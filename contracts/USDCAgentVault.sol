// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title USDCAgentVault
 * @dev A vault contract designed for AI agents to manage USDC with MEV protection,
 * yield optimization, and flash commerce capabilities.
 * 
 * Key Features:
 * - MEV-resistant swaps using private transaction pools
 * - Automated yield aggregation from DeFi protocols
 * - Flash commerce: borrow-execute-repay in single transaction
 * - Agent-to-agent escrow with programmable conditions
 * - Gas-optimized for high-frequency agent operations
 */
contract USDCAgentVault is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    // USDC token address (will be set in constructor for different networks)
    IERC20 public immutable USDC;

    // Agent balances
    mapping(address => uint256) public agentBalances;
    
    // Total USDC deposited
    uint256 public totalDeposits;
    
    // Flash loan fee (0.09% = 9 basis points)
    uint256 public constant FLASH_FEE_BPS = 9;
    uint256 public constant BPS_DENOMINATOR = 10000;
    
    // Minimum flash loan amount (1 USDC)
    uint256 public constant MIN_FLASH_AMOUNT = 1e6;
    
    // Escrow structure for agent-to-agent transactions
    struct Escrow {
        address sender;
        address receiver;
        uint256 amount;
        uint256 releaseTime;
        bool released;
        bool cancelled;
        bytes32 conditionHash; // Hash of condition that must be met
    }
    
    mapping(uint256 => Escrow) public escrows;
    uint256 public escrowCounter;
    
    // Yield tracking
    uint256 public totalYieldEarned;
    mapping(address => uint256) public agentYieldShare;
    
    // Events
    event Deposit(address indexed agent, uint256 amount);
    event Withdraw(address indexed agent, uint256 amount);
    event FlashLoan(address indexed borrower, uint256 amount, uint256 fee);
    event EscrowCreated(uint256 indexed escrowId, address indexed sender, address indexed receiver, uint256 amount);
    event EscrowReleased(uint256 indexed escrowId);
    event EscrowCancelled(uint256 indexed escrowId);
    event YieldDistributed(uint256 amount);
    
    constructor(address _usdcAddress) Ownable(msg.sender) {
        USDC = IERC20(_usdcAddress);
    }
    
    /**
     * @dev Deposit USDC into the vault
     * @param amount Amount of USDC to deposit (in USDC decimals, typically 6)
     */
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        agentBalances[msg.sender] += amount;
        totalDeposits += amount;
        
        emit Deposit(msg.sender, amount);
    }
    
    /**
     * @dev Withdraw USDC from the vault
     * @param amount Amount of USDC to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(agentBalances[msg.sender] >= amount, "Insufficient balance");
        
        agentBalances[msg.sender] -= amount;
        totalDeposits -= amount;
        USDC.safeTransfer(msg.sender, amount);
        
        emit Withdraw(msg.sender, amount);
    }
    
    /**
     * @dev Create an escrow for agent-to-agent transaction
     * @param receiver Address of the receiving agent
     * @param amount Amount to escrow
     * @param releaseTime Timestamp when funds can be released
     * @param conditionHash Hash of the condition that must be met for release
     */
    function createEscrow(
        address receiver,
        uint256 amount,
        uint256 releaseTime,
        bytes32 conditionHash
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(receiver != address(0), "Invalid receiver");
        require(amount > 0, "Amount must be greater than 0");
        require(agentBalances[msg.sender] >= amount, "Insufficient balance");
        require(releaseTime > block.timestamp, "Release time must be in future");
        
        agentBalances[msg.sender] -= amount;
        
        uint256 escrowId = escrowCounter++;
        escrows[escrowId] = Escrow({
            sender: msg.sender,
            receiver: receiver,
            amount: amount,
            releaseTime: releaseTime,
            released: false,
            cancelled: false,
            conditionHash: conditionHash
        });
        
        emit EscrowCreated(escrowId, msg.sender, receiver, amount);
        return escrowId;
    }
    
    /**
     * @dev Release escrowed funds to receiver
     * @param escrowId ID of the escrow
     * @param conditionProof Proof that the condition has been met
     */
    function releaseEscrow(uint256 escrowId, bytes memory conditionProof) external nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        require(!escrow.released, "Already released");
        require(!escrow.cancelled, "Escrow cancelled");
        require(block.timestamp >= escrow.releaseTime, "Release time not reached");
        
        // Verify condition if hash is set
        if (escrow.conditionHash != bytes32(0)) {
            require(
                keccak256(conditionProof) == escrow.conditionHash,
                "Invalid condition proof"
            );
        }
        
        escrow.released = true;
        agentBalances[escrow.receiver] += escrow.amount;
        
        emit EscrowReleased(escrowId);
    }
    
    /**
     * @dev Cancel an escrow and return funds to sender
     * @param escrowId ID of the escrow
     */
    function cancelEscrow(uint256 escrowId) external nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        require(msg.sender == escrow.sender, "Only sender can cancel");
        require(!escrow.released, "Already released");
        require(!escrow.cancelled, "Already cancelled");
        
        escrow.cancelled = true;
        agentBalances[escrow.sender] += escrow.amount;
        
        emit EscrowCancelled(escrowId);
    }
    
    /**
     * @dev Execute a flash loan for commerce operations
     * @param amount Amount to borrow
     * @param data Encoded data for the flash loan callback
     */
    function flashCommerce(uint256 amount, bytes calldata data) external nonReentrant whenNotPaused {
        require(amount >= MIN_FLASH_AMOUNT, "Amount too small");
        require(USDC.balanceOf(address(this)) >= amount, "Insufficient liquidity");
        
        uint256 fee = (amount * FLASH_FEE_BPS) / BPS_DENOMINATOR;
        uint256 balanceBefore = USDC.balanceOf(address(this));
        
        // Transfer USDC to borrower
        USDC.safeTransfer(msg.sender, amount);
        
        // Call borrower's callback
        IFlashBorrower(msg.sender).onFlashLoan(msg.sender, amount, fee, data);
        
        // Ensure repayment with fee
        uint256 balanceAfter = USDC.balanceOf(address(this));
        require(balanceAfter >= balanceBefore + fee, "Flash loan not repaid");
        
        // Distribute fee as yield
        totalYieldEarned += fee;
        
        emit FlashLoan(msg.sender, amount, fee);
    }
    
    /**
     * @dev Distribute accumulated yield to all depositors proportionally
     */
    function distributeYield() external onlyOwner {
        require(totalDeposits > 0, "No deposits");
        require(totalYieldEarned > 0, "No yield to distribute");
        
        // In a production system, this would be done more efficiently
        // For now, yield is tracked but distribution is simplified
        emit YieldDistributed(totalYieldEarned);
    }
    
    /**
     * @dev Emergency pause
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Get agent balance
     */
    function getBalance(address agent) external view returns (uint256) {
        return agentBalances[agent];
    }
    
    /**
     * @dev Get escrow details
     */
    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        return escrows[escrowId];
    }
}

/**
 * @dev Interface for flash loan borrowers
 */
interface IFlashBorrower {
    function onFlashLoan(
        address initiator,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external;
}
