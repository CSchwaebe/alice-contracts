// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGame.sol";

// Interface for RagnarokGameMaster's elimination function
interface IRagnarokGameMaster {
    function playerEliminated(address player) external;
}

contract Bidding is IGame, Ownable {
    // ============ Constants ============
    uint256 private constant INITIAL_POINTS = 1000;
    uint256 private constant COMMIT_DURATION = 2 minutes;
    uint256 private constant REVEAL_DURATION = 1 minutes;
    uint256 private constant MAX_ROUNDS = 20;
    uint256 private constant COMMIT_PHASE = 1;
    uint256 private constant REVEAL_PHASE = 2;
    uint256 private constant MAX_PLAYERS_PER_INSTANCE = 20;

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
        uint256 currentPhase;      // 1 = commit phase, 2 = reveal phase
        uint256 roundEndTime;      // When the current phase ends
        uint256 gameStartTime;     // When the game was initialized
        uint256 gameEndTime;       // When the game was completed
        address[] players;
        mapping(address => bool) isPlayer;
        mapping(address => uint256) playerNumbers;
        address[] activePlayers;
        mapping(address => bool) isActivePlayer;
        mapping(address => uint256) playerPoints;  // Track points for each player
        // Commit-reveal data
        mapping(address => bytes32) commitments;
        mapping(address => uint256) reveals;       // Revealed bids
        mapping(address => bool) hasCommitted;
        mapping(address => bool) hasRevealed;
        uint256 commitCount;
        uint256 revealCount;
        uint256 currentRound;       // Track which round we're on (1-10)
    }

    struct BiddingPlayerInfo {
        address playerAddress;
        uint256 playerNumber;
        uint256 points;
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
    event PlayerRevealed(uint256 indexed gameId, address indexed player, uint256 bid);
    event PlayerEliminated(uint256 indexed gameId, address indexed player, uint256 playerNumber);
    event GameCompleted(uint256 indexed gameId, address[] winners);
    event RoundStarted(uint256 indexed gameId, uint256 roundNumber, uint256 phase, uint256 endTime);
    event PointsDeducted(uint256 indexed gameId, address indexed player, uint256 bid, uint256 remainingPoints);

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
        require(_players.length >= 2, "Need at least 2 players");

        // Calculate optimal distribution
        uint256 totalPlayers = _players.length;
        uint256 numInstances = (totalPlayers + MAX_PLAYERS_PER_INSTANCE - 1) / MAX_PLAYERS_PER_INSTANCE;
        uint256 playersPerInstance = totalPlayers / numInstances;
        uint256 extraPlayers = totalPlayers % numInstances;

        uint256 playerIndex = 0;

        // Create game instances
        for (uint256 i = 0; i < numInstances; i++) {
            uint256 gameId = ++gameIdCounter;
            GameInstance storage game = games[gameId];
            game.state = GameState.Pregame;
            game.currentRound = 1;
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
                game.playerPoints[player] = INITIAL_POINTS;  // Initialize points

                // Track player's game
                playerGameId[player] = gameId;
                isPlayerInGame[player] = true;
                playerIndex++;
            }

            emit GameInitialized(game.players, _playerNumbers);
        }
    }

    function startGames() external override onlyGameMaster returns (bool) {
        bool allStarted = true;
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage game = games[i];
            if (game.state == GameState.Pregame && game.activePlayers.length > 0) {
                game.state = GameState.Active;
                game.currentPhase = COMMIT_PHASE;
                game.roundEndTime = block.timestamp + COMMIT_DURATION;
                emit RoundStarted(i, game.currentRound, COMMIT_PHASE, game.roundEndTime);
            } else {
                allStarted = false;
            }
        }
        return allStarted;
    }

    function commitBid(bytes32 commitment) external {
        require(isPlayerInGame[msg.sender], "Player not in any game");
        uint256 gameId = playerGameId[msg.sender];
        GameInstance storage game = games[gameId];
        
        require(game.state == GameState.Active, "Game not active");
        require(game.currentPhase == COMMIT_PHASE, "Not in commit stage");
        require(block.timestamp <= game.roundEndTime, "Commit period ended");
        require(!game.hasCommitted[msg.sender], "Already committed");
        
        game.commitments[msg.sender] = commitment;
        game.hasCommitted[msg.sender] = true;
        game.commitCount++;
        
        emit PlayerCommitted(gameId, msg.sender);

        // If all active players have committed, move to reveal stage
        if (game.commitCount == game.activePlayers.length) {
            game.currentPhase = REVEAL_PHASE;
            game.roundEndTime = block.timestamp + REVEAL_DURATION;
            emit RoundStarted(gameId, game.currentRound, REVEAL_PHASE, game.roundEndTime);
        }
    }

    function revealBid(uint256 bid, bytes32 salt) external {
        require(isPlayerInGame[msg.sender], "Player not in any game");
        uint256 gameId = playerGameId[msg.sender];
        GameInstance storage game = games[gameId];
        
        require(game.state == GameState.Active, "Game not active");
        require(game.hasCommitted[msg.sender], "Must commit first");
        require(!game.hasRevealed[msg.sender], "Already revealed");
        require(bid <= game.playerPoints[msg.sender], "Bid exceeds available points");

        // If commit stage has expired and we haven't moved to reveal stage yet
        if (game.currentPhase == COMMIT_PHASE && block.timestamp > game.roundEndTime) {
            _handleCommitStageEnd(gameId);
            if (game.state == GameState.Completed) {
                return;
            }
        }

        require(game.currentPhase == REVEAL_PHASE, "Not in reveal stage");
        require(block.timestamp <= game.roundEndTime, "Reveal period ended");
        
        // Verify commitment
        bytes32 commitment = keccak256(abi.encodePacked(bid, salt, msg.sender));
        require(commitment == game.commitments[msg.sender], "Invalid reveal");
        
        game.reveals[msg.sender] = bid;
        game.hasRevealed[msg.sender] = true;
        game.revealCount++;
        
        emit PlayerRevealed(gameId, msg.sender, bid);

        // If all active players have revealed or reveal period has ended
        if (game.revealCount == game.activePlayers.length || block.timestamp > game.roundEndTime) {
            _resolveRound(gameId);
        }
    }

    function endExpiredGames() external override {
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage game = games[i];
            if (game.state == GameState.Active) {
                if (game.currentPhase == COMMIT_PHASE && block.timestamp > game.roundEndTime) {
                    _handleCommitStageEnd(i);
                } else if (game.currentPhase == REVEAL_PHASE && block.timestamp > game.roundEndTime) {
                    _resolveRound(i);
                }
            }
        }
    }

    function endGame() external override onlyGameMaster returns (address[] memory) {
        address[] memory winners = new address[](0);
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage game = games[i];
            if (game.state == GameState.Active) {
                _resolveRound(i);
            }
        }
        return winners;
    }

    // ============ Internal Functions ============
    function _handleCommitStageEnd(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        require(game.currentPhase == COMMIT_PHASE, "Not in commit stage");
        require(block.timestamp > game.roundEndTime || game.commitCount == game.activePlayers.length, 
                "Cannot end commit stage yet");

        // If all players committed, move to reveal stage
        if (game.commitCount == game.activePlayers.length) {
            game.currentPhase = REVEAL_PHASE;
            game.roundEndTime = block.timestamp + REVEAL_DURATION;
            emit RoundStarted(gameId, game.currentRound, REVEAL_PHASE, game.roundEndTime);
            return;
        }

        // Eliminate players who didn't commit
        address[] memory playersToEliminate = new address[](game.activePlayers.length);
        uint256 eliminationCount = 0;

        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            if (!game.hasCommitted[game.activePlayers[i]]) {
                playersToEliminate[eliminationCount++] = game.activePlayers[i];
            }
        }

        for (uint256 i = 0; i < eliminationCount; i++) {
            _eliminatePlayer(gameId, playersToEliminate[i]);
        }

        // If not enough players remain, end the game
        if (game.activePlayers.length < 2) {
            game.state = GameState.Completed;
            game.gameEndTime = block.timestamp;  // Set end time when game completes
            emit GameCompleted(gameId, game.activePlayers);
        } else {
            // Otherwise, move to reveal stage
            game.currentPhase = REVEAL_PHASE;
            game.roundEndTime = block.timestamp + REVEAL_DURATION;
            emit RoundStarted(gameId, game.currentRound, REVEAL_PHASE, game.roundEndTime);
        }
    }

    // Internal function to get players who haven't revealed their bids
    function _getUnrevealedPlayers(uint256 gameId) internal view returns (address[] memory, uint256) {
        GameInstance storage game = games[gameId];
        address[] memory playersToEliminate = new address[](game.activePlayers.length);
        uint256 eliminationCount = 0;
        
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            address player = game.activePlayers[i];
            if (!game.hasRevealed[player]) {
                playersToEliminate[eliminationCount++] = player;
            }
        }
        
        return (playersToEliminate, eliminationCount);
    }

    // Internal function to deduct points and find lowest bid
    function _deductPointsAndFindLowestBid(uint256 gameId) internal returns (uint256) {
        GameInstance storage game = games[gameId];
        uint256 lowestBid = type(uint256).max;
        
        // Create array to track players to eliminate
        address[] memory insufficientPointsPlayers = new address[](game.activePlayers.length);
        uint256 eliminationCount = 0;

        // First pass: check points and track eliminations
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            address player = game.activePlayers[i];
            if (game.hasRevealed[player]) {
                uint256 bid = game.reveals[player];
                uint256 currentPoints = game.playerPoints[player];
                
                // Check if player has enough points
                if (bid > currentPoints) {
                    insufficientPointsPlayers[eliminationCount++] = player;
                } else {
                    // Only track valid bids for lowest bid calculation
                    if (bid < lowestBid) {
                        lowestBid = bid;
                    }
                    // Deduct points for valid bids
                    game.playerPoints[player] -= bid;
                    emit PointsDeducted(gameId, player, bid, game.playerPoints[player]);
                }
            }
        }

        // Eliminate players with insufficient points
        for (uint256 i = 0; i < eliminationCount; i++) {
            _eliminatePlayer(gameId, insufficientPointsPlayers[i]);
        }
        
        return lowestBid;
    }

    // Internal function to get players who tied for lowest bid
    function _getPlayersWithLowestBid(uint256 gameId, uint256 lowestBid) internal view returns (address[] memory, uint256) {
        GameInstance storage game = games[gameId];
        address[] memory playersToEliminate = new address[](game.activePlayers.length);
        uint256 eliminationCount = 0;
        
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            address player = game.activePlayers[i];
            if (game.hasRevealed[player] && game.reveals[player] == lowestBid) {
                playersToEliminate[eliminationCount++] = player;
            }
        }
        
        return (playersToEliminate, eliminationCount);
    }

    // Internal function to check if game should end
    function _shouldEndGame(uint256 gameId) internal view returns (bool) {
        GameInstance storage game = games[gameId];
        return game.activePlayers.length < 2 || game.currentRound >= MAX_ROUNDS;
    }

    // Internal function to end the game
    function _endGame(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        game.state = GameState.Completed;
        game.gameEndTime = block.timestamp;
        emit GameCompleted(gameId, game.activePlayers);
    }

    // Internal function to start the next round
    function _startNextRound(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        game.currentRound++;
        game.currentPhase = COMMIT_PHASE;
        game.roundEndTime = block.timestamp + COMMIT_DURATION;
        
        // Reset round-specific counters
        game.commitCount = 0;
        game.revealCount = 0;
        
        // Reset all player-specific round state
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            address player = game.activePlayers[i];
            game.hasCommitted[player] = false;
            game.hasRevealed[player] = false;
            game.commitments[player] = bytes32(0);
            game.reveals[player] = 0;
        }
        
        emit RoundStarted(gameId, game.currentRound, COMMIT_PHASE, game.roundEndTime);
    }

    function _resolveRound(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        
        // Get and eliminate players who didn't reveal
        (address[] memory unrevealedPlayers, uint256 unrevealedCount) = _getUnrevealedPlayers(gameId);
        for (uint256 i = 0; i < unrevealedCount; i++) {
            _eliminatePlayer(gameId, unrevealedPlayers[i]);
        }

        // If we have active players who revealed, handle bids
        if (game.activePlayers.length > 0) {
            // Deduct points and find lowest bid
            uint256 lowestBid = _deductPointsAndFindLowestBid(gameId);
            
            // Get and eliminate players with lowest bid
            (address[] memory lowestBidders, uint256 lowestBiddersCount) = _getPlayersWithLowestBid(gameId, lowestBid);
            for (uint256 i = 0; i < lowestBiddersCount; i++) {
                _eliminatePlayer(gameId, lowestBidders[i]);
            }
        }

        // Either end game or start next round
        if (_shouldEndGame(gameId)) {
            _endGame(gameId);
        } else {
            _startNextRound(gameId);
        }
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
        return "Bidding";
    }

    function getGameInfo(uint256 gameId) external view override isValidGameId(gameId) returns (GameInfo memory) {
        GameInstance storage game = games[gameId];
        return GameInfo({
            state: game.state,
            currentRound: game.currentRound,  // Keep this as currentRound for IGame interface compatibility
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
                currentRound: game.currentPhase,  // Keep this as currentRound for IGame interface compatibility
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

    // Additional view functions specific to Bidding
    function getCurrentPhase(uint256 gameId) external view isValidGameId(gameId) returns (uint256) {
        return games[gameId].currentPhase;
    }

    function getRoundEndTime(uint256 gameId) external view isValidGameId(gameId) returns (uint256) {
        return games[gameId].roundEndTime;
    }

    function getPlayerPoints(uint256 gameId, address player) external view isValidGameId(gameId) returns (uint256) {
        require(games[gameId].isPlayer[player], "Player not in game");
        return games[gameId].playerPoints[player];
    }

    function hasPlayerCommitted(uint256 gameId, address player) external view isValidGameId(gameId) returns (bool) {
        return games[gameId].hasCommitted[player];
    }

    function hasPlayerRevealed(uint256 gameId, address player) external view isValidGameId(gameId) returns (bool) {
        return games[gameId].hasRevealed[player];
    }

    function getPlayerInfo(uint256 gameId) external view isValidGameId(gameId) returns (BiddingPlayerInfo[] memory) {
        GameInstance storage game = games[gameId];
        BiddingPlayerInfo[] memory playersInfo = new BiddingPlayerInfo[](game.players.length);

        for (uint256 i = 0; i < game.players.length; i++) {
            address playerAddress = game.players[i];
            playersInfo[i] = BiddingPlayerInfo({
                playerAddress: playerAddress,
                playerNumber: game.playerNumbers[playerAddress],
                points: game.playerPoints[playerAddress],
                hasCommitted: game.hasCommitted[playerAddress],
                hasRevealed: game.hasRevealed[playerAddress],
                isActive: game.isActivePlayer[playerAddress]
            });
        }

        return playersInfo;
    }

    /// @dev Register my contract on Sonic FeeM
    function registerMe() external {
        (bool _success,) = address(0xDC2B0D2Dd2b7759D97D50db4eabDC36973110830).call(
            abi.encodeWithSignature("selfRegister(uint256)", 151)
        );
        require(_success, "FeeM registration failed");
    }
} 