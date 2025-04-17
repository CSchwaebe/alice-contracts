// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IGame.sol";

/**
 * @title IRagnarokGameMaster
 * @notice Interface for the combined RagnarokGameMaster contract
 */
interface IRagnarokGameMaster {
    // =============================================================
    // ======================= Events ==============================
    // =============================================================
    
    // Registration Events
    event PlayerRegistered(address indexed player, uint256 playerNumber);
    event RegistrationClosed();
    event RegistrationFeeChanged(uint256 newFee);
    event PlayerRefunded(address indexed player, uint256 amount);
    event RefundFailed(address indexed player, uint256 amount);
    event GameReset();
    
    // Game Management Events
    event PlayersRegistered(address[] players);
    event GameRegistered(string gameName, address gameAddress);
    event GameStarted(string gameName, address gameAddress, uint256 gameId);
    event PlayerNumberAssigned(address indexed player, uint256 number);
    event PlayerEliminated(address indexed player, uint256 playerNumber);

    // =============================================================
    // ===================== View Functions =======================
    // =============================================================
    
    // Constants
    function MAX_PLAYERS() external view returns (uint256);
    
    // Player Registration
    function registeredPlayers(uint256) external view returns (address);
    function isRegistered(address) external view returns (bool);
    function registrationClosed() external view returns (bool);
    function registrationFee() external view returns (uint256);
    
    // Active Player Tracking
    function activePlayers(uint256) external view returns (address);
    function isActivePlayer(address) external view returns (bool);
    function playerNumbers(address) external view returns (uint256);
    function eliminatedPlayers(uint256) external view returns (address);
    function finalPlacements(address) external view returns (uint256);
    
    // Game Management
    function gameAddresses(string calldata) external view returns (address);
    function isGameRegistered(string calldata) external view returns (bool);
    function registeredGames(uint256) external view returns (string memory);
    
    // Getter Methods
    function getRegisteredPlayers() external view returns (address[] memory);
    function getActivePlayers() external view returns (address[] memory);
    function getPlayerCount() external view returns (uint256);
    function getActivePlayerCount() external view returns (uint256);
    function getEliminatedPlayers() external view returns (address[] memory);
    function getEliminatedPlayerCount() external view returns (uint256);
    function getRegisteredGames() external view returns (string[] memory);
    function getPlayerInfo(address player) external view returns (
        string memory gameName,
        uint256 gameId,
        bool isActive,
        GameState gameState,
        uint256 playerNumber
    );
    function getPlayerNumber(address player) external view returns (uint256);
    function getPlayerFinalPlacement(address player) external view returns (uint256);
    function getActivePlayersAndNumbers() external view returns (address[] memory players, uint256[] memory numbers);
    function getGames() external view returns (string[] memory gameTypes, GameInstanceInfo[][] memory gameInstances);

    // =============================================================
    // ================== State-Changing Functions ================
    // =============================================================
    
    // Player Registration Functions
    function setRegistrationFee(uint256 _newFee) external;
    function register() external payable;
    function closeRegistration() external;
    function withdraw() external;
    function resetGame() external;
    
    // Game Management Functions
    function registerGame(string calldata gameName, address gameAddress) external;
    function initializeGame(string calldata gameName) external returns (uint256);
    function playerEliminated(address player) external;
    function startGames(string calldata gameName) external returns (bool);
    function endExpiredGames(string calldata gameName) external;
    function endGames(string calldata gameName) external returns (address[] memory);
} 