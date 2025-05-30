const { ethers } = require("hardhat");
const fs = require("fs");

// Configuration - Update these addresses before running
const OLD_POINTS_CONTRACT_ADDRESS = "0x92E2a4770005C162Ea70c9928432Caf0F5C85ab0"; // Replace with old contract address
const NEW_POINTS_CONTRACT_ADDRESS = "0x2a38f186Ae7A96F3973617BE1704ce0dAcE61857"; // Replace with new contract address

// Batch size for processing addresses (to avoid gas limit issues)
const BATCH_SIZE = 50;

// Helper function to get contract instance
async function getPointsContract(address) {
  const Points = await ethers.getContractFactory("Points");
  return Points.attach(address);
}

// Helper function to get all addresses with points
async function getAllAddresses(oldPointsContract) {
  console.log("Getting total address count from old contract...");
  const totalAddresses = await oldPointsContract.getAddressCount();
  console.log(`Total addresses with points: ${totalAddresses}`);

  if (totalAddresses == 0) {
    console.log("No addresses to migrate");
    return [];
  }

  console.log("Fetching all addresses...");
  const allAddresses = [];
  const pageSize = 1000; // Maximum allowed by contract

  for (let start = 0; start < totalAddresses; start += pageSize) {
    const size = Math.min(pageSize, Number(totalAddresses) - start);
    console.log(`Fetching addresses ${start} to ${start + size - 1}...`);
    
    const { addresses } = await oldPointsContract.getAddressesPaginated(start, size);
    allAddresses.push(...addresses);
  }

  console.log(`✓ Fetched ${allAddresses.length} addresses total`);
  return allAddresses;
}

// Helper function to get address data from old contract
async function getAddressData(oldPointsContract, addresses) {
  console.log("Getting points data for all addresses...");
  const addressData = [];

  for (let i = 0; i < addresses.length; i++) {
    const address = addresses[i];
    console.log(`Getting data for address ${i + 1}/${addresses.length}: ${address}`);
    
    try {
      const [totalPoints, withdrawablePoints] = await oldPointsContract.getPoints(address);
      const referralCode = await oldPointsContract.addressToReferralCode(address);
      const usedReferralCode = await oldPointsContract.usedReferralCode(address);
      
      addressData.push({
        address,
        totalPoints: totalPoints.toString(),
        withdrawablePoints: withdrawablePoints.toString(),
        referralCode,
        usedReferralCode
      });
    } catch (error) {
      console.error(`Error getting data for ${address}:`, error.message);
      // Continue with other addresses
    }
  }

  console.log(`✓ Got data for ${addressData.length} addresses`);
  return addressData;
}

// Helper function to migrate referral codes
async function migrateReferralCodes(newPointsContract, addressData, deployer) {
  console.log("\nMigrating referral codes...");
  
  // First, collect all unique referral codes and their owners
  const referralCodes = new Map();
  const usedReferralCodes = [];
  
  for (const data of addressData) {
    // Collect owned referral codes
    if (data.referralCode && data.referralCode.trim() !== "") {
      referralCodes.set(data.referralCode, data.address);
    }
    
    // Collect used referral codes
    if (data.usedReferralCode && data.usedReferralCode.trim() !== "") {
      usedReferralCodes.push({
        user: data.address,
        referralCode: data.usedReferralCode
      });
    }
  }

  console.log(`Found ${referralCodes.size} referral codes to migrate`);
  console.log(`Found ${usedReferralCodes.length} used referral codes to migrate`);

  // Migrate owned referral codes first
  for (const [code, owner] of referralCodes) {
    try {
      console.log(`Migrating referral code "${code}" for ${owner}...`);
      await newPointsContract.migrateReferralCode(owner, code);
      console.log(`✓ Successfully migrated referral code "${code}"`);
      
    } catch (error) {
      console.error(`Error migrating referral code "${code}":`, error.message);
    }
  }

  // Then migrate used referral codes
  for (const entry of usedReferralCodes) {
    try {
      console.log(`Migrating used referral code "${entry.referralCode}" for ${entry.user}...`);
      await newPointsContract.migrateUsedReferralCode(entry.user, entry.referralCode);
      console.log(`✓ Successfully migrated used referral code`);
      
    } catch (error) {
      console.error(`Error migrating used referral code "${entry.referralCode}" for ${entry.user}:`, error.message);
    }
  }
  
  console.log(`✓ Referral code migration completed`);
}

