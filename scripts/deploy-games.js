const { ethers } = require("hardhat");

// Configuration - Edit this section
const GAMEMASTER_ADDRESS = "0x951F246C01bbD289A5894D9c5Fd645549c51df01"; // Replace with your GameMaster address

// Helper function to deploy a contract
async function deployContract(name, args = []) {
  console.log(`Deploying ${name} contract...`);
  const Contract = await ethers.getContractFactory(name);
  const contract = await Contract.deploy(...args);
  await contract.waitForDeployment();
  const address = await contract.getAddress();
  console.log(`${name} deployed to:`, address);
  return contract;
}

// Helper function to register a game with GameMaster
async function registerGame(gameMaster, name, address) {
  await gameMaster.registerGame(name, address);
  console.log(`Registered ${name} game with GameMaster`);
}

// Helper function to set GameMaster in a game contract
async function setGameMaster(game, gameMasterAddress) {
  await game.setGameMaster(gameMasterAddress);
}

// Helper function to call registerMe on a game contract
async function callRegisterMe(game, name) {
  await game.registerMe();
  console.log(`Called registerMe on ${name} game`);
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying games with the account:", deployer.address);

  // Get the existing GameMaster contract
  const gameMaster = await ethers.getContractAt("GameMaster", GAMEMASTER_ADDRESS);
  console.log("Connected to GameMaster at:", GAMEMASTER_ADDRESS);

  // Deploy all game contracts
  const doors = await deployContract("Doors");
  const threes = await deployContract("Threes");
  const bidding = await deployContract("Bidding");
  const descend = await deployContract("Descend");
  const equilibrium = await deployContract("Equilibrium");

  // Setup contract relationships
  console.log("\nSetting up game/master relationships...");
  
  // Register games with GameMaster
  await registerGame(gameMaster, "Doors", await doors.getAddress());
  await registerGame(gameMaster, "Threes", await threes.getAddress());
  await registerGame(gameMaster, "Bidding", await bidding.getAddress());
  await registerGame(gameMaster, "Descend", await descend.getAddress());
  await registerGame(gameMaster, "Equilibrium", await equilibrium.getAddress());

  // Set GameMaster in all game contracts
  await setGameMaster(doors, GAMEMASTER_ADDRESS);
  await setGameMaster(threes, GAMEMASTER_ADDRESS);
  await setGameMaster(bidding, GAMEMASTER_ADDRESS);
  await setGameMaster(descend, GAMEMASTER_ADDRESS);
  await setGameMaster(equilibrium, GAMEMASTER_ADDRESS);
  console.log("Set GameMaster in all game contracts");

  // Call registerMe on all game contracts
  console.log("\nCalling registerMe on all game contracts...");
  await callRegisterMe(doors, "Doors");
  await callRegisterMe(threes, "Threes");
  await callRegisterMe(bidding, "Bidding");
  await callRegisterMe(descend, "Descend");
  await callRegisterMe(equilibrium, "Equilibrium");
  console.log("Called registerMe on all game contracts");

  // Print deployment summary
  console.log("\nDeployment Summary:");
  console.log("-------------------");
  console.log("Doors:", await doors.getAddress());
  console.log("Threes:", await threes.getAddress());
  console.log("Bidding:", await bidding.getAddress());
  console.log("Descend:", await descend.getAddress());
  console.log("Equilibrium:", await equilibrium.getAddress());
  console.log("GameMaster:", GAMEMASTER_ADDRESS);

  console.log("\nDeployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
