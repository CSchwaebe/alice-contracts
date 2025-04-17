// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGame.sol";

// Interface for RagnarokGameMaster's elimination function
interface IRagnarokGameMaster {
    function playerEliminated(address player) external;
}

contract Threes is IGame, Ownable {
    // ============ Constants ============
    uint256 private constant COMMIT_DURATION = 5 minutes;
    uint256 private constant REVEAL_DURATION = 5 minutes;
    uint256 private constant PLAYERS_PER_GAME = 3;
    uint256 private constant COMMIT_ROUND = 1;
    uint256 private constant REVEAL_ROUND = 2;

    // ============ Enums ============
    enum RoundState {
        NotStarted,
        Commit,
        Reveal,
        Completed
    }

    // ============ Structs ============
    struct GameInstance {
        GameState state;
        uint256 currentRound;      // 1 = commit stage, 2 = reveal stage
        uint256 roundEndTime;      // When the current round ends
        uint256 gameStartTime;     // When the game was initialized
        uint256 gameEndTime;       // When the game was completed
        address[] players;
        mapping(address => bool) isPlayer;
        mapping(address => uint256) playerNumbers;
        address[] activePlayers;
        mapping(address => bool) isActivePlayer;
        // Commit-reveal data
        mapping(address => bytes32) commitments;
        mapping(address => uint256) reveals;
        mapping(address => bool) hasCommitted;
        mapping(address => bool) hasRevealed;
        uint256 commitCount;       // Track number of commits
        uint256 revealCount;       // Track number of reveals
    }

    struct ThreesPlayerInfo {
        address playerAddress;
        uint256 playerNumber;
        bool hasCommitted;
        bool hasRevealed;
        bool isActive;
    }

    // ============ State Variables ============
    address public gameMaster;
    uint256 public gameIdCounter;
    mapping(uint256 => GameInstance) private games;
    mapping(address => uint256) public playerGameId;
    mapping(address => bool) public isPlayerInGame;

    // ============ Events ============
    event GameMasterChanged(address newGameMaster);
    event PlayerCommitted(uint256 indexed gameId, address indexed player);
    event PlayerRevealed(uint256 indexed gameId, address indexed player, uint256 choice);
    event PlayerEliminated(uint256 indexed gameId, address indexed player, uint256 playerNumber);
    event GameCompleted(uint256 indexed gameId, address[] winners);
    event RoundStarted(uint256 indexed gameId, uint256 roundNumber, uint256 endTime);

    // ============ Modifiers ============
    modifier onlyGameMaster() {
        require(msg.sender == gameMaster, "Only GameMaster can call");
        _;
    }

    modifier isValidGameId(uint256 gameId) {
        require(gameId > 0 && gameId <= gameIdCounter, "Invalid game ID");
        _;
    }

    // ============ Constructor ============
    constructor() Ownable(msg.sender) {
        gameMaster = msg.sender;
    }

    // ============ Admin Functions ============
    function setGameMaster(address _newGameMaster) external onlyOwner {
        require(_newGameMaster != address(0), "Invalid GameMaster address");
        gameMaster = _newGameMaster;
        emit GameMasterChanged(_newGameMaster);
    }

    // ============ Game Functions ============
    function initialize(
        address[] calldata _players,
        uint256[] calldata _playerNumbers
    ) external onlyGameMaster {
        require(_players.length > 0, "No players provided");
        require(_players.length == _playerNumbers.length, "Array lengths must match");
        require(_players.length % PLAYERS_PER_GAME == 0, "Player count must be divisible by 3");

        uint256 numInstances = _players.length / PLAYERS_PER_GAME;
        uint256 playerIndex = 0;

        for (uint256 i = 0; i < numInstances; i++) {
            uint256 gameId = ++gameIdCounter;
            GameInstance storage game = games[gameId];
            game.state = GameState.Pregame;
            game.gameStartTime = block.timestamp;  // Set start time on initialization

            // Add exactly 3 players to this instance
            for (uint256 j = 0; j < PLAYERS_PER_GAME; j++) {
                address player = _players[playerIndex];
                require(player != address(0), "Invalid player address");
                
                // Only check game state if player is marked as in a game
                if (isPlayerInGame[player]) {
                    uint256 currentGameId = playerGameId[player];
                    require(currentGameId == 0 || games[currentGameId].state == GameState.Completed, 
                            "Player already in active game");
                }

                game.players.push(player);
                game.playerNumbers[player] = _playerNumbers[playerIndex];
                game.isPlayer[player] = true;
                game.activePlayers.push(player);
                game.isActivePlayer[player] = true;
                playerIndex++;

                // Track player's game
                playerGameId[player] = gameId;
                isPlayerInGame[player] = true;
            }

            require(game.players.length == PLAYERS_PER_GAME, "Each game must have exactly 3 players");
            emit GameInitialized(game.players, _playerNumbers);
        }
    }

    function startGames() external override onlyGameMaster returns (bool) {
        bool allStarted = true;
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage game = games[i];
            if (game.state == GameState.Pregame && game.activePlayers.length > 0) {
                game.state = GameState.Active;
                game.currentRound = COMMIT_ROUND;
                game.roundEndTime = block.timestamp + COMMIT_DURATION;
                emit RoundStarted(i, COMMIT_ROUND, game.roundEndTime);
            } else {
                allStarted = false;
            }
        }
        return allStarted;
    }

    function commitChoice(bytes32 commitment) external {
        require(isPlayerInGame[msg.sender], "Player not in any game");
        uint256 gameId = playerGameId[msg.sender];
        GameInstance storage game = games[gameId];
        
        require(game.state == GameState.Active, "Game not active");
        require(game.currentRound == COMMIT_ROUND, "Not in commit stage");
        require(block.timestamp <= game.roundEndTime, "Commit period ended");
        require(!game.hasCommitted[msg.sender], "Already committed");
        
        game.commitments[msg.sender] = commitment;
        game.hasCommitted[msg.sender] = true;
        game.commitCount++;
        
        emit PlayerCommitted(gameId, msg.sender);

        // If all active players have committed, move to reveal stage
        if (game.commitCount == game.activePlayers.length) {
            game.currentRound = REVEAL_ROUND;
            game.roundEndTime = block.timestamp + REVEAL_DURATION;
            emit RoundStarted(gameId, REVEAL_ROUND, game.roundEndTime);
        }
    }

    function _handleCommitStageEnd(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        require(game.currentRound == COMMIT_ROUND, "Not in commit stage");
        require(block.timestamp > game.roundEndTime || game.commitCount == game.activePlayers.length, 
                "Cannot end commit stage yet");

        // If all players committed, move to reveal stage
        if (game.commitCount == game.activePlayers.length) {
            game.currentRound = REVEAL_ROUND;
            game.roundEndTime = block.timestamp + REVEAL_DURATION;
            emit RoundStarted(gameId, REVEAL_ROUND, game.roundEndTime);
            return;
        }

        // Otherwise, eliminate players who didn't commit
        address[] memory playersToEliminate = new address[](game.activePlayers.length);
        uint256 eliminationCount = 0;

        // First mark all players who didn't commit
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            if (!game.hasCommitted[game.activePlayers[i]]) {
                playersToEliminate[eliminationCount++] = game.activePlayers[i];
            }
        }

        // Eliminate marked players
        for (uint256 i = 0; i < eliminationCount; i++) {
            _eliminatePlayer(gameId, playersToEliminate[i]);
        }

        // Complete the game with committed players as winners
        game.state = GameState.Completed;
        game.gameEndTime = block.timestamp;  // Set end time when game completes
        emit GameCompleted(gameId, game.activePlayers);
    }

    // Player reveals their choice
    function revealChoice(uint256 choice, bytes32 salt) external {
        require(isPlayerInGame[msg.sender], "Player not in any game");
        uint256 gameId = playerGameId[msg.sender];
        GameInstance storage game = games[gameId];
        
        require(game.state == GameState.Active, "Game not active");
        require(game.hasCommitted[msg.sender], "Must commit first");
        require(!game.hasRevealed[msg.sender], "Already revealed");
        require(choice >= 1 && choice <= 3, "Invalid choice");

        // If commit stage has expired and we haven't moved to reveal stage yet, handle commit stage end
        if (game.currentRound == COMMIT_ROUND && block.timestamp > game.roundEndTime) {
            _handleCommitStageEnd(gameId);
            // If game completed during commit stage end, return
            if (game.state == GameState.Completed) {
                return;
            }
        }

        // Now verify we're in reveal stage
        require(game.currentRound == REVEAL_ROUND, "Not in reveal stage");
        require(block.timestamp <= game.roundEndTime, "Reveal period ended");
        
        // Verify commitment
        bytes32 commitment = keccak256(abi.encodePacked(choice, salt, msg.sender));
        require(commitment == game.commitments[msg.sender], "Invalid reveal");
        
        game.reveals[msg.sender] = choice;
        game.hasRevealed[msg.sender] = true;
        game.revealCount++;
        
        emit PlayerRevealed(gameId, msg.sender, choice);

        // If all active players have revealed or reveal period has ended, resolve the game
        if (game.revealCount == game.activePlayers.length || block.timestamp > game.roundEndTime) {
            _resolveGame(gameId);
        }
    }

    function endExpiredGames() external override onlyGameMaster {
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage game = games[i];
            if (game.state == GameState.Active) {
                if (game.currentRound == COMMIT_ROUND && block.timestamp > game.roundEndTime) {
                    // Handle expired commit stage
                    _handleCommitStageEnd(i);
                } else if (game.currentRound == REVEAL_ROUND && block.timestamp > game.roundEndTime) {
                    _resolveGame(i);
                }
            }
        }
    }

    function endGame() external override onlyGameMaster returns (address[] memory) {
        address[] memory winners = new address[](0);
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage game = games[i];
            if (game.state == GameState.Active) {
                _resolveGame(i);
            }
        }
        return winners;
    }

    // ============ Internal Functions ============
    function _resolveGame(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        
        // First eliminate players who didn't reveal - they're always eliminated
        address[] memory playersToEliminate = new address[](game.activePlayers.length);
        uint256 eliminationCount = 0;
        
        // First mark all players who didn't reveal
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            if (!game.hasRevealed[game.activePlayers[i]]) {
                playersToEliminate[eliminationCount++] = game.activePlayers[i];
            }
        }

        // Eliminate marked players
        for (uint256 i = 0; i < eliminationCount; i++) {
            _eliminatePlayer(gameId, playersToEliminate[i]);
        }

        // Only process choice comparisons if we have exactly 3 players who revealed
        if (game.activePlayers.length == 3) {
            uint256[] memory choices = new uint256[](3);
            for (uint256 i = 0; i < 3; i++) {
                choices[i] = game.reveals[game.activePlayers[i]];
            }

            // Count occurrences of each choice
            uint256[4] memory counts; // 0 unused, 1-3 for choices
            for (uint256 i = 0; i < 3; i++) {
                counts[choices[i]]++;
            }

            eliminationCount = 0;
            // If two chose same number, eliminate them
            // If all different, eliminate all
            // If all same, no eliminations
            if (counts[1] == 2 || counts[2] == 2 || counts[3] == 2) {
                // Two players chose the same, eliminate them
                for (uint256 i = 0; i < game.activePlayers.length; i++) {
                    if (counts[game.reveals[game.activePlayers[i]]] == 2) {
                        playersToEliminate[eliminationCount++] = game.activePlayers[i];
                    }
                }
            } else if (counts[1] != 3 && counts[2] != 3 && counts[3] != 3) {
                // All different choices, copy all players to eliminate
                for (uint256 i = 0; i < game.activePlayers.length; i++) {
                    playersToEliminate[eliminationCount++] = game.activePlayers[i];
                }
            }
            // If all same, no eliminations needed

            // Eliminate marked players
            for (uint256 i = 0; i < eliminationCount; i++) {
                _eliminatePlayer(gameId, playersToEliminate[i]);
            }
        }
        // If less than 3 players revealed, they're all safe - we already eliminated non-revealing players

        // Complete the game
        game.state = GameState.Completed;
        game.gameEndTime = block.timestamp;  // Set end time when game completes
        emit GameCompleted(gameId, game.activePlayers);
    }

    function _eliminatePlayer(uint256 gameId, address player) internal {
        GameInstance storage game = games[gameId];
        require(game.isActivePlayer[player], "Player not active");

        game.isActivePlayer[player] = false;
        isPlayerInGame[player] = false;
        playerGameId[player] = 0;

        // Remove from activePlayers array
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            if (game.activePlayers[i] == player) {
                game.activePlayers[i] = game.activePlayers[game.activePlayers.length - 1];
                game.activePlayers.pop();
                break;
            }
        }

        // Notify RagnarokGameMaster about elimination
        try IRagnarokGameMaster(gameMaster).playerEliminated(player) {
            // Successfully notified the RagnarokGameMaster
        } catch {
            // Silently fail if RagnarokGameMaster rejects or doesn't have the function
        }

        emit PlayerEliminated(gameId, player, game.playerNumbers[player]);
    }

    // ============ View Functions ============
    function getGameName() external pure override returns (string memory) {
        return "Threes";
    }

    function getGameInfo(uint256 gameId) external view override isValidGameId(gameId) returns (GameInfo memory) {
        GameInstance storage game = games[gameId];
        return GameInfo({
            state: game.state,
            currentRound: game.currentRound,
            roundEndTime: game.roundEndTime,
            gameStartTime: game.gameStartTime,
            gameEndTime: game.gameEndTime
        });
    }

    function getGameState(uint256 gameId) external view override isValidGameId(gameId) returns (GameState) {
        return games[gameId].state;
    }

    function getGames() external view override returns (GameInstanceInfo[] memory gamesInfo) {
        gamesInfo = new GameInstanceInfo[](gameIdCounter);
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage game = games[i];
            gamesInfo[i - 1] = GameInstanceInfo({
                gameId: i,
                state: game.state,
                currentRound: game.currentRound,
                activePlayerCount: game.activePlayers.length
            });
        }
        return gamesInfo;
    }

    function getPlayers() external view override returns (address[] memory) {
        uint256 totalPlayers = 0;
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            totalPlayers += games[i].players.length;
        }

        address[] memory allPlayers = new address[](totalPlayers);
        uint256 currentIndex = 0;

        for (uint256 i = 1; i <= gameIdCounter; i++) {
            address[] memory instancePlayers = games[i].players;
            for (uint256 j = 0; j < instancePlayers.length; j++) {
                allPlayers[currentIndex++] = instancePlayers[j];
            }
        }

        return allPlayers;
    }

    function getPlayerGameId(address player) external view override returns (uint256) {
        return playerGameId[player];
    }

    function getActivePlayers() external view override returns (address[] memory) {
        uint256 totalActive = 0;
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            totalActive += games[i].activePlayers.length;
        }

        address[] memory allActive = new address[](totalActive);
        uint256 currentIndex = 0;

        for (uint256 i = 1; i <= gameIdCounter; i++) {
            address[] memory instanceActive = games[i].activePlayers;
            for (uint256 j = 0; j < instanceActive.length; j++) {
                allActive[currentIndex++] = instanceActive[j];
            }
        }

        return allActive;
    }

    function getPlayerNumber(uint256 gameId, address player) external view override isValidGameId(gameId) returns (uint256) {
        require(games[gameId].isPlayer[player], "Player not in game");
        return games[gameId].playerNumbers[player];
    }

    // Additional view functions specific to Threes
    function getCurrentRound(uint256 gameId) external view isValidGameId(gameId) returns (uint256) {
        return games[gameId].currentRound;
    }

    function getRoundEndTime(uint256 gameId) external view isValidGameId(gameId) returns (uint256) {
        return games[gameId].roundEndTime;
    }

    function hasPlayerCommitted(uint256 gameId, address player) external view isValidGameId(gameId) returns (bool) {
        return games[gameId].hasCommitted[player];
    }

    function hasPlayerRevealed(uint256 gameId, address player) external view isValidGameId(gameId) returns (bool) {
        return games[gameId].hasRevealed[player];
    }

    /**
     * @notice Get information about all players in a game instance
     * @param gameId The ID of the game instance
     * @return Array of player information including commit/reveal status
     */
    function getPlayerInfo(uint256 gameId) external view isValidGameId(gameId) returns (ThreesPlayerInfo[] memory) {
        GameInstance storage game = games[gameId];
        ThreesPlayerInfo[] memory playersInfo = new ThreesPlayerInfo[](game.players.length);

        for (uint256 i = 0; i < game.players.length; i++) {
            address playerAddress = game.players[i];
            playersInfo[i] = ThreesPlayerInfo({
                playerAddress: playerAddress,
                playerNumber: game.playerNumbers[playerAddress],
                hasCommitted: game.hasCommitted[playerAddress],
                hasRevealed: game.hasRevealed[playerAddress],
                isActive: game.isActivePlayer[playerAddress]
            });
        }

        return playersInfo;
    }
} 