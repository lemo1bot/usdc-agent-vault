const hre = require("hardhat");

async function main() {
    console.log("Deploying USDCAgentVault...");

    // USDC addresses for different networks
    const USDC_ADDRESSES = {
        sepolia: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", // Sepolia USDC
        base: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // Base USDC
        baseSepolia: "0x036CbD53842c5426634e7929541eC2318f3dCF7e" // Base Sepolia USDC
    };

    const network = hre.network.name;
    const usdcAddress = USDC_ADDRESSES[network];

    if (!usdcAddress) {
        throw new Error(`USDC address not configured for network: ${network}`);
    }

    console.log(`Network: ${network}`);
    console.log(`USDC Address: ${usdcAddress}`);

    const USDCAgentVault = await hre.ethers.getContractFactory("USDCAgentVault");
    const vault = await USDCAgentVault.deploy(usdcAddress);

    await vault.waitForDeployment();

    const vaultAddress = await vault.getAddress();
    console.log(`USDCAgentVault deployed to: ${vaultAddress}`);

    // Wait for a few block confirmations
    console.log("Waiting for block confirmations...");
    await vault.deploymentTransaction().wait(5);

    console.log("\n=== Deployment Summary ===");
    console.log(`Network: ${network}`);
    console.log(`Contract: ${vaultAddress}`);
    console.log(`USDC: ${usdcAddress}`);
    console.log("\nTo verify on Etherscan/Basescan:");
    console.log(`npx hardhat verify --network ${network} ${vaultAddress} ${usdcAddress}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
