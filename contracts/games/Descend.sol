// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGame.sol";

// Interface for RagnarokGameMaster's elimination function
interface IRagnarokGameMaster {
    function playerEliminated(address player) external;
}

contract Descend is IGame, Ownable {
    // ============ Constants ============
    uint256 private constant COMMIT_DURATION = 2 minutes;
    uint256 private constant REVEAL_DURATION = 1 minutes;
    uint256 private constant MAX_PLAYERS_PER_INSTANCE = 59;
    uint256 private constant MAX_LEVEL = 21;
    uint256 private constant COMMIT_PHASE = 1;
    uint256 private constant REVEAL_PHASE = 2;
    uint256 private constant MAX_MOVE = 5;
    uint256 private constant MAX_ROUNDS = 20;  // Maximum rounds as safety measure

    // ============ Structs ============
    struct GameInstance {
        GameState state;
        uint256 currentPhase;      // 1 = commit phase, 2 = reveal phase
        uint256 roundEndTime;      // When the current phase ends
        uint256 gameStartTime;     // When the game was initialized
        uint256 gameEndTime;       // When the game was completed
        uint256 currentRound;      // Track round number
        uint256 levelCapacity;     // Capacity for levels 1-20 (n/10)
        uint256 finalCapacity;     // Capacity for level 21 (n/2)
        address[] players;
        mapping(address => bool) isPlayer;
        mapping(address => uint256) playerNumbers;
        address[] activePlayers;
        mapping(address => bool) isActivePlayer;
        mapping(address => uint256) playerLevels;  // Current level of each player
        mapping(address => uint256) lastMove;      // Store last move to prevent repeats
        // Commit-reveal data
        mapping(address => bytes32) commitments;
        mapping(address => uint256) reveals;       // Revealed moves
        mapping(address => bool) hasCommitted;
        mapping(address => bool) hasRevealed;
        // Level tracking
        mapping(uint256 => uint256) levelPopulation;  // Track players at each level
        mapping(uint256 => address[]) playersAtLevel; // Track which players are at each level
        // Non-MAX_LEVEL player tracking
        uint256 nonMaxLevelPlayerCount;
        uint256 nonMaxLevelCommitCount;
        uint256 nonMaxLevelRevealCount;
        // Winners tracking
        address[] winners;  // Players who have reached level 21
    }

    struct DescendPlayerInfo {
        address playerAddress;
        uint256 playerNumber;
        uint256 level;
        uint256 lastMove;
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
    event PlayerRevealed(uint256 indexed gameId, address indexed player, uint256 move);
    event PlayerEliminated(uint256 indexed gameId, address indexed player, uint256 playerNumber);
    event GameCompleted(uint256 indexed gameId, address[] winners);
    event RoundStarted(
        uint256 indexed gameId, 
        uint256 roundNumber, 
        uint256 phase, 
        uint256 endTime,
        uint256[] levelPopulations,
        uint256[] levelCapacities
    );
    event PlayerMoved(uint256 indexed gameId, address indexed player, uint256 fromLevel, uint256 toLevel);
    event LevelElimination(uint256 indexed gameId, uint256 level, uint256 playerCount);
    event RoundEnded(uint256 indexed gameId, uint256 roundNumber);

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
        uint256 maxPlayersPerInstance = MAX_PLAYERS_PER_INSTANCE;  // Maximum players per instance
        uint256 numInstances = (totalPlayers + maxPlayersPerInstance - 1) / maxPlayersPerInstance;
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

            // Set level capacities based on instance player count
            game.levelCapacity = instancePlayers / 10;  // Levels 1-20 capacity
            if (game.levelCapacity == 0) game.levelCapacity = 1;  // Minimum capacity of 1
            game.finalCapacity = instancePlayers / 2;   // Level 21 capacity
            if (game.finalCapacity == 0) game.finalCapacity = 1;  // Minimum capacity of 1

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
                game.playerLevels[player] = 0;  // Start at level 0
                game.lastMove[player] = MAX_MOVE + 1;  // Initialize to invalid move

                // Add player to level 0 tracking
                game.levelPopulation[0]++;
                game.playersAtLevel[0].push(player);

                // Track player's game
                playerGameId[player] = gameId;
                isPlayerInGame[player] = true;
                playerIndex++;
            }

            // Initialize non-MAX_LEVEL counts
            _updateNonMaxLevelCounts(game);

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
                
                // Create arrays for populations and capacities
                uint256[] memory populations = new uint256[](MAX_LEVEL + 1);
                uint256[] memory capacities = new uint256[](MAX_LEVEL + 1);
                
                // Fill populations array
                for (uint256 level = 0; level <= MAX_LEVEL; level++) {
                    populations[level] = game.levelPopulation[level];
                    if (level == 0) {
                        capacities[level] = game.players.length;  // Level 0 capacity is total players
                    } else if (level == MAX_LEVEL) {
                        capacities[level] = game.finalCapacity;   // Level 21 capacity
                    } else {
                        capacities[level] = game.levelCapacity;   // Levels 1-20 capacity
                    }
                }
                
                emit RoundStarted(i, game.currentRound, COMMIT_PHASE, game.roundEndTime, populations, capacities);
            } else {
                allStarted = false;
            }
        }
        return allStarted;
    }

    // ============ Internal Helper Functions ============
    function _checkAllNonMaxLevelPlayersCommitted(GameInstance storage game) internal view returns (bool) {
        return game.nonMaxLevelCommitCount == game.nonMaxLevelPlayerCount;
    }

    function _checkAllNonMaxLevelPlayersRevealed(GameInstance storage game) internal view returns (bool) {
        return game.nonMaxLevelRevealCount == game.nonMaxLevelPlayerCount;
    }

    function _updateNonMaxLevelCounts(GameInstance storage game) internal {
        uint256 count = 0;
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            if (game.playerLevels[game.activePlayers[i]] < MAX_LEVEL) {
                count++;
            }
        }
        game.nonMaxLevelPlayerCount = count;
    }

    function _moveToRevealPhase(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        game.currentPhase = REVEAL_PHASE;
        game.roundEndTime = block.timestamp + REVEAL_DURATION;
        
        // Create arrays for populations and capacities
        uint256[] memory populations = new uint256[](MAX_LEVEL + 1);
        uint256[] memory capacities = new uint256[](MAX_LEVEL + 1);
        
        // Fill populations array
        for (uint256 level = 0; level <= MAX_LEVEL; level++) {
            populations[level] = game.levelPopulation[level];
            if (level == 0) {
                capacities[level] = game.players.length;  // Level 0 capacity is total players
            } else if (level == MAX_LEVEL) {
                capacities[level] = game.finalCapacity;   // Level 21 capacity
            } else {
                capacities[level] = game.levelCapacity;   // Levels 1-20 capacity
            }
        }
        
        emit RoundStarted(gameId, game.currentRound, REVEAL_PHASE, game.roundEndTime, populations, capacities);
    }

    function _eliminateNonCommittedPlayers(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        
        // Find players to eliminate
        address[] memory playersToEliminate = new address[](game.activePlayers.length);
        uint256 eliminationCount = 0;

        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            address player = game.activePlayers[i];
            if (!game.hasCommitted[player] && game.playerLevels[player] < MAX_LEVEL) {
                playersToEliminate[eliminationCount++] = player;
            }
        }

        // Eliminate players
        for (uint256 i = 0; i < eliminationCount; i++) {
            _eliminatePlayer(gameId, playersToEliminate[i]);
        }

        // Update non-MAX_LEVEL counts
        _updateNonMaxLevelCounts(game);

        // Check if game should end
        if (game.activePlayers.length < 2) {
            game.state = GameState.Completed;
            game.gameEndTime = block.timestamp;  // Set end time when game completes
            emit GameCompleted(gameId, game.winners.length > 0 ? game.winners : game.activePlayers);
        }
    }

    function _eliminateNonRevealedPlayers(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        
        // Find players to eliminate
        address[] memory playersToEliminate = new address[](game.activePlayers.length);
        uint256 eliminationCount = 0;

        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            address player = game.activePlayers[i];
            if (!game.hasRevealed[player] && game.playerLevels[player] < MAX_LEVEL) {
                playersToEliminate[eliminationCount++] = player;
            }
        }

        // Eliminate players
        for (uint256 i = 0; i < eliminationCount; i++) {
            _eliminatePlayer(gameId, playersToEliminate[i]);
        }

        // Update non-MAX_LEVEL counts
        _updateNonMaxLevelCounts(game);

        // Check if game should end
        if (game.activePlayers.length < 2) {
            game.state = GameState.Completed;
            emit GameCompleted(gameId, game.winners.length > 0 ? game.winners : game.activePlayers);
        }
    }

    // ============ Game Functions ============
    function commitMove(bytes32 commitment) external {
        require(isPlayerInGame[msg.sender], "Player not in any game");
        uint256 gameId = playerGameId[msg.sender];
        GameInstance storage game = games[gameId];
        
        require(game.state == GameState.Active, "Game not active");
        
        // Players at MAX_LEVEL don't need to participate
        if (game.playerLevels[msg.sender] == MAX_LEVEL) {
            return;
        }
        
        require(game.currentPhase == COMMIT_PHASE, "Not in commit phase");
        require(!game.hasCommitted[msg.sender], "Already committed");
        
        // Check if commit period has ended first
        if (block.timestamp > game.roundEndTime) {
            _eliminateNonCommittedPlayers(gameId);
            // Game might be completed after eliminations
            if (game.state != GameState.Completed) {
                _moveToRevealPhase(gameId);
            }
            return;
        }
        
        // Record the commitment
        game.commitments[msg.sender] = commitment;
        game.hasCommitted[msg.sender] = true;
        if (game.playerLevels[msg.sender] < MAX_LEVEL) {
            game.nonMaxLevelCommitCount++;
        }
        
        emit PlayerCommitted(gameId, msg.sender);

        // Check if all non-MAX_LEVEL players have committed
        if (_checkAllNonMaxLevelPlayersCommitted(game)) {
            _moveToRevealPhase(gameId);
        }
    }

    function revealMove(uint256 move, bytes32 salt) external {
        require(isPlayerInGame[msg.sender], "Player not in any game");
        uint256 gameId = playerGameId[msg.sender];
        GameInstance storage game = games[gameId];
        
        require(game.state == GameState.Active, "Game not active");
        
        // Players at MAX_LEVEL don't need to participate
        if (game.playerLevels[msg.sender] == MAX_LEVEL) {
            return;
        }
        
        require(game.hasCommitted[msg.sender], "Must commit first");
        require(!game.hasRevealed[msg.sender], "Already revealed");
        require(move <= MAX_MOVE, "Invalid move");

        // If commit phase has expired and we haven't moved to reveal phase yet
        if (game.currentPhase == COMMIT_PHASE && block.timestamp > game.roundEndTime) {
            _handleCommitPhaseEnd(gameId);
            if (game.state == GameState.Completed) {
                return;
            }
        }

        require(game.currentPhase == REVEAL_PHASE, "Not in reveal phase");
        require(block.timestamp <= game.roundEndTime, "Reveal period ended");
        
        // Verify commitment
        bytes32 commitment = keccak256(abi.encodePacked(move, salt, msg.sender));
        require(commitment == game.commitments[msg.sender], "Invalid reveal");
        
        // Mark as revealed and update counters first
        game.reveals[msg.sender] = move;
        game.hasRevealed[msg.sender] = true;
        if (game.playerLevels[msg.sender] < MAX_LEVEL) {
            game.nonMaxLevelRevealCount++;
        }
        
        // Then check for repeated move and eliminate if needed
        if (move == game.lastMove[msg.sender]) {
            _eliminatePlayer(gameId, msg.sender);
            return;
        }
        
        emit PlayerRevealed(gameId, msg.sender, move);

        // If all non-MAX_LEVEL players have revealed or reveal period has ended
        if (_checkAllNonMaxLevelPlayersRevealed(game) || block.timestamp > game.roundEndTime) {
            if (block.timestamp > game.roundEndTime) {
                _eliminateNonRevealedPlayers(gameId);
            } else {
                _resolveRound(gameId);
            }
        }
    }

    function endExpiredGames() external override {
        for (uint256 i = 1; i <= gameIdCounter; i++) {
            GameInstance storage game = games[i];
            if (game.state == GameState.Active) {
                if (game.currentPhase == COMMIT_PHASE && block.timestamp > game.roundEndTime) {
                    _handleCommitPhaseEnd(i);
                } else if (game.currentPhase == REVEAL_PHASE && block.timestamp > game.roundEndTime) {
                    _eliminateNonRevealedPlayers(i);
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
    function _handleCommitPhaseEnd(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        require(game.currentPhase == COMMIT_PHASE, "Not in commit phase");
        require(block.timestamp > game.roundEndTime || _checkAllNonMaxLevelPlayersCommitted(game), 
                "Cannot end commit phase yet");

        // If all non-MAX_LEVEL players committed, move to reveal phase
        if (_checkAllNonMaxLevelPlayersCommitted(game)) {
            _moveToRevealPhase(gameId);
            return;
        }

        // Eliminate players who didn't commit
        _eliminateNonCommittedPlayers(gameId);
    }

    // Helper function to check if game should end
    function _shouldEndGame(GameInstance storage game) internal view returns (bool) {
        // Game ends if:
        // 1. Level 21 is at/over capacity
        // 2. All remaining players are on level 21
        // 3. Less than 2 players remain
        // 4. Max rounds reached
        if (game.activePlayers.length < 2 || game.currentRound >= MAX_ROUNDS) {
            return true;
        }
        
        if (game.levelPopulation[MAX_LEVEL] >= game.finalCapacity) {
            return true;
        }

        // Check if all remaining players are on level 21
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            if (game.playerLevels[game.activePlayers[i]] != MAX_LEVEL) {
                return false;
            }
        }
        return true;
    }

    // Helper function to reset round state
    function _resetRoundState(GameInstance storage game) internal {
        // Reset all players' round state
        for (uint256 i = 0; i < game.players.length; i++) {
            address player = game.players[i];
            if (game.hasCommitted[player] || game.hasRevealed[player]) {
                game.hasCommitted[player] = false;
                game.hasRevealed[player] = false;
                delete game.commitments[player];
                delete game.reveals[player];
            }
        }
        
        // Reset and recalculate non-MAX_LEVEL counters
        game.nonMaxLevelCommitCount = 0;
        game.nonMaxLevelRevealCount = 0;
        _updateNonMaxLevelCounts(game);
    }

    // Helper function to start next round
    function _startNextRound(uint256 gameId, GameInstance storage game) internal {
        game.currentRound++;
        game.state = GameState.Active;
        game.currentPhase = COMMIT_PHASE;
        game.roundEndTime = block.timestamp + COMMIT_DURATION;
        
        // Create arrays for populations and capacities
        uint256[] memory populations = new uint256[](MAX_LEVEL + 1);
        uint256[] memory capacities = new uint256[](MAX_LEVEL + 1);
        
        // Fill populations array
        for (uint256 level = 0; level <= MAX_LEVEL; level++) {
            populations[level] = game.levelPopulation[level];
            capacities[level] = level == MAX_LEVEL ? game.finalCapacity : 
                               level == 0 ? game.players.length : game.levelCapacity;
        }
        
        emit RoundStarted(gameId, game.currentRound, COMMIT_PHASE, game.roundEndTime, populations, capacities);
    }

    function _resolveRound(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        
        // First handle any non-revealed players
        bool hasNonRevealed = false;
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            address player = game.activePlayers[i];
            if (!game.hasRevealed[player] && game.playerLevels[player] < MAX_LEVEL) {
                hasNonRevealed = true;
                break;
            }
        }

        if (hasNonRevealed) {
            _eliminateNonRevealedPlayers(gameId);
            if (game.state == GameState.Completed) {
                game.gameEndTime = block.timestamp;  // Set end time when game completes
                return;
            }
        }

        // Process moves for all revealing players
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            address player = game.activePlayers[i];
            if (game.hasRevealed[player]) {
                uint256 move = game.reveals[player];
                uint256 oldLevel = game.playerLevels[player];
                uint256 newLevel = oldLevel + move;
                if (newLevel > MAX_LEVEL) newLevel = MAX_LEVEL;

                // Remove from old level
                _removePlayerFromLevel(game, player, oldLevel);

                // Add to new level
                game.playerLevels[player] = newLevel;
                game.levelPopulation[newLevel]++;
                game.playersAtLevel[newLevel].push(player);
                game.lastMove[player] = move;  // Store the move

                // If player reached level 21, add to winners if not already there
                if (newLevel == MAX_LEVEL && !_isWinner(game, player)) {
                    game.winners.push(player);
                }

                emit PlayerMoved(gameId, player, oldLevel, newLevel);
            }
        }

        // Validate level populations
        for (uint256 level = 0; level <= MAX_LEVEL; level++) {
            require(game.levelPopulation[level] == game.playersAtLevel[level].length, 
                    "Level population mismatch");
        }

        // Check for overcrowded levels and eliminate players
        for (uint256 level = 1; level <= MAX_LEVEL; level++) {
            uint256 population = game.levelPopulation[level];
            uint256 capacity = level == MAX_LEVEL ? game.finalCapacity : game.levelCapacity;

            if (population > capacity && level < MAX_LEVEL) {
                // Eliminate all players at this level
                address[] memory levelPlayers = game.playersAtLevel[level];
                for (uint256 i = 0; i < levelPlayers.length; i++) {
                    if (game.isActivePlayer[levelPlayers[i]]) {
                        _eliminatePlayer(gameId, levelPlayers[i]);
                    }
                }
                emit LevelElimination(gameId, level, population);
            }
        }

        emit RoundEnded(gameId, game.currentRound);

        // Reset round state
        _resetRoundState(game);

        // Check if game should end
        if (_shouldEndGame(game)) {
            // If ending due to level 21 capacity, eliminate all non-level-21 players first
            if (game.levelPopulation[MAX_LEVEL] >= game.finalCapacity) {
                // Create array to store players to eliminate to avoid modifying array during iteration
                address[] memory playersToEliminate = new address[](game.activePlayers.length);
                uint256 eliminateCount = 0;
                
                // Find all players not at level 21
                for (uint256 i = 0; i < game.activePlayers.length; i++) {
                    address player = game.activePlayers[i];
                    if (game.playerLevels[player] < MAX_LEVEL) {
                        playersToEliminate[eliminateCount++] = player;
                    }
                }
                
                // Eliminate those players
                for (uint256 i = 0; i < eliminateCount; i++) {
                    _eliminatePlayer(gameId, playersToEliminate[i]);
                }
            }
            
            game.state = GameState.Completed;
            game.gameEndTime = block.timestamp;  // Set end time when game completes
            emit GameCompleted(gameId, game.winners.length > 0 ? game.winners : game.activePlayers);
        } else {
            _startNextRound(gameId, game);
        }
    }

    function _isWinner(GameInstance storage game, address player) internal view returns (bool) {
        for (uint256 i = 0; i < game.winners.length; i++) {
            if (game.winners[i] == player) {
                return true;
            }
        }
        return false;
    }

    function _removePlayerFromLevel(GameInstance storage game, address player, uint256 level) internal {
        game.levelPopulation[level]--;
        address[] storage levelPlayers = game.playersAtLevel[level];
        for (uint256 i = 0; i < levelPlayers.length; i++) {
            if (levelPlayers[i] == player) {
                levelPlayers[i] = levelPlayers[levelPlayers.length - 1];
                levelPlayers.pop();
                break;
            }
        }
    }

    function _eliminatePlayer(uint256 gameId, address player) internal {
        GameInstance storage game = games[gameId];
        require(game.isActivePlayer[player], "Player not active");

        // Remove from current level tracking
        uint256 currentLevel = game.playerLevels[player];
        _removePlayerFromLevel(game, player, currentLevel);

        // Update non-MAX_LEVEL counters if player was below MAX_LEVEL
        if (currentLevel < MAX_LEVEL) {
            if (game.hasCommitted[player]) {
                game.nonMaxLevelCommitCount--;
            }
            if (game.hasRevealed[player]) {
                game.nonMaxLevelRevealCount--;
            }
        }

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

        // Update non-MAX_LEVEL player count
        _updateNonMaxLevelCounts(game);

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
        return "Descend";
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

    // Additional view functions specific to Descend
    function getCurrentPhase(uint256 gameId) external view isValidGameId(gameId) returns (uint256) {
        return games[gameId].currentPhase;
    }

    function getRoundEndTime(uint256 gameId) external view isValidGameId(gameId) returns (uint256) {
        return games[gameId].roundEndTime;
    }

    function getPlayerLevel(uint256 gameId, address player) external view isValidGameId(gameId) returns (uint256) {
        require(games[gameId].isPlayer[player], "Player not in game");
        return games[gameId].playerLevels[player];
    }

    function getLastMove(uint256 gameId, address player) external view isValidGameId(gameId) returns (uint256) {
        require(games[gameId].isPlayer[player], "Player not in game");
        return games[gameId].lastMove[player];
    }

    function getLevelPopulation(uint256 gameId, uint256 level) external view isValidGameId(gameId) returns (uint256) {
        require(level <= MAX_LEVEL, "Invalid level");
        return games[gameId].levelPopulation[level];
    }

    function getLevelPopulations(uint256 gameId) external view isValidGameId(gameId) returns (uint256[] memory) {
        uint256[] memory populations = new uint256[](MAX_LEVEL + 1);
        for (uint256 level = 0; level <= MAX_LEVEL; level++) {
            populations[level] = games[gameId].levelPopulation[level];
        }
        return populations;
    }

    function getLevelCapacities(uint256 gameId) external view isValidGameId(gameId) returns (uint256[] memory) {
        GameInstance storage game = games[gameId];
        uint256[] memory capacities = new uint256[](MAX_LEVEL + 1);
        
        // Level 0 capacity is total players
        capacities[0] = game.players.length;
        
        // Levels 1-20 have standard capacity
        for (uint256 level = 1; level < MAX_LEVEL; level++) {
            capacities[level] = game.levelCapacity;
        }
        
        // Level 21 has final capacity
        capacities[MAX_LEVEL] = game.finalCapacity;
        
        return capacities;
    }

    function hasPlayerCommitted(uint256 gameId, address player) external view isValidGameId(gameId) returns (bool) {
        return games[gameId].hasCommitted[player];
    }

    function hasPlayerRevealed(uint256 gameId, address player) external view isValidGameId(gameId) returns (bool) {
        return games[gameId].hasRevealed[player];
    }

    function getPlayerInfo(uint256 gameId) external view isValidGameId(gameId) returns (DescendPlayerInfo[] memory) {
        GameInstance storage game = games[gameId];
        DescendPlayerInfo[] memory playersInfo = new DescendPlayerInfo[](game.players.length);

        for (uint256 i = 0; i < game.players.length; i++) {
            address playerAddress = game.players[i];
            playersInfo[i] = DescendPlayerInfo({
                playerAddress: playerAddress,
                playerNumber: game.playerNumbers[playerAddress],
                level: game.playerLevels[playerAddress],
                lastMove: game.lastMove[playerAddress],
                hasCommitted: game.hasCommitted[playerAddress],
                hasRevealed: game.hasRevealed[playerAddress],
                isActive: game.isActivePlayer[playerAddress]
            });
        }

        return playersInfo;
    }

    function getWinners(uint256 gameId) external view isValidGameId(gameId) returns (address[] memory) {
        GameInstance storage game = games[gameId];
        if (game.state == GameState.Completed) {
            return game.winners.length > 0 ? game.winners : game.activePlayers;
        }
        return new address[](0);
    }

    /// @dev Register my contract on Sonic FeeM
    function registerMe() external {
        (bool _success,) = address(0xDC2B0D2Dd2b7759D97D50db4eabDC36973110830).call(
            abi.encodeWithSignature("selfRegister(uint256)", 151)
        );
        require(_success, "FeeM registration failed");
    }
} 