// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IGame.sol";

interface IDoors is IGame {
    // Structs
    struct PlayerInfo {
        address playerAddress;
        uint256 playerNumber;
        bool isActive;
        uint256 doorsOpened;
    }

    // Events
    event GameMasterChanged(address newGameMaster);
    event RoundStarted(uint256 indexed gameId, uint256 roundNumber, uint256 endTime);
    event DoorOpened(uint256 indexed gameId, address indexed player, bool success);
    event PlayerEliminated(uint256 indexed gameId, address indexed player, uint256 playerNumber);
    event RoundEnded(uint256 indexed gameId, uint256 roundNumber);
    event GameCompleted(uint256 indexed gameId, address[] winners);

    // View Functions
    function gameMaster() external view returns (address);
    function gameIdCounter() external view returns (uint256);
    function playerGameId(address) external view returns (uint256);
    function isPlayerInGame(address) external view returns (bool);
    function getGameInfo(uint256 gameId) external view returns (GameInfo memory);
    function getGameState(uint256 gameId) external view returns (GameState);
    function getGameName() external pure returns (string memory);
    function getPlayerInfo(uint256 gameId) external view returns (PlayerInfo[] memory);
    function getPlayerNumber(uint256 gameId, address player) external view returns (uint256);
    function getDoorsOpened(uint256 gameId, address player) external view returns (uint256);
    function getPlayers(uint256 gameId) external view returns (address[] memory);
    function getActivePlayers(uint256 gameId) external view returns (address[] memory);
   

    // State-Changing Functions
    function setGameMaster(address _newGameMaster) external;
    function initialize(address[] calldata _players, uint256[] calldata _playerNumbers) external;
    function startGames() external returns (bool);
    function openDoor() external returns (bool);
    function endExpiredGames() external;
    function endGame() external returns (address[] memory winners);
} 