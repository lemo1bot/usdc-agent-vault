const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

async function main() {
    console.log('Starting deployment...\n');

    // Setup provider with custom timeout
    const provider = new ethers.JsonRpcProvider(
        process.env.SEPOLIA_RPC_URL,
        {
            name: 'sepolia',
            chainId: 11155111
        },
        {
            staticNetwork: true,
            timeout: 60000 // 60 second timeout
        }
    );

    // Setup wallet
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    console.log('Deployer address:', wallet.address);

    // Check balance
    const balance = await provider.getBalance(wallet.address);
    console.log('Balance:', ethers.formatEther(balance), 'ETH\n');

    if (balance === 0n) {
        throw new Error('Insufficient balance for deployment');
    }

    // Load compiled contract
    const contractPath = './artifacts/contracts/USDCAgentVault.sol/USDCAgentVault.json';
    const contractJson = JSON.parse(fs.readFileSync(contractPath, 'utf8'));

    // Sepolia USDC address
    const USDC_ADDRESS = '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238';

    console.log('Deploying USDCAgentVault...');
    console.log('USDC Address:', USDC_ADDRESS);

    // Create contract factory
    const factory = new ethers.ContractFactory(
        contractJson.abi,
        contractJson.bytecode,
        wallet
    );

    // Deploy with increased gas limit
    const contract = await factory.deploy(USDC_ADDRESS, {
        gasLimit: 3000000
    });

    console.log('\nTransaction sent!');
    console.log('Transaction hash:', contract.deploymentTransaction().hash);
    console.log('Waiting for confirmations...\n');

    // Wait for deployment
    await contract.waitForDeployment();

    const address = await contract.getAddress();
    console.log('✅ USDCAgentVault deployed to:', address);
    console.log('\nDeployment Details:');
    console.log('- Contract Address:', address);
    console.log('- Transaction Hash:', contract.deploymentTransaction().hash);
    console.log('- Network: Sepolia');
    console.log('- Block Explorer:', `https://sepolia.etherscan.io/address/${address}`);
    console.log('- Transaction:', `https://sepolia.etherscan.io/tx/${contract.deploymentTransaction().hash}`);

    // Save deployment info
    const deploymentInfo = {
        network: 'sepolia',
        contractAddress: address,
        transactionHash: contract.deploymentTransaction().hash,
        deployer: wallet.address,
        usdcAddress: USDC_ADDRESS,
        timestamp: new Date().toISOString(),
        blockExplorer: `https://sepolia.etherscan.io/address/${address}`,
        transactionUrl: `https://sepolia.etherscan.io/tx/${contract.deploymentTransaction().hash}`
    };

    fs.writeFileSync(
        'deployment-info.json',
        JSON.stringify(deploymentInfo, null, 2)
    );

    console.log('\n✅ Deployment info saved to deployment-info.json');
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error('Deployment failed:', error);
        process.exit(1);
    });
