// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IGame
 * @notice Interface for game contracts in the Ragnarok system
 */

// Game state enum
enum GameState {
    NotInitialized, // Game not yet initialized
    Pregame,    // Game not yet started
    Active,     // Game is currently active
    Waiting,    // Between rounds
    Completed   // Game has finished
}

struct GameInstanceInfo {
    uint256 gameId;
    GameState state;
    uint256 currentRound;
    uint256 activePlayerCount;
    
}

interface IGame {
    

    struct GameInfo {
        GameState state;
        uint256 currentRound;
        uint256 roundEndTime;
        uint256 gameStartTime;     // When the game was initialized
        uint256 gameEndTime;       // When the game was completed
    }

    function initialize(
        address[] calldata players,
        uint256[] calldata playerNumbers
    ) external;
    function startGames() external returns (bool);
    function endExpiredGames() external;
    function getPlayers() external view returns (address[] memory);
    function getPlayerGameId(
        address player
    ) external view returns (uint256 gameId);
    function getGameName() external view returns (string memory);
    function endGame() external returns (address[] memory winners);
    function getActivePlayers() external view returns (address[] memory);
    function getPlayerNumber(uint256 gameId, address player) external view returns (uint256);
    function getGameInfo(uint256 gameId) external view returns (GameInfo memory);
    function getGameState(uint256 gameId) external view returns (GameState);
    function getGames() external view returns (GameInstanceInfo[] memory games);
    event GameInitialized(address[] players, uint256[] playerNumbers);
}
