const { ethers } = require("hardhat");

// Helper function to deploy a contract
async function deployContract(name, args = []) {
  console.log(`Deploying ${name}...`);
  const Contract = await ethers.getContractFactory(name);
  const contract = await Contract.deploy(...args);
  await contract.waitForDeployment();
  const address = await contract.getAddress();
  console.log(`${name} deployed to: ${address}`);
  return contract;
}

// Simplified event waiting function
async function waitForGameEvents(climbContract, sequenceNumber, timeoutMs = 10000) {
  console.log(`⏳ Waiting for entropy callback (sequence: ${sequenceNumber})...`);
  
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      climbContract.removeAllListeners();
      reject(new Error("Timeout waiting for events"));
    }, timeoutMs);

    let result = { entropy: null, climb: null, cashout: null, gameEnd: null, autoClimb: null };

    // Listen for entropy received
    climbContract.once("EntropyReceived", (player, gameId, sequence, randomNumber) => {
      console.log(`🎲 Entropy received: ${randomNumber}`);
      result.entropy = { player, gameId, sequence, randomNumber };
    });

    // Listen for climb result
    climbContract.once("ClimbResult", (player, gameId, fromLevel, newLevel, success, gameEnded, randomNumber) => {
      console.log(`🎯 Climb: ${fromLevel} → ${newLevel}, Success: ${success ? '✅' : '❌'}`);
      result.climb = { player, gameId, fromLevel, newLevel, success, gameEnded, randomNumber };
      
      if (gameEnded || result.entropy) {
        clearTimeout(timeout);
        climbContract.removeAllListeners();
        resolve(result);
      }
    });

    // Listen for cashout
    climbContract.once("PlayerCashedOut", (player, gameId, level, multiplierValue, payout, paidInPoints) => {
      const payoutType = paidInPoints ? "Points" : "ETH";
      const amount = paidInPoints ? payout.toString() : ethers.formatEther(payout);
      console.log(`💰 Cashout: ${amount} ${payoutType} (${multiplierValue}x)`);
      result.cashout = { player, gameId, level, multiplierValue, payout, paidInPoints };
      
      if (result.entropy) {
        clearTimeout(timeout);
        climbContract.removeAllListeners();
        resolve(result);
      }
    });

    // Listen for auto-climb completion
    climbContract.once("AutoClimbCompleted", (player, gameId, startLevel, finalLevel, targetLevel, reachedTarget) => {
      console.log(`🏁 Auto-climb: ${startLevel} → ${finalLevel}, Target: ${targetLevel}, Success: ${reachedTarget ? '✅' : '❌'}`);
      result.autoClimb = { player, gameId, startLevel, finalLevel, targetLevel, reachedTarget };
      
      if (result.entropy) {
        clearTimeout(timeout);
        climbContract.removeAllListeners();
        resolve(result);
      }
    });

    // Listen for game ended
    climbContract.once("GameEnded", (data) => {
      console.log(`🏁 Game ended: ${data.endReason}`);
      result.gameEnd = data;
    });
  });
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("🚀 Starting Climb contract deployment...");
  console.log("Deployer:", deployer.address);
  
  const initialBalance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.formatEther(initialBalance), "ETH");

  //const ENTROPY_ADDRESS = "0xebe57e8045f2f230872523bbff7374986e45c486";
  const ENTROPY_ADDRESS = "0x36825bf3fbdf5a29e2d5148bfe7dcf7b5639e320";


  try {
    // 1. Deploy contracts
    console.log("\n📊 Deploying Contracts...");
    const pointsContract = await deployContract("Points", []);
    const climbContract = await deployContract("Climb", [ENTROPY_ADDRESS, await pointsContract.getAddress()]);

    const pointsAddress = await pointsContract.getAddress();
    const climbAddress = await climbContract.getAddress();

    // 2. Setup and fund
    console.log("\n🔗 Setting up contracts...");
    const authTx = await pointsContract.setContractAuthorization(climbAddress, true);
    await authTx.wait();
    console.log("✅ Climb contract authorized");

    const fundAmount = ethers.parseEther("5");
    const fundTx = await climbContract.depositFunds({ value: fundAmount });
    await fundTx.wait();
    console.log(`✅ Funded with ${ethers.formatEther(fundAmount)} ETH`);

    // 3. Display basic info
    console.log("\n⚙️ Contract Info:");
    const minDeposit = await climbContract.MIN_DEPOSIT();
    const maxDeposit = await climbContract.maxDeposit();
    const contractBalance = await climbContract.getContractBalance();
    console.log(`Min/Max Deposit: ${ethers.formatEther(minDeposit)} - ${ethers.formatEther(maxDeposit)} ETH`);
    console.log(`Contract Balance: ${ethers.formatEther(contractBalance)} ETH`);

    // Get entropy fee
    const entropyABI = [
      "function getDefaultProvider() external view returns (address)",
      "function getFee(address provider) external view returns (uint256)"
    ];
    const entropyContract = new ethers.Contract(ENTROPY_ADDRESS, entropyABI, deployer);
    const defaultProvider = await entropyContract.getDefaultProvider();
    const fee = await entropyContract.getFee(defaultProvider);
    console.log(`Entropy fee: ${ethers.formatEther(fee)} ETH`);

    // 4. Test basic gameplay
    console.log("\n🎮 Testing Basic Gameplay...");
    
    // Test 1: Single climb and cashout
    console.log("\n--- Test 1: Climb and Cashout ---");
    const startTx1 = await climbContract.startGame({ value: ethers.parseEther("1") });
    await startTx1.wait();
    console.log("✅ Game started");

    const climbTx1 = await climbContract.climb({ value: fee });
    const climbReceipt1 = await climbTx1.wait();

        // Extract sequence number
    let sequenceNumber1;
    const requestEvent1 = climbReceipt1.logs.find(log => {
          try {
            const parsed = climbContract.interface.parseLog(log);
            return parsed.name === "RequestAttempted";
      } catch { return false; }
    });
    
    if (requestEvent1) {
      sequenceNumber1 = climbContract.interface.parseLog(requestEvent1).args.data.sequenceNumber;
      
      try {
        const result1 = await waitForGameEvents(climbContract, sequenceNumber1);
        
        if (result1.climb && result1.climb.success) {
          console.log("✅ Climb successful, attempting cashout...");
          
          const cashoutTx = await climbContract.cashOut({ value: fee });
            const cashoutReceipt = await cashoutTx.wait();

          const cashoutEvent = cashoutReceipt.logs.find(log => {
              try {
                const parsed = climbContract.interface.parseLog(log);
                return parsed.name === "RequestAttempted";
            } catch { return false; }
          });
          
          if (cashoutEvent) {
            const cashoutSequence = climbContract.interface.parseLog(cashoutEvent).args.data.sequenceNumber;
            await waitForGameEvents(climbContract, cashoutSequence);
            console.log("✅ Test 1 completed");
          }
        } else {
          console.log("❌ Climb failed - bust (got 10 consolation points)");
        }
      } catch (error) {
        console.log(`❌ Test 1 error: ${error.message}`);
      }
    }

    // Test 2: Auto-climb
    console.log("\n--- Test 2: Auto-Climb ---");
    
    // Start new game for auto-climb
    const currentGame = await climbContract.getPlayerGame(deployer.address);
    if (!currentGame.isActive) {
      const startTx2 = await climbContract.startGame({ value: ethers.parseEther("1") });
      await startTx2.wait();
      console.log("✅ New game started for auto-climb");
    }

    // Test auto-climb to level 3
      const canAutoClimb = await climbContract.canPlayerAutoClimb(deployer.address, 3);
      if (canAutoClimb) {
        const successProb = await climbContract.getAutoClimbSuccessProbability(deployer.address, 3);
      console.log(`Auto-climbing to level 3 (${(Number(successProb) / 100).toFixed(2)}% success rate)...`);
      
      const autoClimbTx = await climbContract.autoClimb(3, { value: fee });
        const autoClimbReceipt = await autoClimbTx.wait();

      const autoEvent = autoClimbReceipt.logs.find(log => {
          try {
            const parsed = climbContract.interface.parseLog(log);
            return parsed.name === "RequestAttempted";
        } catch { return false; }
      });
      
      if (autoEvent) {
        const autoSequence = climbContract.interface.parseLog(autoEvent).args.data.sequenceNumber;
        
        try {
          const autoResult = await waitForGameEvents(climbContract, autoSequence);
          if (autoResult.autoClimb) {
            console.log("✅ Test 2 completed");
          }
        } catch (error) {
          console.log(`❌ Test 2 error: ${error.message}`);
        }
      }
    } else {
      console.log("❌ Cannot auto-climb from current state");
    }

    // Test 3: Quick test of multiple attempts to see different outcomes
    console.log("\n--- Test 3: Multiple Games ---");
    let ethSeen = false;
    let pointsSeen = false;
    
    for (let i = 0; i < 5 && (!ethSeen || !pointsSeen); i++) {
      console.log(`\nGame ${i + 1}:`);
      
      try {
        // Ensure clean state
        const gameState = await climbContract.getPlayerGame(deployer.address);
        if (!gameState.isActive) {
          const startTx = await climbContract.startGame({ value: ethers.parseEther("1") });
          await startTx.wait();
        }

        const climbTx = await climbContract.climb({ value: fee });
        const climbReceipt = await climbTx.wait();
        
        const requestEvent = climbReceipt.logs.find(log => {
            try {
              const parsed = climbContract.interface.parseLog(log);
              return parsed.name === "RequestAttempted";
          } catch { return false; }
        });
        
        if (requestEvent) {
          const sequenceNumber = climbContract.interface.parseLog(requestEvent).args.data.sequenceNumber;
          const result = await waitForGameEvents(climbContract, sequenceNumber);
          
          if (result.climb && result.climb.success) {
            // Try cashout
            const cashoutTx = await climbContract.cashOut({ value: fee });
            const cashoutReceipt = await cashoutTx.wait();
            
            const cashoutEvent = cashoutReceipt.logs.find(log => {
              try {
                const parsed = climbContract.interface.parseLog(log);
                return parsed.name === "RequestAttempted";
              } catch { return false; }
            });
            
            if (cashoutEvent) {
              const cashoutSequence = climbContract.interface.parseLog(cashoutEvent).args.data.sequenceNumber;
              const cashoutResult = await waitForGameEvents(climbContract, cashoutSequence);
              
              if (cashoutResult.cashout) {
                if (cashoutResult.cashout.paidInPoints) {
                  pointsSeen = true;
                  console.log("🎯 Points payout achieved!");
                } else {
                  ethSeen = true;
                  console.log("🎯 ETH payout achieved!");
                }
              }
            }
          }
        }
        
        // Brief pause
        await new Promise(resolve => setTimeout(resolve, 1000));
        
      } catch (error) {
        console.log(`Game ${i + 1} error: ${error.message}`);
      }
    }

    console.log(`\n📊 Results: ETH payout ${ethSeen ? '✅' : '❌'} | Points payout ${pointsSeen ? '✅' : '❌'}`);

    // 5. Withdraw funds
    console.log("\n💸 Withdrawing funds...");
    const finalBalance = await climbContract.getContractBalance();
    if (finalBalance > 0n) {
      const withdrawTx = await climbContract.withdraw(finalBalance);
      await withdrawTx.wait();
      console.log(`✅ Withdrew ${ethers.formatEther(finalBalance)} ETH`);
    }

    // 6. Final summary
    console.log("\n✅ Deployment and testing completed!");
    console.log(`Points Contract: ${pointsAddress}`);
    console.log(`Climb Contract: ${climbAddress}`);
    
    // Check final points balance
        try {
          const pointsBalance = await pointsContract.points(deployer.address);
      console.log(`Final Points Balance: ${pointsBalance.toString()} points`);
    } catch (error) {
      console.log("Could not check points balance");
    }

  } catch (error) {
    console.error("❌ Error:", error.message);
  } finally {
    process.exit(0);
  }
}

main()
  .then(() => console.log("✅ Script completed"))
  .catch((error) => {
    console.error("❌ Script failed:", error);
    process.exit(1);
  });
