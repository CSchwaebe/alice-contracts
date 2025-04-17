const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Threes", function () {
    let Threes;
    let RagnarokGameMaster;
    let threes;
    let ragnarokGameMaster;
    let owner;
    let player1;
    let player2;
    let player3;
    let player4;
    let player5;
    let player6;

    const COMMIT_DURATION = 5 * 60; // 5 minutes
    const REVEAL_DURATION = 20 * 60; // 20 minutes

    // Helper function to create commitment
    async function createCommitment(choice, player) {
        const salt = ethers.randomBytes(32);
        const commitment = ethers.solidityPackedKeccak256(
            ["uint256", "bytes32", "address"],
            [choice, salt, player.address]
        );
        return { commitment, salt };
    }

    beforeEach(async function () {
        [owner, player1, player2, player3, player4, player5, player6] = await ethers.getSigners();

        // Deploy RagnarokGameMaster
        RagnarokGameMaster = await ethers.getContractFactory("RagnarokGameMaster");
        ragnarokGameMaster = await RagnarokGameMaster.deploy();

        // Deploy Threes
        Threes = await ethers.getContractFactory("Threes");
        threes = await Threes.deploy();

        // Setup contract relationships
        await ragnarokGameMaster.registerGame("Threes", await threes.getAddress());
        await threes.setGameMaster(await ragnarokGameMaster.getAddress());

        // Register players
        const registrationFee = await ragnarokGameMaster.registrationFee();
        await ragnarokGameMaster.connect(player1).register({ value: registrationFee });
        await ragnarokGameMaster.connect(player2).register({ value: registrationFee });
        await ragnarokGameMaster.connect(player3).register({ value: registrationFee });
    });

    describe("Game Setup", function () {
        it("Should initialize game with exactly 3 players", async function () {
            await ragnarokGameMaster.initializeGame("Threes");
            
            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.length).to.equal(3);
            expect(gameInfo[0].isActive).to.be.true;
            expect(gameInfo[1].isActive).to.be.true;
            expect(gameInfo[2].isActive).to.be.true;
        });

        it("Should fail to initialize with non-multiple of 3 players", async function () {
            // Register a 4th player
            const registrationFee = await ragnarokGameMaster.registrationFee();
            await ragnarokGameMaster.connect(player4).register({ value: registrationFee });
            
            await expect(ragnarokGameMaster.initializeGame("Threes"))
                .to.be.revertedWith("Player count must be divisible by 3");
        });
    });

    describe("Commit Phase", function () {
        beforeEach(async function () {
            await ragnarokGameMaster.initializeGame("Threes");
            await ragnarokGameMaster.startGames("Threes");
        });

        it("Should allow players to commit choices", async function () {
            const { commitment } = await createCommitment(1, player1);
            await threes.connect(player1).commitChoice(commitment);
            expect(await threes.hasPlayerCommitted(1, player1.address)).to.be.true;
        });

        it("Should move to reveal phase when all players commit", async function () {
            // All players commit
            for (const player of [player1, player2, player3]) {
                const { commitment } = await createCommitment(1, player);
                await threes.connect(player).commitChoice(commitment);
            }

            // Check we're in reveal phase
            expect(await threes.getCurrentRound(1)).to.equal(2); // REVEAL_ROUND
        });

        it("Should eliminate non-committing players when time expires", async function () {
            // Only player1 commits
            const { commitment } = await createCommitment(1, player1);
            await threes.connect(player1).commitChoice(commitment);

            // Move time forward past commit duration
            await time.increase(COMMIT_DURATION + 1);

            // End expired games
            await ragnarokGameMaster.endExpiredGames("Threes");

            // Check player1 is still active, others eliminated
            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.find(p => p.playerAddress === player1.address).isActive).to.be.true;
            expect(gameInfo.find(p => p.playerAddress === player2.address).isActive).to.be.false;
            expect(gameInfo.find(p => p.playerAddress === player3.address).isActive).to.be.false;
        });
    });

    describe("Reveal Phase", function () {
        beforeEach(async function () {
            await ragnarokGameMaster.initializeGame("Threes");
            await ragnarokGameMaster.startGames("Threes");
        });

        it("Should allow players to reveal choices", async function () {
            // All players commit same number
            const commit1 = await createCommitment(1, player1);
            const commit2 = await createCommitment(1, player2);
            const commit3 = await createCommitment(1, player3);

            await threes.connect(player1).commitChoice(commit1.commitment);
            await threes.connect(player2).commitChoice(commit2.commitment);
            await threes.connect(player3).commitChoice(commit3.commitment);

            await threes.connect(player1).revealChoice(1, commit1.salt);
            expect(await threes.hasPlayerRevealed(1, player1.address)).to.be.true;
        });

        it("Should eliminate non-revealing players when time expires", async function () {
            // All players commit same number
            const commit1 = await createCommitment(1, player1);
            const commit2 = await createCommitment(1, player2);
            const commit3 = await createCommitment(1, player3);

            await threes.connect(player1).commitChoice(commit1.commitment);
            await threes.connect(player2).commitChoice(commit2.commitment);
            await threes.connect(player3).commitChoice(commit3.commitment);

            // Only player1 reveals
            await threes.connect(player1).revealChoice(1, commit1.salt);

            // Move time forward past reveal duration
            await time.increase(REVEAL_DURATION + 1);

            // End expired games
            await ragnarokGameMaster.endExpiredGames("Threes");

            // Check player1 is still active, others eliminated
            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.find(p => p.playerAddress === player1.address).isActive).to.be.true;
            expect(gameInfo.find(p => p.playerAddress === player2.address).isActive).to.be.false;
            expect(gameInfo.find(p => p.playerAddress === player3.address).isActive).to.be.false;
        });

        it("Should handle all players revealing same number", async function () {
            // All players commit same number
            const commit1 = await createCommitment(1, player1);
            const commit2 = await createCommitment(1, player2);
            const commit3 = await createCommitment(1, player3);

            await threes.connect(player1).commitChoice(commit1.commitment);
            await threes.connect(player2).commitChoice(commit2.commitment);
            await threes.connect(player3).commitChoice(commit3.commitment);

            // All players reveal
            await threes.connect(player1).revealChoice(1, commit1.salt);
            await threes.connect(player2).revealChoice(1, commit2.salt);
            await threes.connect(player3).revealChoice(1, commit3.salt);

            // All players should still be active
            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.every(p => p.isActive)).to.be.true;
        });

        it("Should eliminate players who reveal same number when two match", async function () {
            // Players commit with two matching and one different
            const commit1 = await createCommitment(1, player1);
            const commit2 = await createCommitment(1, player2);
            const commit3 = await createCommitment(2, player3);

            await threes.connect(player1).commitChoice(commit1.commitment);
            await threes.connect(player2).commitChoice(commit2.commitment);
            await threes.connect(player3).commitChoice(commit3.commitment);

            // Players reveal
            await threes.connect(player1).revealChoice(1, commit1.salt);
            await threes.connect(player2).revealChoice(1, commit2.salt);
            await threes.connect(player3).revealChoice(2, commit3.salt);

            // Check player3 is still active, others eliminated
            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.find(p => p.playerAddress === player1.address).isActive).to.be.false;
            expect(gameInfo.find(p => p.playerAddress === player2.address).isActive).to.be.false;
            expect(gameInfo.find(p => p.playerAddress === player3.address).isActive).to.be.true;
        });

        it("Should eliminate all players when all reveal different numbers", async function () {
            // Players commit different numbers
            const commit1 = await createCommitment(1, player1);
            const commit2 = await createCommitment(2, player2);
            const commit3 = await createCommitment(3, player3);

            await threes.connect(player1).commitChoice(commit1.commitment);
            await threes.connect(player2).commitChoice(commit2.commitment);
            await threes.connect(player3).commitChoice(commit3.commitment);

            // Players reveal
            await threes.connect(player1).revealChoice(1, commit1.salt);
            await threes.connect(player2).revealChoice(2, commit2.salt);
            await threes.connect(player3).revealChoice(3, commit3.salt);

            // All players should be eliminated
            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.every(p => !p.isActive)).to.be.true;
        });
    });

    describe("Edge Cases", function () {
        beforeEach(async function () {
            await ragnarokGameMaster.initializeGame("Threes");
            await ragnarokGameMaster.startGames("Threes");
        });

        it("Should handle no players committing", async function () {
            // Move time forward past commit duration
            await time.increase(COMMIT_DURATION + 1);

            // End expired games
            await ragnarokGameMaster.endExpiredGames("Threes");

            // All players should be eliminated
            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.every(p => !p.isActive)).to.be.true;
        });

        it("Should handle only one player committing", async function () {
            const { commitment } = await createCommitment(1, player1);
            await threes.connect(player1).commitChoice(commitment);

            // Move time forward past commit duration
            await time.increase(COMMIT_DURATION + 1);

            // End expired games
            await ragnarokGameMaster.endExpiredGames("Threes");

            // Only player1 should be active
            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.find(p => p.playerAddress === player1.address).isActive).to.be.true;
            expect(gameInfo.filter(p => p.isActive).length).to.equal(1);
        });
    });

    describe("Multiple Games", function () {
        beforeEach(async function () {
            // Register players 4-6
            const registrationFee = await ragnarokGameMaster.registrationFee();
            await ragnarokGameMaster.connect(player4).register({ value: registrationFee });
            await ragnarokGameMaster.connect(player5).register({ value: registrationFee });
            await ragnarokGameMaster.connect(player6).register({ value: registrationFee });
        });

        it("Should handle multiple games simultaneously", async function () {
            // Initialize all games at once (should create two games with players 1-3 and 4-6)
            await ragnarokGameMaster.initializeGame("Threes");
            await ragnarokGameMaster.startGames("Threes");

            // Game 1: only player1 commits
            const { commitment: commit1 } = await createCommitment(1, player1);
            await threes.connect(player1).commitChoice(commit1);

            // Game 2: store commitments for later reveal
            const game2Commitments = [];
            for (const player of [player4, player5, player6]) {
                const commitment = await createCommitment(1, player);
                game2Commitments.push({ player, ...commitment });
                await threes.connect(player).commitChoice(commitment.commitment);
            }

            // Small delay to allow state transition
            await ethers.provider.send("evm_mine", []);

            // Move time forward past commit duration
            await time.increase(COMMIT_DURATION + 1);
            await ragnarokGameMaster.endExpiredGames("Threes");

            // Mine a block to ensure state updates
            await ethers.provider.send("evm_mine", []);

            // Check game 1: only player1 should be active (others eliminated for not committing)
            const game1Info = await threes.getPlayerInfo(1);
            expect(game1Info.find(p => p.playerAddress === player1.address).isActive).to.be.true;
            expect(game1Info.find(p => p.playerAddress === player2.address).isActive).to.be.false;
            expect(game1Info.find(p => p.playerAddress === player3.address).isActive).to.be.false;
            expect(game1Info.filter(p => p.isActive).length).to.equal(1);

            // Check game 2: all players should be in reveal phase
            const game2Info = await threes.getPlayerInfo(2);
            expect(game2Info.every(p => p.isActive)).to.be.true;
            expect(await threes.getCurrentRound(2)).to.equal(2); // REVEAL_ROUND

            // Game 2: all players reveal using stored commitments
            for (const { player, salt } of game2Commitments) {
                await threes.connect(player).revealChoice(1, salt);
            }

            // All players in game 2 should still be active (all revealed same number)
            const game2InfoAfterReveal = await threes.getPlayerInfo(2);
            expect(game2InfoAfterReveal.every(p => p.isActive)).to.be.true;
        });
    });

    describe("endExpiredGames", function () {
        beforeEach(async function () {
            // Register players 4-6 for multi-game tests
            const registrationFee = await ragnarokGameMaster.registrationFee();
            await ragnarokGameMaster.connect(player4).register({ value: registrationFee });
            await ragnarokGameMaster.connect(player5).register({ value: registrationFee });
            await ragnarokGameMaster.connect(player6).register({ value: registrationFee });
        });

        it("Should handle expired commit phase with no commits", async function () {
            await ragnarokGameMaster.initializeGame("Threes");
            await ragnarokGameMaster.startGames("Threes");

            await time.increase(COMMIT_DURATION + 1);
            await ragnarokGameMaster.endExpiredGames("Threes");

            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.every(p => !p.isActive)).to.be.true;
            expect(await threes.getGameState(1)).to.equal(4); // Completed
        });

        it("Should handle expired commit phase with partial commits", async function () {
            await ragnarokGameMaster.initializeGame("Threes");
            await ragnarokGameMaster.startGames("Threes");

            // Only player1 commits
            const { commitment } = await createCommitment(1, player1);
            await threes.connect(player1).commitChoice(commitment);

            await time.increase(COMMIT_DURATION + 1);
            await ragnarokGameMaster.endExpiredGames("Threes");

            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.find(p => p.playerAddress === player1.address).isActive).to.be.true;
            expect(gameInfo.filter(p => p.isActive).length).to.equal(1);
            expect(await threes.getGameState(1)).to.equal(4); // Completed
        });

        it("Should handle expired reveal phase with no reveals", async function () {
            await ragnarokGameMaster.initializeGame("Threes");
            await ragnarokGameMaster.startGames("Threes");

            // All players commit
            for (const player of [player1, player2, player3]) {
                const { commitment } = await createCommitment(1, player);
                await threes.connect(player).commitChoice(commitment);
            }

            // Move to reveal phase and let it expire
            await time.increase(REVEAL_DURATION + 1);
            await ragnarokGameMaster.endExpiredGames("Threes");

            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.every(p => !p.isActive)).to.be.true;
            expect(await threes.getGameState(1)).to.equal(4); // Completed
        });

        it("Should handle expired reveal phase with partial reveals", async function () {
            await ragnarokGameMaster.initializeGame("Threes");
            await ragnarokGameMaster.startGames("Threes");

            // All players commit
            const commits = [];
            for (const player of [player1, player2, player3]) {
                const commit = await createCommitment(1, player);
                commits.push({ player, ...commit });
                await threes.connect(player).commitChoice(commit.commitment);
            }

            // Only player1 reveals
            await threes.connect(player1).revealChoice(1, commits[0].salt);

            await time.increase(REVEAL_DURATION + 1);
            await ragnarokGameMaster.endExpiredGames("Threes");

            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.find(p => p.playerAddress === player1.address).isActive).to.be.true;
            expect(gameInfo.filter(p => p.isActive).length).to.equal(1);
            expect(await threes.getGameState(1)).to.equal(4); // Completed
        });

        it("Should handle multiple games in different phases", async function () {
            // Initialize both games
            await ragnarokGameMaster.initializeGame("Threes");
            await ragnarokGameMaster.startGames("Threes");

            // Game 1: Only player1 commits
            const { commitment: commit1 } = await createCommitment(1, player1);
            await threes.connect(player1).commitChoice(commit1);

            // Game 2: All players commit
            const game2Commits = [];
            for (const player of [player4, player5, player6]) {
                const commit = await createCommitment(1, player);
                game2Commits.push({ player, ...commit });
                await threes.connect(player).commitChoice(commit.commitment);
            }

            // Let commit phase expire
            await time.increase(COMMIT_DURATION + 1);
            await ragnarokGameMaster.endExpiredGames("Threes");

            // Check game 1 (expired in commit phase)
            const game1Info = await threes.getPlayerInfo(1);
            expect(game1Info.find(p => p.playerAddress === player1.address).isActive).to.be.true;
            expect(game1Info.filter(p => p.isActive).length).to.equal(1);
            expect(await threes.getGameState(1)).to.equal(4); // Completed

            // Check game 2 (should be in reveal phase)
            const game2Info = await threes.getPlayerInfo(2);
            expect(game2Info.every(p => p.isActive)).to.be.true;
            expect(await threes.getCurrentRound(2)).to.equal(2); // REVEAL_ROUND

            // Only player4 reveals in game 2
            await threes.connect(player4).revealChoice(1, game2Commits[0].salt);

            // Let reveal phase expire
            await time.increase(REVEAL_DURATION + 1);
            await ragnarokGameMaster.endExpiredGames("Threes");

            // Check game 2 after reveal phase expires
            const game2InfoAfter = await threes.getPlayerInfo(2);
            expect(game2InfoAfter.find(p => p.playerAddress === player4.address).isActive).to.be.true;
            expect(game2InfoAfter.filter(p => p.isActive).length).to.equal(1);
            expect(await threes.getGameState(2)).to.equal(4); // Completed
        });

        it("Should not affect active games that haven't expired", async function () {
            await ragnarokGameMaster.initializeGame("Threes");
            await ragnarokGameMaster.startGames("Threes");

            // All players commit in game 1
            for (const player of [player1, player2, player3]) {
                const { commitment } = await createCommitment(1, player);
                await threes.connect(player).commitChoice(commitment);
            }

            // Call endExpiredGames before any expiration
            await ragnarokGameMaster.endExpiredGames("Threes");

            // Game should still be active and in reveal phase
            expect(await threes.getGameState(1)).to.equal(2); // Active
            expect(await threes.getCurrentRound(1)).to.equal(2); // REVEAL_ROUND

            const gameInfo = await threes.getPlayerInfo(1);
            expect(gameInfo.every(p => p.isActive)).to.be.true;
        });

        it("Should not affect completed games", async function () {
            await ragnarokGameMaster.initializeGame("Threes");
            await ragnarokGameMaster.startGames("Threes");

            // Complete game 1 normally
            const commits = [];
            for (const player of [player1, player2, player3]) {
                const commit = await createCommitment(1, player);
                commits.push({ player, ...commit });
                await threes.connect(player).commitChoice(commit.commitment);
            }

            // All reveal the same number
            for (const { player, salt } of commits) {
                await threes.connect(player).revealChoice(1, salt);
            }

            // Game should be completed with all players active
            const gameInfoBefore = await threes.getPlayerInfo(1);
            expect(gameInfoBefore.every(p => p.isActive)).to.be.true;
            expect(await threes.getGameState(1)).to.equal(4); // Completed

            // Call endExpiredGames
            await time.increase(REVEAL_DURATION + 1);
            await ragnarokGameMaster.endExpiredGames("Threes");

            // Game state should remain unchanged
            const gameInfoAfter = await threes.getPlayerInfo(1);
            expect(gameInfoAfter.every(p => p.isActive)).to.be.true;
            expect(await threes.getGameState(1)).to.equal(4); // Completed
        });
    });
}); 