// Helper function to migrate points in batches
async function migratePointsBatch(newPointsContract, batch, batchNumber) {
  console.log(`\nMigrating batch ${batchNumber} (${batch.length} addresses)...`);
  
  for (let i = 0; i < batch.length; i++) {
    const data = batch[i];
    const { address, totalPoints, withdrawablePoints } = data;
    
    if (totalPoints === "0") {
      console.log(`Skipping ${address} (0 points)`);
      continue;
    }

    try {
      console.log(`Migrating ${address}: ${totalPoints} total, ${withdrawablePoints} withdrawable`);
      
      // Calculate non-withdrawable points
      const nonWithdrawablePoints = BigInt(totalPoints) - BigInt(withdrawablePoints);
      
      // Assign non-withdrawable points first if any
      if (nonWithdrawablePoints > 0) {
        await newPointsContract.assignPoints(address, nonWithdrawablePoints.toString(), false);
        console.log(`✓ Assigned ${nonWithdrawablePoints} non-withdrawable points`);
      }
      
      // Assign withdrawable (referral) points if any
      if (withdrawablePoints !== "0") {
        await newPointsContract.assignPoints(address, withdrawablePoints, true);
        console.log(`✓ Assigned ${withdrawablePoints} withdrawable points`);
      }
      
    } catch (error) {
      console.error(`Error migrating points for ${address}:`, error.message);
      
      // If it's a points cap error, stop migration
      if (error.message.includes("PointsCapReached")) {
        console.error("Points cap reached! Cannot continue migration.");
        throw error;
      }
    }
  }
  
  console.log(`✓ Batch ${batchNumber} completed`);
}

// Helper function to save migration data to file
async function saveMigrationData(addressData) {
  const fileName = `migration-data-${Date.now()}.json`;
  const filePath = `./migration-data/${fileName}`;
  
  // Create directory if it doesn't exist
  const dir = "./migration-data";
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir);
  }
  
  fs.writeFileSync(filePath, JSON.stringify(addressData, null, 2));
  console.log(`Migration data saved to: ${filePath}`);
  return filePath;
}

// Helper function to verify migration
async function verifyMigration(oldPointsContract, newPointsContract, addressData) {
  console.log("\nVerifying migration...");
  
  let successCount = 0;
  let errorCount = 0;
  const errors = [];
  
  for (const data of addressData) {
    try {
      const [newTotalPoints, newWithdrawablePoints] = await newPointsContract.getPoints(data.address);
      
      // Verify points
      const pointsMatch = newTotalPoints.toString() === data.totalPoints && 
                         newWithdrawablePoints.toString() === data.withdrawablePoints;
      
      // Verify referral codes
      const newReferralCode = await newPointsContract.addressToReferralCode(data.address);
      const referralCodeMatch = newReferralCode === data.referralCode;
      
      // Verify used referral codes
      const newUsedReferralCode = await newPointsContract.usedReferralCode(data.address);
      const usedReferralCodeMatch = newUsedReferralCode === data.usedReferralCode;
      
      if (pointsMatch && referralCodeMatch && usedReferralCodeMatch) {
        successCount++;
      } else {
        errorCount++;
        const errorDetails = {
          address: data.address,
          expected: { 
            total: data.totalPoints, 
            withdrawable: data.withdrawablePoints,
            referralCode: data.referralCode,
            usedReferralCode: data.usedReferralCode
          },
          actual: { 
            total: newTotalPoints.toString(), 
            withdrawable: newWithdrawablePoints.toString(),
            referralCode: newReferralCode,
            usedReferralCode: newUsedReferralCode
          }
        };
        
        // Add specific mismatch details
        if (!pointsMatch) errorDetails.issue = "Points mismatch";
        else if (!referralCodeMatch) errorDetails.issue = "Referral code mismatch";
        else if (!usedReferralCodeMatch) errorDetails.issue = "Used referral code mismatch";
        
        errors.push(errorDetails);
      }
    } catch (error) {
      errorCount++;
      errors.push({
        address: data.address,
        error: error.message
      });
    }
  }
  
  console.log(`\nVerification Results:`);
  console.log(`✓ Successfully migrated: ${successCount}`);
  console.log(`✗ Errors: ${errorCount}`);
  
  if (errors.length > 0) {
    console.log("\nErrors:");
    errors.forEach(error => {
      if (error.issue) {
        console.log(`- ${error.address}: ${error.issue}`);
        console.log(`  Expected: ${JSON.stringify(error.expected)}`);
        console.log(`  Actual: ${JSON.stringify(error.actual)}`);
      } else {
        console.log(`- ${error.address}: ${error.error}`);
      }
    });
  }
  
  return { successCount, errorCount, errors };
}

