# Points Contract Migration Script

This script migrates all points data from an old Points contract to a new Points contract.

## Features

- ✅ Migrates all user points (total and withdrawable/referral points)
- ✅ **Migrates referral codes and used referral codes**
- ✅ Preserves point balances with proper categorization
- ✅ Batch processing to avoid gas limit issues
- ✅ Comprehensive verification of migration results
- ✅ Backup creation for safety
- ✅ Detailed logging and error handling
- ✅ Graceful handling of interruptions

## Prerequisites

1. **Hardhat Environment**: The script requires a Hardhat project setup
2. **Contract Ownership**: You must be the owner of the NEW Points contract
3. **Contract Deployment**: Both old and new Points contracts must be deployed
4. **Sufficient ETH**: Deployer account needs enough ETH for gas fees

## Configuration

Before running the script, update these variables in `scripts/migrate-points.js`:

```javascript
const OLD_POINTS_CONTRACT_ADDRESS = "0x1234..."; // Replace with old contract address
const NEW_POINTS_CONTRACT_ADDRESS = "0x5678..."; // Replace with new contract address
```

Optional configuration:
```javascript
const BATCH_SIZE = 50; // Number of addresses to process per batch
```

## Usage

1. **Configure addresses** in the script (see Configuration section above)

2. **Run the migration**:
   ```bash
   npx hardhat run scripts/migrate-points.js --network <your-network>
   ```

3. **Monitor progress**: The script provides detailed logging of each step

4. **Review results**: Check the final verification report and any errors

## What the Script Does

### 1. Validation
- Verifies contract addresses are set
- Confirms deployer is owner of new contract
- Checks new contract has sufficient capacity

### 2. Data Collection
- Fetches all addresses with points from old contract
- Retrieves point balances (total and withdrawable) for each address
- Collects referral code information (owned and used codes)
- Creates backup file with all data

### 3. Migration
- Processes addresses in configurable batches
- Uses `assignPoints()` function to recreate balances
- Separates withdrawable (referral) and non-withdrawable points
- **Migrates owned referral codes using `migrateReferralCode()`**
- **Migrates used referral codes using `migrateUsedReferralCode()`**
- Handles errors gracefully and continues with remaining addresses

### 4. Verification
- Compares old and new contract balances for each address
- **Verifies referral codes and used referral codes match**
- Reports success/failure statistics
- Lists any discrepancies for manual review

## Output Files

The script creates a backup file in `./migration-data/` with format:
```
migration-data-{timestamp}.json
```

This file contains all the original data in case you need to re-run or troubleshoot.

## Important Notes

### Referral Codes
- **✅ Fully Automated**: The contract now includes migration functions that allow the owner to register referral codes on behalf of users
- **Complete Migration**: Both owned referral codes and used referral codes are migrated automatically
- **No User Action Required**: Users don't need to re-register their referral codes after migration

### Points Capacity
- The new contract must have sufficient remaining capacity for all migrated points
- Script checks this before starting migration
- Migration stops if points cap would be exceeded

### Gas Considerations
- Processing is done in batches to avoid gas limit issues
- Default batch size is 50 addresses (configurable)
- Small delay between batches to avoid overwhelming the network

### Error Handling
- Individual address failures don't stop the entire migration
- Comprehensive error logging for troubleshooting
- Verification step identifies any missed migrations

## Troubleshooting

### "Not owner of new contract"
- Ensure the account running the script is the owner of the NEW Points contract
- Check that you're connected to the correct network

### "Insufficient capacity"
- The new contract doesn't have enough remaining points capacity
- Check `getRemainingPoints()` on the new contract

### "Points cap reached during migration"
- Migration stopped to prevent exceeding the points cap
- Review which addresses were migrated successfully
- Consider deploying a new contract with higher capacity

### Verification Errors
- Check the detailed error list in the console output
- Common causes: network issues, contract state changes during migration
- Re-run verification manually if needed

## Manual Verification

You can manually verify specific addresses:

```javascript
// Get points from old contract
const [oldTotal, oldWithdrawable] = await oldContract.getPoints("0x...");

// Get points from new contract  
const [newTotal, newWithdrawable] = await newContract.getPoints("0x...");

// Compare values
console.log(`Old: ${oldTotal}/${oldWithdrawable}, New: ${newTotal}/${newWithdrawable}`);
```

## Post-Migration Steps

1. **Update frontend/dApp** to use the new contract address
2. **Test functionality** with the new contract (including referral system)
3. **Consider pausing/disabling** the old contract to prevent confusion

## Safety Recommendations

- **Test first** on a testnet with the same contract setup
- **Run during low activity** periods to minimize interference
- **Have a rollback plan** in case of issues
- **Monitor gas prices** and adjust batch size accordingly
- **Keep backup files** until migration is fully verified 