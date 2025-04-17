const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying GameMaster contract with the account:", deployer.address);
  
  // Deploy GameMaster contract
  console.log("Deploying GameMaster contract...");
  const GameMaster = await ethers.getContractFactory("GameMaster");
  const gameMaster = await GameMaster.deploy();
  await gameMaster.waitForDeployment();
  const gameMasterAddress = await gameMaster.getAddress();
  console.log("GameMaster deployed to:", gameMasterAddress);

  console.log("\nDeployment Summary:");
  console.log("-------------------");
  console.log("GameMaster:", gameMasterAddress);
  console.log("Deployer:", deployer.address);
  console.log("\nDeployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 