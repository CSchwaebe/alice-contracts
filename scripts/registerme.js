const { ethers } = require("hardhat");

// List of contract addresses to register
// Add or remove addresses as needed
const contractsToRegister = [
    "0x2272dC69009E83396d67146Ac17B1B9669431f0B",
];

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Registering contracts with the account:", deployer.address);

    for (const address of contractsToRegister) {
        try {
            console.log(`\nRegistering contract at ${address}...`);
            
            // Create contract instance with minimal ABI for registerMe function
            const contract = await ethers.getContractAt(
                ["function registerMe() external"],
                address,
                deployer
            );

            // Call registerMe
            const tx = await contract.registerMe();
            await tx.wait();
            
            console.log(`✓ Successfully registered contract at ${address}`);
        } catch (error) {
            console.error(`Failed to register contract at ${address}:`, error.message);
        }
    }

    console.log("\nRegistration process complete!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
