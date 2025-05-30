const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

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

// Helper function to fund players
async function fundPlayers(deployer, playerPrivateKeys, amount) {
  console.log("\nFunding players...");
  for (let i = 0; i < playerPrivateKeys.length; i++) {
    const playerWallet = new ethers.Wallet(
      playerPrivateKeys[i],
      ethers.provider
    );
    console.log(`Funding player ${i + 1} (${playerWallet.address})...`);
    await deployer.sendTransaction({
      to: playerWallet.address,
      value: ethers.parseEther(amount.toString()),
    });
  }
  console.log("✓ All players funded successfully!");
}

// Helper function to register players
async function registerPlayers(
  gameMaster,
  points,
  playerPrivateKeys,
  referralCode
) {
  console.log("\nRegistering players...");
  const registrationFee = await gameMaster.registrationFee();

  for (let i = 0; i < playerPrivateKeys.length; i++) {
    const playerWallet = new ethers.Wallet(
      playerPrivateKeys[i],
      ethers.provider
    );
    console.log(`Registering player ${i + 1} (${playerWallet.address})...`);

    const playerGameMaster = gameMaster.connect(playerWallet);

    await playerGameMaster.registerWithReferral(referralCode, {
      value: registrationFee,
      gasLimit: 600_000,
    });

    console.log(`✓ Player ${i + 1} registered successfully!`);
  }
  console.log("✓ All players registered successfully!");
}

// Helper function to withdraw funds from contracts
async function withdrawFromContracts(gameMaster, points) {
  console.log("\nWithdrawing ETH from contracts...");

  const gameMasterAddress = await gameMaster.getAddress();
  const pointsAddress = await points.getAddress();

  // Withdraw from GameMaster
  console.log("Withdrawing from GameMaster...");
  const gameMasterBalance = await ethers.provider.getBalance(gameMasterAddress);
  if (gameMasterBalance > 0) {
    await gameMaster.withdraw();
    console.log(
      `✓ Successfully withdrew ${ethers.formatEther(
        gameMasterBalance
      )} ETH from GameMaster`
    );
  } else {
    console.log("No ETH to withdraw from GameMaster");
  }

  /*
  // Withdraw from Points
  console.log("Withdrawing from Points...");
  const pointsBalance = await ethers.provider.getBalance(pointsAddress);
  if (pointsBalance > 0) {
    await points.withdraw();
    console.log(
      `✓ Successfully withdrew ${ethers.formatEther(
        pointsBalance
      )} ETH from Points`
    );
  } else {
    console.log("No ETH to withdraw from Points");
  }
    */
}

