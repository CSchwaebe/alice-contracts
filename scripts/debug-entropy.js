const { ethers } = require("hardhat");

async function debugEntropyCallback() {
  const [deployer] = await ethers.getSigners();
  
  // Configuration - update these with your actual values
  const ENTROPY_ADDRESS = "0xebe57e8045f2f230872523bbff7374986e45c486";
  const CLIMB_CONTRACT = "0x047209426c6B3436F99BfE762974757a38dFf495"; // From your last deployment
  const SEQUENCE_NUMBER = 43623; // From your last test
  const PROVIDER = "0x6CC14824Ea2918f5De5C2f75A9Da968ad4BD6344"; // From your test output
  const CHAIN_ID = "blaze"; // Blaze network
  
  console.log("🔍 Debugging Entropy Callback...");
  console.log("================================");
  console.log(`Entropy Address: ${ENTROPY_ADDRESS}`);
  console.log(`Climb Contract: ${CLIMB_CONTRACT}`);
  console.log(`Sequence Number: ${SEQUENCE_NUMBER}`);
  console.log(`Provider: ${PROVIDER}`);
  console.log(`Chain ID: ${CHAIN_ID}`);

  try {
    // Get the Climb contract
    const climbContract = await ethers.getContractAt("Climb", CLIMB_CONTRACT);
    
    // Check current game state
    console.log("\n📊 Current Game State:");
    const gameState = await climbContract.getPlayerGame(deployer.address);
    console.log(`Current Level: ${gameState.currentLevel}`);
    console.log(`Game Active: ${gameState.isActive}`);
    console.log(`Pending Type: ${gameState.pendingType}`);
    console.log(`Pending Sequence: ${gameState.pendingSequence}`);
    console.log(`Game ID: ${gameState.gameId}`);
    console.log(`Deposit Amount: ${ethers.formatEther(gameState.depositAmount)} ETH`);

    // Fetch provider revelation from Fortuna
    console.log("\n🌐 Fetching provider revelation...");
    const fortunaUrl = `https://fortuna.dourolabs.app/v1/chains/${CHAIN_ID}/revelations/${SEQUENCE_NUMBER}`;
    console.log(`Fetching from: ${fortunaUrl}`);
    
    const response = await fetch(fortunaUrl);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    
    const data = await response.json();
    const providerRevelation = "0x" + data.value.data;
    console.log(`Provider revelation: ${providerRevelation}`);

    // We need the user random number from the original request
    // For debugging, let's use a mock value or try to extract it
    const userRandomNumber = "0xb1db70cfe95d9e823ac591362921c20eb45f136dbf417362f0a045dc7100519e";
    console.log(`Using user random number: ${userRandomNumber}`);

    // Get the Entropy contract
    const entropyABI = [
      "function revealWithCallback(address provider, uint64 sequenceNumber, bytes32 userRandomNumber, bytes32 providerRevelation) external"
    ];
    
    const entropyContract = new ethers.Contract(ENTROPY_ADDRESS, entropyABI, deployer);

    console.log("\n🚀 Manually triggering entropy callback...");
    console.log("==========================================");
    
    // Estimate gas first
    try {
      const gasEstimate = await entropyContract.revealWithCallback.estimateGas(
        PROVIDER,
        SEQUENCE_NUMBER,
        userRandomNumber,
        providerRevelation
      );
      console.log(`⛽ Gas estimate: ${gasEstimate.toString()}`);
    } catch (gasError) {
      console.log("⚠️  Could not estimate gas:", gasError.message);
    }

    // Execute the manual callback
    const tx = await entropyContract.revealWithCallback(
      PROVIDER,
      SEQUENCE_NUMBER,
      userRandomNumber,
      providerRevelation,
      {
        gasLimit: 1000000 // High gas limit for debugging
      }
    );

    console.log(`Transaction hash: ${tx.hash}`);
    console.log("⏳ Waiting for confirmation...");

    const receipt = await tx.wait();
    console.log(`✅ Transaction confirmed in block ${receipt.blockNumber}`);
    console.log(`Gas used: ${receipt.gasUsed.toString()}`);

    // Check if the callback worked
    console.log("\n📊 Updated Game State:");
    const updatedGameState = await climbContract.getPlayerGame(deployer.address);
    console.log(`Current Level: ${updatedGameState.currentLevel}`);
    console.log(`Game Active: ${updatedGameState.isActive}`);
    console.log(`Pending Type: ${updatedGameState.pendingType}`);
    console.log(`Pending Sequence: ${updatedGameState.pendingSequence}`);

    // Check for events
    console.log("\n📜 Checking for events in transaction...");
    for (const log of receipt.logs) {
      try {
        const parsed = climbContract.interface.parseLog(log);
        console.log(`Event: ${parsed.name}`);
        console.log(`Args:`, parsed.args);
      } catch (e) {
        // Not a climb contract event
      }
    }

    console.log("\n✅ Manual callback completed successfully!");

  } catch (error) {
    console.error("❌ Error during manual callback:", error.message);
    
    if (error.reason) {
      console.log(`Revert reason: ${error.reason}`);
    }
    
    if (error.data) {
      console.log(`Revert data: ${error.data}`);
    }

    // Try to decode the revert data
    if (error.data && error.data.startsWith("0x")) {
      console.log("\n🔍 Attempting to decode revert data...");
      try {
        // Common error selectors
        const errorSelectors = {
          "0x08c379a0": "Error(string)", // Standard revert with message
          "0x4e487b71": "Panic(uint256)", // Panic errors
          "0xb8be1a8d": "Unknown custom error"
        };
        
        const selector = error.data.slice(0, 10);
        console.log(`Error selector: ${selector}`);
        
        if (errorSelectors[selector]) {
          console.log(`Error type: ${errorSelectors[selector]}`);
          
          if (selector === "0x08c379a0") {
            // Try to decode the error message
            try {
              const decoded = ethers.AbiCoder.defaultAbiCoder().decode(["string"], "0x" + error.data.slice(10));
              console.log(`Error message: "${decoded[0]}"`);
            } catch (decodeError) {
              console.log("Could not decode error message");
            }
          }
        }
      } catch (decodeError) {
        console.log("Could not decode revert data");
      }
    }
  }
}

debugEntropyCallback()
  .then(() => {
    console.log("✅ Debug script completed!");
    process.exit(0);
  })
  .catch((error) => {
    console.error("❌ Debug script failed:", error);
    process.exit(1);
  }); 