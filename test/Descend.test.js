const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Descend", function () {
    let Descend;
    let RagnarokGameMaster;
    let descend;
    let ragnarokGameMaster;
    let owner;
    let player1;
    let player2;
    let player3;
    let player4;
    let player5;
    let player6;

    const COMMIT_DURATION = 200 * 60; // 200 minutes
    const REVEAL_DURATION = 200 * 60; // 200 minutes
    const MAX_LEVEL = 21;
    const MAX_MOVE = 5;

    // Helper function to create commitment
    async function createCommitment(move, player) {
        const salt = ethers.randomBytes(32);
        const commitment = ethers.solidityPackedKeccak256(
            ["uint256", "bytes32", "address"],
            [move, salt, player.address]
        );
        return { commitment, salt };
    }

    beforeEach(async function () {
        [owner, player1, player2, player3, player4, player5, player6] = await ethers.getSigners();

        // Deploy RagnarokGameMaster
        RagnarokGameMaster = await ethers.getContractFactory("RagnarokGameMaster");
        ragnarokGameMaster = await RagnarokGameMaster.deploy();

        // Deploy Descend
        Descend = await ethers.getContractFactory("Descend");
        descend = await Descend.deploy();

        // Setup contract relationships
        await ragnarokGameMaster.registerGame("Descend", await descend.getAddress());
        await descend.setGameMaster(await ragnarokGameMaster.getAddress());

        // Register players
        const registrationFee = await ragnarokGameMaster.registrationFee();
        await ragnarokGameMaster.connect(player1).register({ value: registrationFee });
        await ragnarokGameMaster.connect(player2).register({ value: registrationFee });
        await ragnarokGameMaster.connect(player3).register({ value: registrationFee });
    });

    describe("Game Setup", function () {
        it("Should initialize game with correct player distribution", async function () {
            await ragnarokGameMaster.initializeGame("Descend");
            
            const gameInfo = await descend.getPlayerInfo(1);
            expect(gameInfo.length).to.be.above(0);
            expect(gameInfo[0].isActive).to.be.true;
            expect(gameInfo[0].level).to.equal(0); // All players start at level 0
        });

        it("Should set correct level capacities based on player count", async function () {
            await ragnarokGameMaster.initializeGame("Descend");
            
            const gameId = 1;
            const playerCount = (await descend.getPlayerInfo(gameId)).length;
            const levelPopulation = await descend.getLevelPopulation(gameId, 0);
            
            expect(levelPopulation).to.equal(playerCount); // All players should start at level 0
        });

        it("Should fail to initialize with invalid player addresses", async function () {
            const invalidPlayers = [ethers.ZeroAddress];
            const playerNumbers = [1];
            
            await expect(descend.initialize(invalidPlayers, playerNumbers))
                .to.be.revertedWith("Invalid player address");
        });
    });

    describe("Commit Phase", function () {
        beforeEach(async function () {
            await ragnarokGameMaster.initializeGame("Descend");
            await ragnarokGameMaster.startGames("Descend");
        });

        it("Should allow players to commit moves", async function () {
            const { commitment } = await createCommitment(1, player1);
            await descend.connect(player1).commitMove(commitment);
            expect(await descend.hasPlayerCommitted(1, player1.address)).to.be.true;
        });

        it("Should move to reveal phase when all players commit", async function () {
            // All players commit
            for (const player of [player1, player2, player3]) {
                const { commitment } = await createCommitment(1, player);
                await descend.connect(player).commitMove(commitment);
            }

            // Check we're in reveal phase
            expect(await descend.getCurrentPhase(1)).to.equal(2); // REVEAL_PHASE
        });

        it("Should prevent committing after commit period ends", async function () {
            await time.increase(COMMIT_DURATION + 1);
            
            const { commitment } = await createCommitment(1, player1);
            await expect(descend.connect(player1).commitMove(commitment))
                .to.be.revertedWith("Commit period ended");
        });

        it("Should prevent double commits", async function () {
            const { commitment } = await createCommitment(1, player1);
            await descend.connect(player1).commitMove(commitment);
            
            await expect(descend.connect(player1).commitMove(commitment))
                .to.be.revertedWith("Already committed");
        });
    });

    describe("Reveal Phase", function () {
        beforeEach(async function () {
            await ragnarokGameMaster.initializeGame("Descend");
            await ragnarokGameMaster.startGames("Descend");
        });

        it("Should allow players to reveal moves", async function () {
            // Commit phase
            const { commitment, salt } = await createCommitment(1, player1);
            await descend.connect(player1).commitMove(commitment);
            
            // Move to reveal phase
            for (const player of [player2, player3]) {
                const { commitment } = await createCommitment(1, player);
                await descend.connect(player).commitMove(commitment);
            }

            // Reveal move
            await descend.connect(player1).revealMove(1, salt);
            expect(await descend.hasPlayerRevealed(1, player1.address)).to.be.true;
        });

        it("Should update player levels after reveals", async function () {
            // All players commit and reveal same move
            const move = 2;
            const commits = [];
            
            // Commit phase
            for (const player of [player1, player2, player3]) {
                const commit = await createCommitment(move, player);
                commits.push({ player, ...commit });
                await descend.connect(player).commitMove(commit.commitment);
            }

            // Reveal phase
            for (const { player, salt } of commits) {
                await descend.connect(player).revealMove(move, salt);
            }

            // Check levels updated
            const level = await descend.getPlayerLevel(1, player1.address);
            expect(level).to.equal(move);
        });

        it("Should handle repeated moves", async function () {
            // First round
            let commit = await createCommitment(2, player1);
            await descend.connect(player1).commitMove(commit.commitment);
            
            // Other players commit
            for (const player of [player2, player3]) {
                const { commitment } = await createCommitment(1, player);
                await descend.connect(player).commitMove(commitment);
            }

            // Reveal first move
            await descend.connect(player1).revealMove(2, commit.salt);
            
            // Complete round for other players
            for (const player of [player2, player3]) {
                const { salt } = await createCommitment(1, player);
                await descend.connect(player).revealMove(1, salt);
            }

            // Second round - try same move
            commit = await createCommitment(2, player1);
            await descend.connect(player1).commitMove(commit.commitment);
            await descend.connect(player1).revealMove(2, commit.salt);

            // The actual move should be different due to random generation
            const lastMove = await descend.getLastMove(1, player1.address);
            expect(lastMove).to.be.lte(MAX_MOVE);
        });

        it("Should eliminate players at overcrowded levels", async function () {
            // Setup multiple players to move to same level
            const move = 1;
            const commits = [];
            
            // Commit phase
            for (const player of [player1, player2, player3]) {
                const commit = await createCommitment(move, player);
                commits.push({ player, ...commit });
                await descend.connect(player).commitMove(commit.commitment);
            }

            // Reveal phase
            for (const { player, salt } of commits) {
                await descend.connect(player).revealMove(move, salt);
            }

            // Check if players were eliminated based on level capacity
            const levelPopulation = await descend.getLevelPopulation(1, move);
            const activePlayers = (await descend.getPlayerInfo(1)).filter(p => p.isActive);
            
            // Either all players should be eliminated if over capacity, or none if under capacity
            if (levelPopulation > 1) { // Assuming levelCapacity is 1 for this test
                expect(activePlayers.length).to.equal(0);
            } else {
                expect(activePlayers.length).to.equal(3);
            }
        });
    });

    describe("Game Completion", function () {
        beforeEach(async function () {
            await ragnarokGameMaster.initializeGame("Descend");
            await ragnarokGameMaster.startGames("Descend");
        });

        it("Should complete game when players reach final level", async function () {
            // Move players to final level
            const move = MAX_LEVEL; // This will be capped at MAX_LEVEL
            const commits = [];
            
            // Commit phase
            for (const player of [player1, player2, player3]) {
                const commit = await createCommitment(move, player);
                commits.push({ player, ...commit });
                await descend.connect(player).commitMove(commit.commitment);
            }

            // Reveal phase
            for (const { player, salt } of commits) {
                await descend.connect(player).revealMove(move, salt);
            }

            // Check game completed
            const gameState = await descend.getGameState(1);
            expect(gameState).to.equal(4); // GameState.Completed
        });

        it("Should complete game after max rounds", async function () {
            // Play multiple rounds until max rounds reached
            for (let round = 1; round <= 100; round++) {
                const commits = [];
                
                // Commit phase
                for (const player of [player1, player2, player3]) {
                    const commit = await createCommitment(1, player);
                    commits.push({ player, ...commit });
                    await descend.connect(player).commitMove(commit.commitment);
                }

                // Reveal phase
                for (const { player, salt } of commits) {
                    await descend.connect(player).revealMove(1, salt);
                }
            }

            // Check game completed
            const gameState = await descend.getGameState(1);
            expect(gameState).to.equal(4); // GameState.Completed
        });
    });

    describe("Multiple Games", function () {
        beforeEach(async function () {
            // Register more players
            const registrationFee = await ragnarokGameMaster.registrationFee();
            await ragnarokGameMaster.connect(player4).register({ value: registrationFee });
            await ragnarokGameMaster.connect(player5).register({ value: registrationFee });
            await ragnarokGameMaster.connect(player6).register({ value: registrationFee });
        });

        it("Should handle multiple games with different player counts", async function () {
            await ragnarokGameMaster.initializeGame("Descend");
            
            // Check games were created with correct distribution
            const games = await descend.getGames();
            expect(games.length).to.be.above(0);
            
            // Verify each game has players
            for (let i = 0; i < games.length; i++) {
                const gameInfo = await descend.getPlayerInfo(i + 1);
                expect(gameInfo.length).to.be.above(0);
            }
        });

        it("Should track player game assignments correctly", async function () {
            await ragnarokGameMaster.initializeGame("Descend");
            
            // Check each player is assigned to exactly one game
            for (const player of [player1, player2, player3, player4, player5, player6]) {
                const gameId = await descend.getPlayerGameId(player.address);
                expect(gameId).to.be.above(0);
                
                // Verify player is active in their assigned game
                const isInGame = await descend.isPlayerInGame(player.address);
                expect(isInGame).to.be.true;
            }
        });
    });

    describe("Edge Cases", function () {
        it("Should handle minimum player count", async function () {
            // Register minimum number of players (2)
            const registrationFee = await ragnarokGameMaster.registrationFee();
            const minPlayers = [player1, player2];
            
            for (const player of minPlayers) {
                await ragnarokGameMaster.connect(player).register({ value: registrationFee });
            }

            await ragnarokGameMaster.initializeGame("Descend");
            const gameInfo = await descend.getPlayerInfo(1);
            expect(gameInfo.length).to.equal(2);
        });

        it("Should prevent invalid moves", async function () {
            await ragnarokGameMaster.initializeGame("Descend");
            await ragnarokGameMaster.startGames("Descend");

            // Try to reveal without committing
            const salt = ethers.randomBytes(32);
            await expect(descend.connect(player1).revealMove(1, salt))
                .to.be.revertedWith("Must commit first");
        });

        it("Should handle player elimination correctly", async function () {
            await ragnarokGameMaster.initializeGame("Descend");
            await ragnarokGameMaster.startGames("Descend");

            // Let commit phase expire without any commits
            await time.increase(COMMIT_DURATION + 1);
            await ragnarokGameMaster.endExpiredGames("Descend");

            // Check all players were eliminated
            const gameInfo = await descend.getPlayerInfo(1);
            expect(gameInfo.every(p => !p.isActive)).to.be.true;
        });
    });
}); 