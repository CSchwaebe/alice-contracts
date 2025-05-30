// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IGame.sol";
import "./Points.sol";

// Import GameState enum from IGame
import {GameState} from "./interfaces/IGame.sol";

/**
 * @title GameMaster
 * @notice Combined contract that handles player registration and game management
 */
contract GameMaster is Ownable {
    // =============================================================
    // ==================== Constants ==============================
    // =============================================================
    uint256 public maxPlayers = 1000;
    Points public pointsContract;

    // =============================================================
    // ================== Player Registration ======================
    // =============================================================
    address[] public registeredPlayers;
    mapping(address => bool) public isRegistered;
    bool public registrationClosed;
    uint256 public registrationFee = 12 ether;
    
    // =============================================================
    // ================== Active Player Tracking ==================
    // =============================================================
    address[] public activePlayers;
    mapping(address => bool) public isActivePlayer;
    mapping(address => uint256) public playerNumbers;
    
    // Track eliminated players in order of elimination
    address[] public eliminatedPlayers;
    // Track final placement (1000 = first eliminated, 1 = winner)
    mapping(address => uint256) public finalPlacements;
    
    // =============================================================
    // ================== Game Management =========================
    // =============================================================
    mapping(string => address) public gameAddresses;
    mapping(string => bool) public isGameRegistered;
    string[] public registeredGames;
    
    // =============================================================
    // ======================= Events =============================
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
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Sets the Points contract address
     * @param _pointsContract Address of the Points contract
     */
    function setPointsContract(address payable _pointsContract) external onlyOwner {
        require(_pointsContract != address(0), "Invalid Points contract address");
        pointsContract = Points(_pointsContract);
    }
    
    // =============================================================
    // ================== Player Registration Functions ===========
    // =============================================================
    
    /**
     * @notice Sets the registration fee
     * @param _newFee New fee amount in wei
     */
    function setRegistrationFee(uint256 _newFee) external onlyOwner {
        require(_newFee > 0, "Fee must be greater than 0");
        registrationFee = _newFee;
        emit RegistrationFeeChanged(_newFee);
    }
    
    /**
     * @notice Register for the game by sending ETH
     */
    function register() external payable {
        require(!registrationClosed, "Registration is closed");
        require(msg.value >= registrationFee, "Must send at least the registration fee");
        require(!isRegistered[msg.sender], "Already registered");
        require(address(pointsContract) != address(0), "Points contract not set");
        
        // Calculate points portion (1/6 of registration fee)
        uint256 pointsPortion = registrationFee / 6;
        
        // Send points portion to Points contract
        pointsContract.depositFor{value: pointsPortion}(msg.sender);
        
        // Assign player number
        uint256 playerNumber = registeredPlayers.length;
        playerNumbers[msg.sender] = playerNumber;
        
        registeredPlayers.push(msg.sender);
        isRegistered[msg.sender] = true;
        
        // Add to active players as well
        activePlayers.push(msg.sender);
        isActivePlayer[msg.sender] = true;
        
        emit PlayerRegistered(msg.sender, playerNumber);
        
        // Auto-close registration when max players reached
        if (registeredPlayers.length >= maxPlayers) {
            registrationClosed = true;
            emit RegistrationClosed();
        }
        
        // Return excess payment if any
        uint256 excess = msg.value - registrationFee;
        if (excess > 0) {
            (bool success, ) = msg.sender.call{value: excess}("");
            require(success, "Failed to return excess payment");
        }
    }

    /**
     * @notice Register for the game with a referral code
     * @param referralCode The referral code to use
     */
    function registerWithReferral(string calldata referralCode) external payable {
        require(!registrationClosed, "Registration is closed");
        require(msg.value >= registrationFee, "Must send at least the registration fee");
        require(!isRegistered[msg.sender], "Already registered");
        require(address(pointsContract) != address(0), "Points contract not set");
        
        // Calculate points portion (1/6 of registration fee)
        uint256 pointsPortion = registrationFee / 6;
        
        // Send points portion to Points contract with referral
        pointsContract.depositFor{value: pointsPortion}(msg.sender, referralCode);
        
        // Assign player number
        uint256 playerNumber = registeredPlayers.length;
        playerNumbers[msg.sender] = playerNumber;
        
        registeredPlayers.push(msg.sender);
        isRegistered[msg.sender] = true;
        
        // Add to active players as well
        activePlayers.push(msg.sender);
        isActivePlayer[msg.sender] = true;
        
        emit PlayerRegistered(msg.sender, playerNumber);
        
        // Auto-close registration when max players reached
        if (registeredPlayers.length >= maxPlayers) {
            registrationClosed = true;
            emit RegistrationClosed();
        }
        
        // Return excess payment if any
        uint256 excess = msg.value - registrationFee;
        if (excess > 0) {
            (bool success, ) = msg.sender.call{value: excess}("");
            require(success, "Failed to return excess payment");
        }
    }
    
    /**
     * @notice Close registration (owner only)
     */
    function closeRegistration() external onlyOwner {
        registrationClosed = true;
        emit RegistrationClosed();
    }
    
    /**
     * @notice Allows the contract owner to withdraw all collected registration fees
     * @dev Uses low-level call to transfer ETH to avoid gas limitations of transfer()
     * @return true if the withdrawal was successful
     */
    function withdraw() external onlyOwner returns (bool) {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "No funds to withdraw");

        address ownerAddress = owner();
        (bool transferSuccess, ) = ownerAddress.call{value: contractBalance}("");
        require(transferSuccess, "ETH transfer to owner failed");
        
        return true;
    }
    
    /**
     * @notice Reset game and refund all registered players
     */
    function resetGame() external onlyOwner {
        require(!registrationClosed || registeredPlayers.length > 0, "No players to refund");
        
        // Refund each registered player
        for (uint256 i = 0; i < registeredPlayers.length; i++) {
            address player = registeredPlayers[i];
            (bool success, ) = player.call{value: registrationFee}("");
            
            // Log failure but continue to avoid locking funds
            if (!success) {
                emit RefundFailed(player, registrationFee);
            } else {
                emit PlayerRefunded(player, registrationFee);
            }
            
            // Clear final placement
            delete finalPlacements[player];
        }
        
        // Reset state variables
        delete registeredPlayers;
        delete activePlayers;
        delete eliminatedPlayers;
        registrationClosed = false;
        
        // Clear player tracking
        for (uint i = 0; i < registeredPlayers.length; i++) {
            address player = registeredPlayers[i];
            isRegistered[player] = false;
            isActivePlayer[player] = false;
            delete playerNumbers[player];
        }
        
        emit GameReset();
    }
    
    /**
     * @notice Allows owner to register multiple players without requiring registration fee
     * @dev Only callable by contract owner, useful for special events or testing
     * @param players Array of player addresses to register
     */
    function registerPlayersBatch(address[] calldata players) external onlyOwner {
        require(!registrationClosed, "Registration is closed");
        require(registeredPlayers.length + players.length <= maxPlayers, "Would exceed maximum players");
        
        for (uint256 i = 0; i < players.length; i++) {
            address player = players[i];
            require(player != address(0), "Invalid player address");
            require(!isRegistered[player], "Player already registered");
            
            // Assign player number
            uint256 playerNumber = registeredPlayers.length;
            playerNumbers[player] = playerNumber;
            
            // Register player
            registeredPlayers.push(player);
            isRegistered[player] = true;
            
            // Add to active players
            activePlayers.push(player);
            isActivePlayer[player] = true;
            
            emit PlayerRegistered(player, playerNumber);
        }
        
        // Check if max players reached after batch registration
        if (registeredPlayers.length >= maxPlayers) {
            registrationClosed = true;
            emit RegistrationClosed();
        }
    }
    
    // =============================================================
    // ================== Game Management Functions ===============
    // =============================================================
    
    /**
     * @notice Register a new game type
     * @param gameName Name of the game
     * @param gameAddress Address of the game contract
     */
    function registerGame(string calldata gameName, address gameAddress) external onlyOwner {
        require(gameAddress != address(0), "Invalid game address");
        require(!isGameRegistered[gameName], "Game already registered");
        require(bytes(gameName).length > 0, "Game name cannot be empty");
        
        gameAddresses[gameName] = gameAddress;
        isGameRegistered[gameName] = true;
        registeredGames.push(gameName);
        
        emit GameRegistered(gameName, gameAddress);
    }
    
    /**
     * @notice Initialize a new game instance
     * @param gameName Name of the game to initialize
     * @return gameId ID of the created game
     */
    function initializeGame(string calldata gameName) external onlyOwner returns (uint256) {
        require(isGameRegistered[gameName], "Game not registered");
        require(activePlayers.length > 0, "No active players");
        
        address gameAddress = gameAddresses[gameName];
        IGame game = IGame(gameAddress);
        
        // Create array of player numbers in same order as activePlayers array
        uint256[] memory playerNumbersArray = new uint256[](activePlayers.length);
        for (uint256 i = 0; i < activePlayers.length; i++) {
            address player = activePlayers[i];
            playerNumbersArray[i] = playerNumbers[player];
        }
        
        // Initialize new game instance
        game.initialize(activePlayers, playerNumbersArray);
        
        emit GameStarted(gameName, gameAddress, 0);
        return 0;
    }
    
    /**
     * @notice Start games for a specific game type
     * @param gameName Name of the game
     * @return success Whether all games were started successfully
     */
    function startGames(string calldata gameName) external onlyOwner returns (bool) {
        require(isGameRegistered[gameName], "Game not registered");
        IGame game = IGame(gameAddresses[gameName]);
        return game.startGames();
    }
    
    /**
     * @notice End expired games for a specific game type
     * @param gameName Name of the game
     */
    function endExpiredGames(string calldata gameName) external onlyOwner {
        require(isGameRegistered[gameName], "Game not registered");
        IGame game = IGame(gameAddresses[gameName]);
        game.endExpiredGames();
    }
    
    /**
     * @notice End all games for a specific game type
     * @param gameName Name of the game
     * @return winners Array of winners
     */
    function endGames(string calldata gameName) external onlyOwner returns (address[] memory) {
        require(isGameRegistered[gameName], "Game not registered");
        IGame game = IGame(gameAddresses[gameName]);
        return game.endGame();
    }
    
    /**
     * @notice Handle player elimination (called by game contracts)
     * @param player Address of the eliminated player
     */
    function playerEliminated(address player) external {
        require(isRegistered[player], "Player not registered");
        require(isActivePlayer[player], "Player already eliminated");
        
        // Ensure only a registered game can call this function
        bool isValidCaller = false;
        for (uint i = 0; i < registeredGames.length; i++) {
            if (msg.sender == gameAddresses[registeredGames[i]]) {
                isValidCaller = true;
                break;
            }
        }
        require(isValidCaller, "Only registered games can eliminate players");
        
        // Remove player from active players
        isActivePlayer[player] = false;
        
        // Add player to eliminated players array and set final placement
        eliminatedPlayers.push(player);
        // Calculate placement: total players - current eliminated count = placement
        // This makes first eliminated = last place, last eliminated = first place
        uint256 totalPlayers = registeredPlayers.length;
        uint256 placement = totalPlayers - eliminatedPlayers.length + 1;
        finalPlacements[player] = placement;
        
        // Find and remove from activePlayers array
        for (uint i = 0; i < activePlayers.length; i++) {
            if (activePlayers[i] == player) {
                // Replace with the last element and pop
                activePlayers[i] = activePlayers[activePlayers.length - 1];
                activePlayers.pop();
                break;
            }
        }
        
        emit PlayerEliminated(player, playerNumbers[player]);
    }
    
    // =============================================================
    // ===================== View Functions =======================
    // =============================================================
    
    /**
     * @notice Get all registered players
     * @return Array of player addresses
     */
    function getRegisteredPlayers() external view returns (address[] memory) {
        return registeredPlayers;
    }
    
    /**
     * @notice Get all active players
     * @return Array of active player addresses
     */
    function getActivePlayers() external view returns (address[] memory) {
        return activePlayers;
    }
    
    /**
     * @notice Get total number of registered players
     * @return Number of registered players
     */
    function getPlayerCount() external view returns (uint256) {
        return registeredPlayers.length;
    }
    
    /**
     * @notice Get total number of active players
     * @return Number of active players
     */
    function getActivePlayerCount() external view returns (uint256) {
        return activePlayers.length;
    }
    
    /**
     * @notice Get all registered games
     * @return Array of game names
     */
    function getRegisteredGames() external view returns (string[] memory) {
        return registeredGames;
    }
    
    /**
     * @notice Get player information in a game
     * @param player Address of the player
     * @return gameName Name of the game the player is in
     * @return gameId ID of the game the player is in
     * @return isActive Whether the player is still active
     * @return gameState The current state of the game (0 = Pregame, 1 = Active, 2 = Waiting, 3 = Completed)
     * @return playerNumber The player's assigned number
     */
    function getPlayerInfo(address player) external view returns (
        string memory gameName,
        uint256 gameId,
        bool isActive,
        GameState gameState,
        uint256 playerNumber
    ) {
        if (!isRegistered[player]) {
            return ("", 0, false, GameState.NotInitialized, 0);
        }
        
        // Get player's active status and number
        isActive = isActivePlayer[player];
        playerNumber = playerNumbers[player];

        // Store most recent match
        string memory latestGameName = "";
        uint256 latestGameId = 0;
        GameState latestGameState = GameState.NotInitialized;
        uint256 mostRecentStartTime = 0;
        
        // Get all registered games
        for (uint256 i = 0; i < registeredGames.length; i++) {
            string memory currentGameName = registeredGames[i];
            address gameAddress = gameAddresses[currentGameName];
            
            if (gameAddress != address(0)) {
                IGame game = IGame(gameAddress);
                uint256 playerGameId = game.getPlayerGameId(player);
                
                if (playerGameId != 0) {
                    // Get game info to check start time
                    IGame.GameInfo memory info = game.getGameInfo(playerGameId);
                    
                    // Update latest match if this game started more recently
                    if (info.gameStartTime > mostRecentStartTime) {
                        mostRecentStartTime = info.gameStartTime;
                        latestGameName = currentGameName;
                        latestGameId = playerGameId;
                        latestGameState = info.state;
                    }
                }
            }
        }
        
        return (latestGameName, latestGameId, isActive, latestGameState, playerNumber);
    }
    
    /**
     * @notice Get player number
     * @param player Address of the player
     * @return Player number
     */
    function getPlayerNumber(address player) external view returns (uint256) {
        require(isRegistered[player], "Player not registered");
        return playerNumbers[player];
    }
    
    /**
     * @notice Get all active players and their player numbers
     * @return players Array of active player addresses
     * @return numbers Array of corresponding player numbers
     */
    function getActivePlayersAndNumbers() external view returns (
        address[] memory players,
        uint256[] memory numbers
    ) {
        uint256 count = activePlayers.length;
        numbers = new uint256[](count);
        
        // Return copy of activePlayers array and build numbers array
        players = activePlayers;
        for (uint256 i = 0; i < count; i++) {
            numbers[i] = playerNumbers[players[i]];
        }
        
        return (players, numbers);
    }
    
    /**
     * @notice Get all eliminated players in order of elimination
     * @return Array of eliminated player addresses
     */
    function getEliminatedPlayers() external view returns (address[] memory) {
        return eliminatedPlayers;
    }

    /**
     * @notice Get total number of eliminated players
     * @return Number of eliminated players
     */
    function getEliminatedPlayerCount() external view returns (uint256) {
        return eliminatedPlayers.length;
    }

    /**
     * @notice Get a player's final placement in the game (0 if still active)
     * @param player Address of the player
     * @return Final placement (totalPlayers = first eliminated, 1 = winner, 0 = still active)
     */
    function getPlayerFinalPlacement(address player) external view returns (uint256) {
        require(isRegistered[player], "Player not registered");
        return finalPlacements[player];
    }

    /**
     * @notice Get information about all game instances across all registered games
     * @return gameTypes Array of game type names
     * @return gameInstances Array of arrays containing game instances for each game type
     */
    function getGames() external view returns (
        string[] memory gameTypes,
        GameInstanceInfo[][] memory gameInstances
    ) {
        uint256 numGames = registeredGames.length;
        gameTypes = registeredGames;
        gameInstances = new GameInstanceInfo[][](numGames);
        
        // Get game instances for each registered game
        for (uint256 i = 0; i < numGames; i++) {
            string memory gameName = registeredGames[i];
            address gameAddress = gameAddresses[gameName];
            
            if (gameAddress != address(0)) {
                IGame game = IGame(gameAddress);
                gameInstances[i] = game.getGames();
            }
        }
        
        return (gameTypes, gameInstances);
    }

    /**
     * @notice Toggle registration status (open/closed)
     */
    function toggleRegistration() external onlyOwner {
        registrationClosed = !registrationClosed;
        if (registrationClosed) {
            emit RegistrationClosed();
        }
    }

    /**
     * @notice Set the maximum number of players allowed
     * @param _maxPlayers New maximum number of players
     */
    function setMaxPlayers(uint256 _maxPlayers) external onlyOwner {
        require(_maxPlayers > 0, "Max players must be greater than 0");
        require(_maxPlayers >= registeredPlayers.length, "Cannot set max players below current player count");
        maxPlayers = _maxPlayers;
    }

    /// @dev Register my contract on Sonic FeeM
    function registerMe() external {
        (bool _success,) = address(0xDC2B0D2Dd2b7759D97D50db4eabDC36973110830).call(
            abi.encodeWithSignature("selfRegister(uint256)", 151)
        );
        require(_success, "FeeM registration failed");
    }
} 