// Helper function to write environment variables
async function writeEnvFile(contracts) {
  const envPath = "/Users/channing/Documents/GitHub/ragnarok/.env.development";
  console.log("\nWriting environment variables to:", envPath);

  const envContent = `NEXT_PUBLIC_FIREBASE_API_KEY="AIzaSyA2RjVjrert4yVYn9ShDrRSEpQvqGDsnoU"
NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN="ragnarok-58977.firebaseapp.com"
NEXT_PUBLIC_FIREBASE_DATABASE_URL="https://ragnarok-58977-default-rtdb.firebaseio.com"
NEXT_PUBLIC_FIREBASE_PROJECT_ID="ragnarok-58977"
FIREBASE_STORAGE_BUCKET="ragnarok-58977.firebasestorage.app"
FIREBASE_MESSAGING_SENDER_ID="706324277802"
FIREBASE_APP_ID="1:706324277802:web:05763e1e0dc8317ad83153"
FIREBASE_MEASUREMENT_ID="G-44E0MHL32H"

ALCHEMY_API_URL="https://sonic-blaze.g.alchemy.com/v2/GdeOJcP1A5nVB4VsMm4KN0wDVA2yy6iL"

NEXT_PUBLIC_APPKIT_PROJECT_ID="7f02c5df8e9d779de7cfa8d56660538f"

NEXT_PUBLIC_CONTRACT_ADDR_GAME_DOORS="${contracts.doors}"
NEXT_PUBLIC_CONTRACT_ADDR_GAME_THREES="${contracts.threes}"
NEXT_PUBLIC_CONTRACT_ADDR_GAME_BIDDING="${contracts.bidding}"
NEXT_PUBLIC_CONTRACT_ADDR_GAME_DESCEND="${contracts.descend}"
NEXT_PUBLIC_CONTRACT_ADDR_EQUILIBRIUM="${contracts.equilibrium}"

NEXT_PUBLIC_CONTRACT_ADDR_GAMEMASTER="${contracts.gameMaster}"
NEXT_PUBLIC_CONTRACT_ADDR_POINTS="${contracts.points}"

SUPER_SECRET_SALT="fourpercentTREDfourpercentTRED69"`;

  fs.writeFileSync(envPath, envContent);
  console.log("Environment variables written successfully");
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const gameMaster = await deployContract("GameMaster");
  const points = await deployContract("Points");

  // Set Points contract in GameMaster
  await gameMaster.setPointsContract(await points.getAddress());
  console.log("Points contract set in GameMaster");

  // Register referral code for deployer
  console.log("\nRegistering referral code for deployer...");
  const deployerPoints = points.connect(deployer);
  await deployerPoints.registerReferralCode("coff33blak");
  console.log("✓ Referral code 'coff33blak' registered for deployer");

  // Player setup
  const playerPrivateKeys = [
    "0x8161a06b8f4aab4e96616c26f6ba612cb0539e7ccac8c9cbf260924a57365d8d", // Player 1

    "0xbfb8a468dd0f49ace88d2538160a45b1bc2e7fb0dccf72fd65bfd0b9ad2b9b68", // Player 2
    
    "0x864a94ba503d72fcf5b2d52f531ce0ef38f07fdbdd93dcbcfa49f89548590ef7", // Player 3
    "0x02b9c40dd12ed6dc8d1a70e84b0f8aed9be884ce59b2c5559f8cf0d9dc9e735d", // Player 4
    "0x39ed31d96c47a4c5546ce62dc20d8a270056d6addb3a865757f9fd480a5d44ed", // Player 5
    "0x8e74215d3d2a38344f2c6e3e9cb948ba6d045a7f89151edc2ddf32b7ee988b5a", // Player 6
    "0x3c0bf01e3db7f9ad15de75e94499ab46a023850a91d81ca136f544b33e7cb028", // Player 7
    "0x5f033aa0f01e801e3068419ec857e055334c42c5221a80fdb98e14a2e425cbff", // Player 8
    "0xae0f283314e986fd37a3f27f7299725d524660f95a4ffbbec8af5906216ef40f", // Player 9
    
    //"0xf6075be03f88dcab5fb577457960dff4fe35cd447907131700f245e99f6f17f9"  // Player 10
  ];

  // Fund and register players
  await fundPlayers(deployer, playerPrivateKeys, 13);
  await registerPlayers(gameMaster, points, playerPrivateKeys, "coff33blak");

  // Deploy all contracts
  const doors = await deployContract("Doors");
  const threes = await deployContract("Threes");
  const bidding = await deployContract("Bidding");
  const descend = await deployContract("Descend");
  const equilibrium = await deployContract("Equilibrium");

  // Setup contract relationships
  console.log("Setting up game/master relationships...");
  // Register games with GameMaster
  const gameMasterAddress = await gameMaster.getAddress();
  await registerGame(gameMaster, "Doors", await doors.getAddress());
  await registerGame(gameMaster, "Threes", await threes.getAddress());
  await registerGame(gameMaster, "Bidding", await bidding.getAddress());
  await registerGame(gameMaster, "Descend", await descend.getAddress());
  await registerGame(gameMaster, "Equilibrium", await equilibrium.getAddress());

  // Set GameMaster in all game contracts
  await setGameMaster(doors, gameMasterAddress);
  await setGameMaster(threes, gameMasterAddress);
  await setGameMaster(bidding, gameMasterAddress);
  await setGameMaster(descend, gameMasterAddress);
  await setGameMaster(equilibrium, gameMasterAddress);
  console.log("Set GameMaster in all game contracts");

  // Print deployment summary
  console.log("\nDeployment Summary:");
  console.log("-------------------");
  console.log("Doors:", await doors.getAddress());
  console.log("Threes:", await threes.getAddress());
  console.log("Bidding:", await bidding.getAddress());
  console.log("Descend:", await descend.getAddress());
  console.log("Equilibrium:", await equilibrium.getAddress());
  console.log("GameMaster:", gameMasterAddress);
  console.log("Points:", await points.getAddress());
  console.log("\nRegistered Players:", playerPrivateKeys.length);
  console.log("Each player received: 13 ETH");

  // Withdraw funds from contracts
  await withdrawFromContracts(gameMaster, points);

  // Write environment variables
  await writeEnvFile({
    doors: await doors.getAddress(),
    threes: await threes.getAddress(),
    bidding: await bidding.getAddress(),
    descend: await descend.getAddress(),
    equilibrium: await equilibrium.getAddress(),
    gameMaster: gameMasterAddress,
    points: await points.getAddress()
  });

  console.log("\nDeployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
