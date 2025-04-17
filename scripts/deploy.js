const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  
  // Deploy Doors contract
  console.log("Deploying Doors contract...");
  const Doors = await ethers.getContractFactory("Doors");
  const doors = await Doors.deploy();
  await doors.waitForDeployment();
  const doorsAddress = await doors.getAddress();
  console.log("Doors deployed to:", doorsAddress);
  
  // Deploy Threes contract
  console.log("Deploying Threes contract...");
  const Threes = await ethers.getContractFactory("Threes");
  const threes = await Threes.deploy();
  await threes.waitForDeployment();
  const threesAddress = await threes.getAddress();
  console.log("Threes deployed to:", threesAddress);
  
  // Deploy Bidding contract
  console.log("Deploying Bidding contract...");
  const Bidding = await ethers.getContractFactory("Bidding");
  const bidding = await Bidding.deploy();
  await bidding.waitForDeployment();
  const biddingAddress = await bidding.getAddress();
  console.log("Bidding deployed to:", biddingAddress);

  // Deploy Descend contract
  console.log("Deploying Descend contract...");
  const Descend = await ethers.getContractFactory("Descend");
  const descend = await Descend.deploy();
  await descend.waitForDeployment();
  const descendAddress = await descend.getAddress();
  console.log("Descend deployed to:", descendAddress);

  // Deploy Equilibrium contract
  console.log("Deploying Equilibrium contract...");
  const Equilibrium = await ethers.getContractFactory("Equilibrium");
  const equilibrium = await Equilibrium.deploy();
  await equilibrium.waitForDeployment();
  const equilibriumAddress = await equilibrium.getAddress();
  console.log("Equilibrium deployed to:", equilibriumAddress);
  
  // Deploy GameMaster contract
  console.log("Deploying GameMaster contract...");
  const GameMaster = await ethers.getContractFactory("GameMaster");
  const gameMaster = await GameMaster.deploy();
  await gameMaster.waitForDeployment();
  const gameMasterAddress = await gameMaster.getAddress();
  console.log("GameMaster deployed to:", gameMasterAddress);

  // Setup contract relationships
  console.log("Setting up contract relationships...");
  
  // Register Doors game with GameMaster
  await gameMaster.registerGame("Doors", doorsAddress);
  console.log("Registered Doors game with GameMaster");

  // Register Threes game with GameMaster
  await gameMaster.registerGame("Threes", threesAddress);
  console.log("Registered Threes game with GameMaster");

  // Register Bidding game with GameMaster
  await gameMaster.registerGame("Bidding", biddingAddress);
  console.log("Registered Bidding game with GameMaster");

  // Register Descend game with GameMaster
  await gameMaster.registerGame("Descend", descendAddress);
  console.log("Registered Descend game with GameMaster");

  // Register Equilibrium game with GameMaster
  await gameMaster.registerGame("Equilibrium", equilibriumAddress);
  console.log("Registered Equilibrium game with GameMaster");

  // Set GameMaster in game contracts
  await doors.setGameMaster(gameMasterAddress);
  await threes.setGameMaster(gameMasterAddress);
  await bidding.setGameMaster(gameMasterAddress);
  await descend.setGameMaster(gameMasterAddress);
  await equilibrium.setGameMaster(gameMasterAddress);
  console.log("Set GameMaster in all game contracts");

  // Register 10 players
  console.log("\nRegistering 10 players...");
  
  // Create array of 10 placeholder private keys (replace these with real private keys)
  const playerPrivateKeys = [
    "0x8161a06b8f4aab4e96616c26f6ba612cb0539e7ccac8c9cbf260924a57365d8d", // Player 1
    "0xbfb8a468dd0f49ace88d2538160a45b1bc2e7fb0dccf72fd65bfd0b9ad2b9b68", // Player 2
    "0x864a94ba503d72fcf5b2d52f531ce0ef38f07fdbdd93dcbcfa49f89548590ef7", // Player 3
    //"0x02b9c40dd12ed6dc8d1a70e84b0f8aed9be884ce59b2c5559f8cf0d9dc9e735d", // Player 4
    //"0x39ed31d96c47a4c5546ce62dc20d8a270056d6addb3a865757f9fd480a5d44ed", // Player 5
    //"0x8e74215d3d2a38344f2c6e3e9cb948ba6d045a7f89151edc2ddf32b7ee988b5a", // Player 6
    //"0x3c0bf01e3db7f9ad15de75e94499ab46a023850a91d81ca136f544b33e7cb028", // Player 7
    //"0x5f033aa0f01e801e3068419ec857e055334c42c5221a80fdb98e14a2e425cbff", // Player 8
    //"0xae0f283314e986fd37a3f27f7299725d524660f95a4ffbbec8af5906216ef40f", // Player 9
    //"0xf6075be03f88dcab5fb577457960dff4fe35cd447907131700f245e99f6f17f9"  // Player 10
  ];

  // Get registration fee
  const registrationFee = await gameMaster.registrationFee();
  console.log("Registration fee:", ethers.formatEther(registrationFee), "ETH");

  // Fund and register each player
  for (let i = 0; i < playerPrivateKeys.length; i++) {
    const playerWallet = new ethers.Wallet(playerPrivateKeys[i], ethers.provider);
    console.log(`\nProcessing player ${i + 1} (${playerWallet.address})...`);
    
    // Send 0.12 ETH to the player wallet
    await deployer.sendTransaction({
      to: playerWallet.address,
      value: ethers.parseEther("0.12")
    });
    
    // Register the player
    const playerGameMaster = gameMaster.connect(playerWallet);
    await playerGameMaster.register({ value: registrationFee });
    console.log(`Player ${i + 1} funded and registered successfully!`);
  }

  console.log("\nDeployment Summary:");
  console.log("-------------------");
  console.log("Doors:", doorsAddress);
  console.log("Threes:", threesAddress);
  console.log("Bidding:", biddingAddress);
  console.log("Descend:", descendAddress);
  console.log("Equilibrium:", equilibriumAddress);
  console.log("GameMaster:", gameMasterAddress);
  console.log("\nRegistered Players:", playerPrivateKeys.length);
  console.log("Each player received: 0.12 ETH");
  console.log("\nDeployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
