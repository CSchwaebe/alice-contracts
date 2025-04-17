const { ethers } = require("hardhat");

// GameMaster contract address - replace this with the actual deployed address
const GAME_MASTER_ADDRESS = "0x0723c9b3d2fd51E124002430c4216d7A3DeF903D";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying Descend contract with the account:", deployer.address);
  
  if (GAME_MASTER_ADDRESS === "0x0000000000000000000000000000000000000000") {
    console.error("Please set the GAME_MASTER_ADDRESS at the top of the script!");
    process.exit(1);
  }

  // Deploy Descend contract
  console.log("Deploying Descend contract...");
  const Descend = await ethers.getContractFactory("Descend");
  const descend = await Descend.deploy();
  await descend.waitForDeployment();
  const descendAddress = await descend.getAddress();
  console.log("Descend deployed to:", descendAddress);

  // Set GameMaster in Descend contract
  console.log("Setting GameMaster address in Descend contract...");
  await descend.setGameMaster(GAME_MASTER_ADDRESS);
  console.log("GameMaster address set successfully");

  // Get GameMaster contract instance
  const GameMaster = await ethers.getContractFactory("GameMaster");
  const gameMaster = GameMaster.attach(GAME_MASTER_ADDRESS);

  // Register Descend with GameMaster
  console.log("Registering Descend with GameMaster...");
  await gameMaster.registerGame("Descend", descendAddress);
  console.log("Descend registered successfully with GameMaster");

  console.log("\nDeployment Summary:");
  console.log("-------------------");
  console.log("Descend:", descendAddress);
  console.log("GameMaster:", GAME_MASTER_ADDRESS);
  console.log("Deployer:", deployer.address);
  console.log("\nDeployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 