async function main() {
  console.log("Points Migration Script");
  console.log("======================");
  
  // Validate configuration
  if (OLD_POINTS_CONTRACT_ADDRESS === "0x..." || NEW_POINTS_CONTRACT_ADDRESS === "0x...") {
    console.error("❌ Please update the contract addresses in the script configuration");
    process.exit(1);
  }
  
  const [deployer] = await ethers.getSigners();
  console.log("Running migration with account:", deployer.address);
  console.log("Old Points Contract:", OLD_POINTS_CONTRACT_ADDRESS);
  console.log("New Points Contract:", NEW_POINTS_CONTRACT_ADDRESS);
  
  try {
    // Get contract instances
    console.log("\nConnecting to contracts...");
    const oldPointsContract = await getPointsContract(OLD_POINTS_CONTRACT_ADDRESS);
    const newPointsContract = await getPointsContract(NEW_POINTS_CONTRACT_ADDRESS);
    console.log("✓ Connected to both contracts");
    
    // Verify deployer is owner of new contract
    const owner = await newPointsContract.owner();
    if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
      console.error(`❌ Deployer (${deployer.address}) is not owner of new contract (${owner})`);
      process.exit(1);
    }
    console.log("✓ Deployer is owner of new contract");
    
    // Get old contract stats
    const oldTotalPoints = await oldPointsContract.totalPointsIssued();
    const oldRemainingPoints = await oldPointsContract.getRemainingPoints();
    console.log(`\nOld contract stats:`);
    console.log(`- Total points issued: ${oldTotalPoints}`);
    console.log(`- Remaining points: ${oldRemainingPoints}`);
    
    // Get new contract stats
    const newTotalPoints = await newPointsContract.totalPointsIssued();
    const newRemainingPoints = await newPointsContract.getRemainingPoints();
    console.log(`\nNew contract stats:`);
    console.log(`- Total points issued: ${newTotalPoints}`);
    console.log(`- Remaining points: ${newRemainingPoints}`);
    
    // Check if new contract has enough capacity
    if (newRemainingPoints < oldTotalPoints - newTotalPoints) {
      console.error(`❌ New contract doesn't have enough capacity for migration`);
      console.error(`Need: ${oldTotalPoints - newTotalPoints}, Available: ${newRemainingPoints}`);
      process.exit(1);
    }
    
    // Get all addresses from old contract
    const addresses = await getAllAddresses(oldPointsContract);
    
    if (addresses.length === 0) {
      console.log("No addresses to migrate. Exiting.");
      return;
    }
    
    // Get data for all addresses
    const addressData = await getAddressData(oldPointsContract, addresses);
    
    // Save migration data for backup
    const backupFile = await saveMigrationData(addressData);
    
    // Migrate in batches
    console.log(`\nStarting migration in batches of ${BATCH_SIZE}...`);
    const batches = [];
    for (let i = 0; i < addressData.length; i += BATCH_SIZE) {
      batches.push(addressData.slice(i, i + BATCH_SIZE));
    }
    
    console.log(`Created ${batches.length} batches`);
    
    for (let i = 0; i < batches.length; i++) {
      await migratePointsBatch(newPointsContract, batches[i], i + 1);
      
      // Small delay between batches to avoid overwhelming the network
      if (i < batches.length - 1) {
        console.log("Waiting 2 seconds before next batch...");
        await new Promise(resolve => setTimeout(resolve, 2000));
      }
    }
    
    // Migrate referral codes
    await migrateReferralCodes(newPointsContract, addressData, deployer);
    
    // Verify migration
    const verification = await verifyMigration(oldPointsContract, newPointsContract, addressData);
    
    // Final stats
    const finalTotalPoints = await newPointsContract.totalPointsIssued();
    const finalRemainingPoints = await newPointsContract.getRemainingPoints();
    
    console.log(`\n🎉 Migration Complete!`);
    console.log(`====================`);
    console.log(`- Addresses processed: ${addressData.length}`);
    console.log(`- Successfully migrated: ${verification.successCount}`);
    console.log(`- Errors: ${verification.errorCount}`);
    console.log(`- Final total points: ${finalTotalPoints}`);
    console.log(`- Remaining capacity: ${finalRemainingPoints}`);
    console.log(`- Backup saved to: ${backupFile}`);
    
    if (verification.errorCount > 0) {
      console.log(`\n⚠️  Please review the ${verification.errorCount} errors above`);
    }
    
  } catch (error) {
    console.error("\n❌ Migration failed:", error.message);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('\n\nMigration interrupted by user');
  process.exit(1);
});

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Unhandled error:", error);
    process.exit(1);
  }); 