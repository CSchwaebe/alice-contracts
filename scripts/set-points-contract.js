const { ethers } = require("hardhat");

// Configuration - Update these addresses before running
const GAME_MASTER_CONTRACT_ADDRESS = "0x2272dC69009E83396d67146Ac17B1B9669431f0B"; // Replace with deployed GameMaster address
const POINTS_CONTRACT_ADDRESS = "0x2a38f186Ae7A96F3973617BE1704ce0dAcE61857"; // Replace with Points contract address

async function main() {
  console.log("Setting Points Contract in GameMaster");
  console.log("=====================================");
  
  // Validate configuration
  if (GAME_MASTER_CONTRACT_ADDRESS === "0x..." || POINTS_CONTRACT_ADDRESS === "0x...") {
    console.error("❌ Please update the contract addresses in the script configuration");
    process.exit(1);
  }
  
  const [deployer] = await ethers.getSigners();
  console.log("Running with account:", deployer.address);
  console.log("GameMaster Contract:", GAME_MASTER_CONTRACT_ADDRESS);
  console.log("Points Contract:", POINTS_CONTRACT_ADDRESS);
  
  try {
    // Get contract instance
    console.log("\nConnecting to GameMaster contract...");
    const GameMaster = await ethers.getContractFactory("GameMaster");
    const gameMaster = GameMaster.attach(GAME_MASTER_CONTRACT_ADDRESS);
    console.log("✓ Connected to GameMaster contract");
    
    // Verify deployer is owner
    const owner = await gameMaster.owner();
    if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
      console.error(`❌ Deployer (${deployer.address}) is not owner of GameMaster contract (${owner})`);
      process.exit(1);
    }
    console.log("✓ Deployer is owner of GameMaster contract");
    
    // Check current points contract
    const currentPointsContract = await gameMaster.pointsContract();
    console.log(`\nCurrent points contract: ${currentPointsContract}`);
    
    if (currentPointsContract.toLowerCase() === POINTS_CONTRACT_ADDRESS.toLowerCase()) {
      console.log("✓ Points contract is already set correctly");
      return;
    }
    
    // Set the points contract
    console.log("\nSetting points contract...");
    const tx = await gameMaster.setPointsContract(POINTS_CONTRACT_ADDRESS);
    console.log(`Transaction hash: ${tx.hash}`);
    
    // Wait for confirmation
    console.log("Waiting for confirmation...");
    await tx.wait();
    console.log("✓ Transaction confirmed");
    
    // Verify the change
    const newPointsContract = await gameMaster.pointsContract();
    if (newPointsContract.toLowerCase() === POINTS_CONTRACT_ADDRESS.toLowerCase()) {
      console.log("✓ Points contract successfully set");
    } else {
      console.error("❌ Points contract not set correctly");
      process.exit(1);
    }
    
    console.log(`\n🎉 Successfully set points contract to: ${POINTS_CONTRACT_ADDRESS}`);
    
  } catch (error) {
    console.error("\n❌ Failed to set points contract:", error.message);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('\n\nOperation interrupted by user');
  process.exit(1);
});

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Unhandled error:", error);
    process.exit(1);
  }); 