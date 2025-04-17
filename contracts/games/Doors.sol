// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGame.sol";

// Import GameState and GameInstanceInfo from IGame
import {GameState, GameInstanceInfo } from "../interfaces/IGame.sol";

// Updated interface for RagnarokGameMaster's elimination function
interface IRagnarokGameMaster {
    function playerEliminated(address player) external;
}

contract Doors is IGame, Ownable {
    // ============ Constants ============
    uint256 private constant INITIAL_ROUND_DURATION = 2 minutes;
    uint256 private constant DURATION_DECREASE_PER_ROUND = 6 seconds;
    uint256 private constant MAX_ROUNDS = 2;
    uint256 private constant TARGET_PLAYERS = 20;
    uint256 private constant FINAL_ROUND_DURATION = 1 minutes;

    // ============ Structs ============
    struct GameInstance {
        GameState state;
        uint256 roundEndTime;
        uint256 currentRound;
        uint256 gameStartTime;     // When the game was initialized
        uint256 gameEndTime;       // When the game was completed
        address[] players;
        mapping(address => bool) isPlayer;
        mapping(address => uint256) playerNumbers;
        address[] activePlayers;
        mapping(address => bool) isActivePlayer;
        mapping(address => uint256) totalDoorsOpened;
    }

    struct PlayerInfo {
        address playerAddress;
        uint256 playerNumber;
        bool isActive;
        uint256 doorsOpened;
    }

    // ============ State Variables ============
    address public gameMaster;
    uint256 public gameIdCounter;
    mapping(uint256 => GameInstance) private games;
    mapping(address => uint256) public playerGameId;
    mapping(address => bool) public isPlayerInGame;

    // ============ Events ============
    event GameMasterChanged(address newGameMaster);
    event RoundStarted(uint256 indexed gameId, uint256 roundNumber, uint256 endTime);
    event DoorOpened(uint256 indexed gameId, address indexed player, bool success);
    event PlayerEliminated(uint256 indexed gameId, address indexed player, uint256 playerNumber);
    event RoundEnded(uint256 indexed gameId, uint256 roundNumber);
    event GameCompleted(uint256 indexed gameId, address[] winners);

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

    // ============ Game Initialization ============
    function initialize(
        address[] calldata _players,
        uint256[] calldata _playerNumbers
    ) external onlyGameMaster {
        require(_players.length > 0, "No players provided");
        require(
            _players.length == _playerNumbers.length,
            "Array lengths must match"
        );

        // Calculate optimal distribution
        uint256 totalPlayers = _players.length;
        uint256 numInstances = (totalPlayers + TARGET_PLAYERS - 1) /
            TARGET_PLAYERS;
        uint256 playersPerInstance = totalPlayers / numInstances;
        uint256 extraPlayers = totalPlayers % numInstances;

        uint256 playerIndex = 0;

        // Create game instances starting from ID 1
        for (uint256 i = 0; i < numInstances; i++) {
            uint256 gameId = ++gameIdCounter; // Increment first, then use
            GameInstance storage game = games[gameId];

            game.state = GameState.Pregame;
            game.currentRound = 0;
            game.gameStartTime = block.timestamp;  // Set start time on initialization

            // Calculate players for this instance
            uint256 instancePlayers = playersPerInstance;
            if (i < extraPlayers) {
                instancePlayers += 1;
            }

            // Add players to this instance
            for (uint256 j = 0; j < instancePlayers; j++) {
                address player = _players[playerIndex];
                require(player != address(0), "Invalid player address");

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

            emit GameInitialized(game.players, _playerNumbers);
        }
    }

    // ============ Game Mechanics ============
    function startGames() external override onlyGameMaster returns (bool) {
        bool allStarted = true;
        uint256 activeGames = 0;

        // Iterate through all game instances
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage game = games[i];

            // Skip completed games
            if (game.state == GameState.Completed) {
                continue;
            }

            activeGames++;

            // Only start first round if game is in pregame state
            if (game.state == GameState.Pregame && 
                game.activePlayers.length > 0 && 
                game.currentRound == 0) {  // Ensure it's the first round
                
                game.currentRound = 1;  // Start at round 1
                game.state = GameState.Active;
                game.roundEndTime = block.timestamp + _getRoundDuration(1);

                emit RoundStarted(i, game.currentRound, game.roundEndTime);
            } else {
                allStarted = false; // At least one game couldn't start
            }
        }

        // If no active games, return true
        if (activeGames == 0) {
            return true;
        }

        return allStarted;
    }

    function openDoor() external returns (bool) {
        require(isPlayerInGame[msg.sender], "Player not in any game");
        uint256 gameId = playerGameId[msg.sender];

        GameInstance storage game = games[gameId];
        require(game.state == GameState.Active, "Game not active");
        require(game.isActivePlayer[msg.sender], "Not an active player");
        
        // Check if round has expired
        if (block.timestamp > game.roundEndTime) {
            _handleExpiredRound(gameId);
            return false;
        }

        // Normal door opening logic continues here
        game.totalDoorsOpened[msg.sender]++;

        uint256 randomValue = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    msg.sender,
                    game.currentRound,
                    gameId,
                    address(this)
                )
            )
        );
        bool success = randomValue % 2 == 0;

        emit DoorOpened(gameId, msg.sender, success);

        if (!success) {
            eliminatePlayer(gameId, msg.sender);
            _endAndCheckFinalRound(gameId);
            return false;
        }

        // Add dummy operations to equalize gas with failure path
        {
            // Dummy storage writes to match eliminatePlayer storage operations
            bool dummy1 = game.isActivePlayer[msg.sender];
            game.isActivePlayer[msg.sender] = dummy1;
            bool dummy2 = isPlayerInGame[msg.sender];
            isPlayerInGame[msg.sender] = dummy2;
            
            // Dummy array operation to match array manipulation in eliminatePlayer
            uint256 len = game.activePlayers.length;
            address dummyAddr = game.activePlayers[len - 1];
            game.activePlayers[len - 1] = dummyAddr;
            
            // Dummy external call to match gameMaster call
            try IRagnarokGameMaster(gameMaster).playerEliminated(address(0)) {
            } catch {}
        }

        _endAndCheckFinalRound(gameId);
        return true;
    }

    function endExpiredGames() external override onlyGameMaster {
        // Iterate through all game instances
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage game = games[i];

            // Check if this instance needs to be ended
            if (
                game.state == GameState.Active &&
                block.timestamp > game.roundEndTime
            ) {
                _handleExpiredRound(i);
            }
        }
    }

    function endGame()
        external
        override
        onlyGameMaster
        returns (address[] memory winners)
    {
        // Ensure all games are completed
        _validateAndCompleteGames();

        // Get winners from all completed games
        return _collectWinners();
    }

    // ============ Internal Functions ============
    function _handleExpiredRound(uint256 gameId) private {
        GameInstance storage game = games[gameId];
        
        // Eliminate all active players for not opening doors in time
        uint256 playerCount = game.activePlayers.length;
        for (uint256 j = 0; j < playerCount; j++) {
            address player = game.activePlayers[0]; // Always remove from start since array shrinks
            eliminatePlayer(gameId, player);
        }

        // Mark game as completed since all players were eliminated
        game.state = GameState.Completed;
        game.gameEndTime = block.timestamp;  // Set end time when game completes
        emit GameCompleted(gameId, new address[](0)); // Empty array as no winners
        emit RoundEnded(gameId, game.currentRound);
    }
    
    function _endAndCheckFinalRound(uint256 gameId) private {
        GameInstance storage game = games[gameId];
        
        // If this is the final round (10) or only one player remains, complete the game
        if (game.currentRound >= MAX_ROUNDS || game.activePlayers.length <= 1) {
            game.state = GameState.Completed;
            game.gameEndTime = block.timestamp;  // Set end time when game completes
            emit GameCompleted(gameId, game.activePlayers);
            emit RoundEnded(gameId, game.currentRound);
        } else {
            // Otherwise, just end the round and start the next one
            game.state = GameState.Waiting;
            emit RoundEnded(gameId, game.currentRound);
            _startRound(gameId);
        }
    }

    function eliminatePlayer(uint256 gameId, address player) private {
        GameInstance storage game = games[gameId];
        require(game.isActivePlayer[player], "Player not active");

        game.isActivePlayer[player] = false;
        isPlayerInGame[player] = false; // Remove player tracking

        for (uint i = 0; i < game.activePlayers.length; i++) {
            if (game.activePlayers[i] == player) {
                game.activePlayers[i] = game.activePlayers[
                    game.activePlayers.length - 1
                ];
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

    function _validateAndCompleteGames() private {
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage game = games[i];

            // Check if game has finished all rounds or is already completed
            require(
                game.currentRound >= MAX_ROUNDS ||
                    game.state == GameState.Completed,
                "Not all instances have completed maximum rounds"
            );

            // Complete any games that aren't already completed
            if (game.state != GameState.Completed) {
                game.state = GameState.Completed;
                game.gameEndTime = block.timestamp;  // Set end time when game completes
                emit GameCompleted(i, game.activePlayers);
            }
        }
    }

    function _collectWinners() private view returns (address[] memory winners) {
        // Count total winners
        uint256 totalWinners = 0;
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            totalWinners += games[i].activePlayers.length;
        }

        // Create and fill winners array
        winners = new address[](totalWinners);
        uint256 currentIndex = 0;

        for (uint256 i = 1; i <= gameIdCounter; i++) {
            address[] memory instanceWinners = games[i].activePlayers;
            for (uint256 j = 0; j < instanceWinners.length; j++) {
                winners[currentIndex++] = instanceWinners[j];
            }
        }

        return winners;
    }

    function _startRound(uint256 gameId) private {
        GameInstance storage game = games[gameId];
        
        // Only start new round if game is in valid state and has active players
        if (game.state == GameState.Waiting && 
            game.activePlayers.length > 0 && 
            game.currentRound < MAX_ROUNDS) {
            game.currentRound++;
            game.state = GameState.Active;
            game.roundEndTime = block.timestamp + _getRoundDuration(game.currentRound);
            
            emit RoundStarted(gameId, game.currentRound, game.roundEndTime);
        }
    }

    function _getRoundDuration(uint256 roundNumber) private pure returns (uint256) {
        uint256 decrease = (roundNumber - 1) * DURATION_DECREASE_PER_ROUND;
        
        // Make sure we don't go below the minimum duration
        if (decrease > INITIAL_ROUND_DURATION - FINAL_ROUND_DURATION) {
            return FINAL_ROUND_DURATION;
        }
        
        return INITIAL_ROUND_DURATION - decrease;
    }

    // ============ View Functions ============
    // Game Info Queries
    function getGameInfo(uint256 gameId) external view isValidGameId(gameId) returns (GameInfo memory) {
        GameInstance storage gameInstance = games[gameId];
        GameInfo memory game = GameInfo({
            state: gameInstance.state,
            currentRound: gameInstance.currentRound,
            roundEndTime: gameInstance.roundEndTime,
            gameStartTime: gameInstance.gameStartTime,
            gameEndTime: gameInstance.gameEndTime
        });
        return game;
    }

    /**
     * @notice Get the current state of a game instance
     * @param gameId ID of the game instance
     * @return state Current state of the game
     */
    function getGameState(uint256 gameId) external view isValidGameId(gameId) returns (GameState) {
        return games[gameId].state;
    }

    /**
     * @notice Get information about all game instances
     * @return gamesInfo Array of game instance information
     */
    function getGames() external view returns (GameInstanceInfo[] memory gamesInfo) {
        // Create array to hold all game instances
        gamesInfo = new GameInstanceInfo[](gameIdCounter);
        
        // Fill array with game instance info
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage currentGame = games[i];
            gamesInfo[i - 1] = GameInstanceInfo({
                gameId: i,
                state: currentGame.state,
                currentRound: currentGame.currentRound,
                activePlayerCount: currentGame.activePlayers.length
            });
        }
        
        return gamesInfo;
    }

    function getGameName() external pure returns (string memory) {
        return "Doors";
    }

    // Player Info Queries
    function getPlayerInfo(uint256 gameId) external view isValidGameId(gameId) returns (PlayerInfo[] memory) {
        GameInstance storage game = games[gameId];

        // Create array to hold all player info
        PlayerInfo[] memory playerInfo = new PlayerInfo[](game.players.length);

        // Fill player info array
        for (uint256 i = 0; i < game.players.length; i++) {
            address player = game.players[i];
            playerInfo[i] = PlayerInfo({
                playerAddress: player,
                playerNumber: game.playerNumbers[player],
                isActive: game.isActivePlayer[player],
                doorsOpened: game.totalDoorsOpened[player]
            });
        }

        return playerInfo;
    }

    function getPlayerNumber(uint256 gameId, address player) external view isValidGameId(gameId) returns (uint256) {
        require(games[gameId].isPlayer[player], "Player not in game");
        return games[gameId].playerNumbers[player];
    }

    function getPlayerGameId(address player) external view override returns (uint256) {
        if (!isPlayerInGame[player]) {
            return 0; // 0 definitively means "not in game"
        }
        return playerGameId[player]; // Will always be > 0
    }

    function getDoorsOpened(uint256 gameId, address player) external view isValidGameId(gameId) returns (uint256) {
        return games[gameId].totalDoorsOpened[player];
    }

    // Player List Queries
    function getPlayers(uint256 gameId) external view isValidGameId(gameId) returns (address[] memory) {
        return games[gameId].players;
    }

    function getPlayers() external view override returns (address[] memory) {
        uint256 totalPlayers = 0;

        // First count total players across all instances
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            totalPlayers += games[i].players.length;
        }

        // Create array to hold all players
        address[] memory allPlayers = new address[](totalPlayers);
        uint256 currentIndex = 0;

        // Fill array with players from all instances
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            address[] memory instancePlayers = games[i].players;
            for (uint256 j = 0; j < instancePlayers.length; j++) {
                allPlayers[currentIndex] = instancePlayers[j];
                currentIndex++;
            }
        }

        return allPlayers;
    }

    function getActivePlayers(uint256 gameId) external view isValidGameId(gameId) returns (address[] memory) {
        return games[gameId].activePlayers;
    }

    function getActivePlayers() external view returns (address[] memory) {
        uint256 totalActivePlayers = 0;

        // First count total active players across all instances
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            totalActivePlayers += games[i].activePlayers.length;
        }

        // Create array to hold all active players
        address[] memory allActivePlayers = new address[](totalActivePlayers);
        uint256 currentIndex = 0;

        // Fill array with active players from all instances
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            address[] memory instanceActivePlayers = games[i].activePlayers;
            for (uint256 j = 0; j < instanceActivePlayers.length; j++) {
                allActivePlayers[currentIndex] = instanceActivePlayers[j];
                currentIndex++;
            }
        }

        return allActivePlayers;
    }

}
