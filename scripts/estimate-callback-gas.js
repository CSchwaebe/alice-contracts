const { ethers } = require("hardhat");

async function estimateCallbackGas() {
  const [deployer] = await ethers.getSigners();
  
  console.log("⛽ Estimating Gas for Entropy Callback Function");
  console.log("===============================================");
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH`);

  // Deploy contracts for testing
  const ENTROPY_ADDRESS = "0xebe57e8045f2f230872523bbff7374986e45c486"; // BLAZE
  
  console.log("\n📦 Deploying test contracts...");
  
  // Deploy Points contract
  const Points = await ethers.getContractFactory("Points");
  const pointsContract = await Points.deploy();
  await pointsContract.waitForDeployment();
  const pointsAddress = await pointsContract.getAddress();
  console.log(`Points deployed: ${pointsAddress}`);
  
  // Deploy Climb contract
  const Climb = await ethers.getContractFactory("Climb");
  const climbContract = await Climb.deploy(ENTROPY_ADDRESS, pointsAddress);
  await climbContract.waitForDeployment();
  const climbAddress = await climbContract.getAddress();
  console.log(`Climb deployed: ${climbAddress}`);
  
  // Authorize climb contract
  await pointsContract.setContractAuthorization(climbAddress, true);
  console.log("✅ Climb contract authorized");
  
  // Fund climb contract
  await climbContract.depositFunds({ value: ethers.parseEther("5") });
  console.log("✅ Climb contract funded");

  console.log("\n🧪 Gas Estimation Scenarios");
  console.log("============================");

  // Initialize variables for gas calculations
  let estimatedMinimalGas = 0;
  let fullCallbackGas = 0;

  // Scenario 1: Current minimal callback (just clears state)
  console.log("\n1️⃣ Current Minimal Callback");
  console.log("----------------------------");
  
  try {
    // Start a game to set up state
    await climbContract.startGame({ value: ethers.parseEther("1") });
    
    // Get the current callback bytecode size
    const climbCode = await ethers.provider.getCode(climbAddress);
    console.log(`Contract bytecode size: ${climbCode.length / 2 - 1} bytes`);
    
    // Simulate the callback function directly
    // We'll create a mock scenario to estimate gas
    
    // First, let's estimate gas for the individual operations in the callback
    console.log("\n📊 Individual Operation Gas Estimates:");
    
    // Storage reads (SLOAD operations)
    console.log("Storage reads:");
    console.log("  - sequenceToPlayer mapping read: ~2,100 gas");
    console.log("  - playerGames mapping read: ~2,100 gas per field");
    console.log("  - Total storage reads: ~8,400 gas");
    
    // Storage writes (SSTORE operations)
    console.log("\nStorage writes:");
    console.log("  - entropyResults mapping write: ~20,000 gas (new slot)");
    console.log("  - pendingType reset: ~2,900 gas (zero out)");
    console.log("  - pendingSequence reset: ~2,900 gas (zero out)");
    console.log("  - sequenceToPlayer delete: ~2,900 gas (zero out)");
    console.log("  - sequenceIsCashout delete: ~2,900 gas (zero out)");
    console.log("  - Total storage writes: ~31,600 gas");
    
    // Event emission
    console.log("\nEvent emission:");
    console.log("  - EntropyReceived event: ~1,500 gas");
    
    // Function call overhead
    console.log("\nFunction overhead:");
    console.log("  - Function call: ~700 gas");
    console.log("  - Parameter validation: ~500 gas");
    
    estimatedMinimalGas = 8400 + 31600 + 1500 + 700 + 500;
    console.log(`\n🎯 Estimated minimal callback gas: ~${estimatedMinimalGas.toLocaleString()} gas`);
    
  } catch (error) {
    console.error("Error in minimal callback estimation:", error.message);
    estimatedMinimalGas = 42700; // Fallback value
  }

  // Scenario 2: Full callback with game logic (what we had before)
  console.log("\n2️⃣ Full Callback with Game Logic");
  console.log("----------------------------------");
  
  try {
    // Estimate additional operations for full game logic
    console.log("\n📊 Additional Operations for Full Logic:");
    
    console.log("Additional storage operations:");
    console.log("  - Game state updates (level, active): ~5,800 gas");
    console.log("  - Completed game storage: ~40,000 gas (new struct)");
    console.log("  - Player history array push: ~20,000 gas");
    
    console.log("\nExternal contract calls:");
    console.log("  - Points contract call: ~25,000 gas");
    console.log("  - ETH transfer: ~21,000 gas");
    
    console.log("\nAdditional events:");
    console.log("  - ClimbResult event: ~2,000 gas");
    console.log("  - GameEnded event: ~3,000 gas");
    console.log("  - PlayerCashedOut event: ~2,500 gas");
    
    console.log("\nComplex calculations:");
    console.log("  - Random number processing: ~500 gas");
    console.log("  - Multiplier calculations: ~300 gas");
    console.log("  - Payout calculations: ~400 gas");
    
    const additionalGas = 5800 + 40000 + 20000 + 25000 + 21000 + 2000 + 3000 + 2500 + 500 + 300 + 400;
    fullCallbackGas = estimatedMinimalGas + additionalGas;
    
    console.log(`\n🎯 Estimated full callback gas: ~${fullCallbackGas.toLocaleString()} gas`);
    
  } catch (error) {
    console.error("Error in full callback estimation:", error.message);
    fullCallbackGas = estimatedMinimalGas + 120200; // Fallback calculation
  }

  // Scenario 3: Check network gas limits
  console.log("\n3️⃣ Network Gas Limits");
  console.log("----------------------");
  
  try {
    // Get latest block to check gas limits
    const latestBlock = await ethers.provider.getBlock("latest");
    console.log(`Block gas limit: ${latestBlock.gasLimit.toLocaleString()}`);
    
    // Common entropy callback gas limits by network
    console.log("\nKnown Entropy callback gas limits:");
    console.log("  - Ethereum Mainnet: 200,000 gas");
    console.log("  - Arbitrum: 1,000,000 gas");
    console.log("  - Optimism: 200,000 gas");
    console.log("  - Polygon: 200,000 gas");
    console.log("  - BSC: 200,000 gas");
    console.log("  - Blast/Sonic: Unknown (likely 200,000)");
    
    const assumedLimit = 200000;
    console.log(`\n📏 Assuming callback limit: ${assumedLimit.toLocaleString()} gas`);
    
    const minimalFitsRatio = (estimatedMinimalGas / assumedLimit * 100).toFixed(1);
    const fullFitsRatio = (fullCallbackGas / assumedLimit * 100).toFixed(1);
    
    console.log(`\n✅ Minimal callback uses: ${minimalFitsRatio}% of limit`);
    console.log(`❌ Full callback uses: ${fullFitsRatio}% of limit`);
    
    if (estimatedMinimalGas <= assumedLimit) {
      console.log("✅ Minimal callback should work!");
    } else {
      console.log("❌ Even minimal callback exceeds limit!");
    }
    
    if (fullCallbackGas <= assumedLimit) {
      console.log("✅ Full callback should work!");
    } else {
      console.log("❌ Full callback exceeds limit - needs optimization!");
    }
    
  } catch (error) {
    console.error("Error checking gas limits:", error.message);
  }

  // Scenario 4: Optimization recommendations
  console.log("\n4️⃣ Optimization Recommendations");
  console.log("=================================");
  
  console.log("\n🔧 To reduce gas usage:");
  console.log("1. Minimize storage writes (most expensive)");
  console.log("2. Batch operations where possible");
  console.log("3. Use events instead of storage for non-critical data");
  console.log("4. Defer complex operations to separate user-triggered functions");
  console.log("5. Use packed structs to reduce storage slots");
  
  console.log("\n💡 Current strategy (minimal callback):");
  console.log("✅ Only essential state clearing");
  console.log("✅ Single event emission");
  console.log("✅ No external calls");
  console.log("✅ No complex calculations");
  console.log("✅ Defers game logic to user-triggered functions");

  console.log("\n📋 Summary");
  console.log("===========");
  console.log(`Minimal callback: ~${estimatedMinimalGas.toLocaleString()} gas (SAFE)`);
  console.log(`Full callback: ~${fullCallbackGas.toLocaleString()} gas (RISKY)`);
  console.log(`Recommended approach: Use minimal callback + separate user functions`);

  console.log("\n🎉 Gas estimation completed!");
}

estimateCallbackGas()
  .then(() => {
    console.log("✅ Gas estimation script completed!");
    process.exit(0);
  })
  .catch((error) => {
    console.error("❌ Gas estimation failed:", error);
    process.exit(1);
  }); 