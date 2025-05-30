const { ethers } = require("hardhat");

// Contract address for the GameMaster - replace with your deployed address
const GAME_MASTER_ADDRESS = "0x951F246C01bbD289A5894D9c5Fd645549c51df01";

// ETH distribution amounts
const DISTRIBUTION = {
    FIRST_PLACE: 275,
    TOP_SIX: 50,
    TOP_NINE: 25,
    OTHERS: 0
};

function getEthForPlacement(placement) {
    if (placement === 1) return DISTRIBUTION.FIRST_PLACE;
    if (placement >= 2 && placement <= 6) return DISTRIBUTION.TOP_SIX;
    if (placement >= 7 && placement <= 9) return DISTRIBUTION.TOP_NINE;
    return DISTRIBUTION.OTHERS;
}

async function sendEth(signer, toAddress, ethAmount) {
    try {
        if (ethAmount === 0) return null;
        
        const tx = await signer.sendTransaction({
            to: toAddress,
            value: ethers.parseEther(ethAmount.toString())
        });
        
        console.log(`   Transaction hash: ${tx.hash}`);
        await tx.wait();
        return tx;
    } catch (error) {
        console.error(`   Failed to send ${ethAmount} ETH to ${toAddress}:`, error.message);
        return null;
    }
}

async function getWinners() {
    const [signer] = await ethers.getSigners();
    console.log("Operating with account:", signer.address);

    // Check signer balance
    const balanceWei = await signer.provider.getBalance(signer.address);
    const balanceEth = Number(ethers.formatEther(balanceWei));
    console.log(`Signer balance: ${balanceEth} ETH`);

    // Connect to GameMaster contract
    const GameMaster = await ethers.getContractFactory("GameMaster");
    const gameMaster = GameMaster.attach(GAME_MASTER_ADDRESS);

    try {
        // Get all registered players
        const registeredPlayers = await gameMaster.getRegisteredPlayers();
        console.log(`\nTotal registered players: ${registeredPlayers.length}`);

        // Get eliminated players in order of elimination
        const eliminatedPlayers = await gameMaster.getEliminatedPlayers();
        console.log(`\nTotal eliminated players: ${eliminatedPlayers.length}`);

        // Get remaining active players
        const activePlayers = await gameMaster.getActivePlayers();
        console.log(`\nRemaining active players: ${activePlayers.length}`);

        // Create a sorted list of players and their placements
        const playerPlacements = [];

        // Get placement for each eliminated player
        for (const player of eliminatedPlayers) {
            const placement = await gameMaster.getPlayerFinalPlacement(player);
            playerPlacements.push({
                address: player,
                placement: Number(placement),
                status: "Eliminated"
            });
        }

        // Add active players with placement 1
        for (const player of activePlayers) {
            playerPlacements.push({
                address: player,
                placement: 1,
                status: "Active"
            });
        }

        // Sort by placement
        playerPlacements.sort((a, b) => a.placement - b.placement);

        // Calculate total ETH needed
        let totalEthNeeded = 0;
        playerPlacements.forEach(player => {
            if (player.placement !== 1) { // Exclude first place from total
                totalEthNeeded += getEthForPlacement(player.placement);
            }
        });

        // Check if we have enough ETH
        if (balanceEth < totalEthNeeded) {
            throw new Error(`Insufficient funds. Need ${totalEthNeeded} ETH but only have ${balanceEth} ETH`);
        }

        // Print and execute distribution
        console.log("\nETH Distribution:");
        console.log("=========================");
        
        let successfulTransfers = 0;
        let totalEthSent = 0;

        for (const player of playerPlacements) {
            const ethAmount = getEthForPlacement(player.placement);
            
            console.log(`\nAddress: ${player.address}`);
            console.log(`Status: ${player.status}`);
            console.log(`Placement: ${player.placement}${player.status === "Active" ? " (Active)" : ""}`);
            console.log(`ETH amount: ${ethAmount} ETH`);

            if (player.placement === 1) {
                console.log("SKIPPING TRANSFER - First place winner");
                continue;
            }

            if (ethAmount > 0) {
                console.log("Sending ETH...");
                const tx = await sendEth(signer, player.address, ethAmount);
                if (tx) {
                    successfulTransfers++;
                    totalEthSent += ethAmount;
                    console.log("Transfer successful!");
                } else {
                    console.log("Transfer failed!");
                }
            } else {
                console.log("No ETH to send for this placement");
            }
            console.log("------------------");
        }

        console.log("\nDistribution Summary:");
        console.log("====================");
        console.log(`Total successful transfers: ${successfulTransfers}`);
        console.log(`Total ETH sent: ${totalEthSent} ETH`);
        console.log(`First place (not sent): ${DISTRIBUTION.FIRST_PLACE} ETH`);

    } catch (error) {
        console.error("\nError during distribution:", error.message);
        throw error;
    }
}

getWinners()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
