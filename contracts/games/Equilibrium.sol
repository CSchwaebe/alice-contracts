// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGame.sol";

// Interface for RagnarokGameMaster's elimination function
interface IRagnarokGameMaster {
    function playerEliminated(address player) external;
}

contract Equilibrium is IGame, Ownable {
    // ============ Constants ============
    uint256 private constant GAME_DURATION = 10 minutes;
    uint256 private constant NUM_TEAMS = 4;

    // ============ Structs ============
    struct GameInstance {
        GameState state;
        uint256 gameStartTime;     // When the game was initialized
        uint256 gameEndTime;       // When the game was completed
        uint256 roundEndTime;      // When the game ends (10 minutes after start)
        address[] players;
        mapping(address => bool) isPlayer;
        mapping(address => uint256) playerNumbers;
        address[] activePlayers;
        mapping(address => bool) isActivePlayer;
        mapping(address => uint8) playerTeams;    // Current team of each player
        mapping(uint8 => uint256) teamSizes;      // Number of players in each team
    }

    struct EquilibriumPlayerInfo {
        address playerAddress;
        uint256 playerNumber;
        uint8 team;
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
    event PlayerSwitchedTeam(uint256 indexed gameId, address indexed player, uint8 fromTeam, uint8 toTeam);
    event PlayerEliminated(uint256 indexed gameId, address indexed player, uint256 playerNumber);
    event GameCompleted(uint256 indexed gameId, address[] winners);
    event TeamEliminated(uint256 indexed gameId, uint8 team, uint256 teamSize);
    event GameStarted(uint256 indexed gameId, uint256 endTime);

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

        // Create single game instance
        uint256 gameId = ++gameIdCounter;
        GameInstance storage game = games[gameId];
        game.state = GameState.Pregame;
        game.gameStartTime = block.timestamp;

        // Add all players to the game
        for (uint256 i = 0; i < _players.length; i++) {
            address player = _players[i];
            require(player != address(0), "Invalid player address");
            
            // Only check game state if player is marked as in a game
            if (isPlayerInGame[player]) {
                uint256 currentGameId = playerGameId[player];
                require(currentGameId == 0 || games[currentGameId].state == GameState.Completed, 
                        "Player already in active game");
            }

            game.players.push(player);
            game.playerNumbers[player] = _playerNumbers[i];
            game.isPlayer[player] = true;
            game.activePlayers.push(player);
            game.isActivePlayer[player] = true;
            game.playerTeams[player] = 0;  // All players start on team 0
            game.teamSizes[0]++;           // Increment team 0 size

            // Track player's game
            playerGameId[player] = gameId;
            isPlayerInGame[player] = true;
        }

        emit GameInitialized(game.players, _playerNumbers);
    }

    function startGames() external override onlyGameMaster returns (bool) {
        GameInstance storage game = games[gameIdCounter];
        if (game.state == GameState.Pregame && game.activePlayers.length > 0) {
            game.state = GameState.Active;
            game.roundEndTime = block.timestamp + GAME_DURATION;
            emit GameStarted(gameIdCounter, game.roundEndTime);
            return true;
        }
        
        return false;
    }

    function switchTeam(uint8 team) external {
        require(isPlayerInGame[msg.sender], "Player not in any game");
        require(team < NUM_TEAMS, "Invalid team number");
        
        uint256 gameId = playerGameId[msg.sender];
        GameInstance storage game = games[gameId];
        
        require(game.state == GameState.Active, "Game not active");
        require(block.timestamp <= game.roundEndTime, "Game has ended");
        
        uint8 currentTeam = game.playerTeams[msg.sender];
        require(currentTeam != team, "Already on this team");
        
        // Update team counts
        game.teamSizes[currentTeam]--;
        game.teamSizes[team]++;
        
        // Update player's team
        game.playerTeams[msg.sender] = team;
        
        emit PlayerSwitchedTeam(gameId, msg.sender, currentTeam, team);
    }

    function endExpiredGames() external override {
        GameInstance storage game = games[gameIdCounter];
        if (game.state == GameState.Active && block.timestamp > game.roundEndTime) {
            _eliminateLargestTeam(gameIdCounter);
        }
    }

    function endGame() external override onlyGameMaster returns (address[] memory) {
        GameInstance storage game = games[gameIdCounter];
        if (game.state == GameState.Active) {
            _eliminateLargestTeam(gameIdCounter);
        }
        return game.activePlayers;
    }

    // ============ Internal Functions ============
    function _eliminateLargestTeam(uint256 gameId) internal {
        GameInstance storage game = games[gameId];
        
        // Find the largest team size
        uint256 largestSize = 0;
        for (uint8 i = 0; i < NUM_TEAMS; i++) {
            if (game.teamSizes[i] > largestSize) {
                largestSize = game.teamSizes[i];
            }
        }
        
        // Count teams with largest size and collect their indices
        uint8[] memory largestTeams = new uint8[](NUM_TEAMS);
        uint256 tiedTeamCount = 0;
        
        for (uint8 i = 0; i < NUM_TEAMS; i++) {
            if (game.teamSizes[i] == largestSize) {
                largestTeams[tiedTeamCount] = i;
                tiedTeamCount++;
            }
        }
        
        // If all teams have same size, don't eliminate anyone
        if (tiedTeamCount == NUM_TEAMS) {
            game.state = GameState.Completed;
            game.gameEndTime = block.timestamp;
            emit GameCompleted(gameId, game.activePlayers);
            return;
        }
        
        // Randomly select one of the tied largest teams
        uint8 selectedTeamIndex = uint8(uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            gameId
        ))) % tiedTeamCount);
        
        uint8 teamToEliminate = largestTeams[selectedTeamIndex];
        
        // Create array to store players to eliminate
        address[] memory playersToEliminate = new address[](game.activePlayers.length);
        uint256 eliminationCount = 0;
        
        // Find all players on the selected team
        for (uint256 i = 0; i < game.activePlayers.length; i++) {
            address player = game.activePlayers[i];
            if (game.playerTeams[player] == teamToEliminate) {
                playersToEliminate[eliminationCount++] = player;
            }
        }
        
        // Eliminate players
        for (uint256 i = 0; i < eliminationCount; i++) {
            _eliminatePlayer(gameId, playersToEliminate[i]);
        }
        
        emit TeamEliminated(gameId, teamToEliminate, largestSize);
        
        // Complete the game
        game.state = GameState.Completed;
        game.gameEndTime = block.timestamp;
        emit GameCompleted(gameId, game.activePlayers);
    }

    function _eliminatePlayer(uint256 gameId, address player) internal {
        GameInstance storage game = games[gameId];
        require(game.isActivePlayer[player], "Player not active");

        // Update team size
        uint8 team = game.playerTeams[player];
        game.teamSizes[team]--;

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
        return "Equilibrium";
    }

    function getGameInfo(uint256 gameId) external view override isValidGameId(gameId) returns (GameInfo memory) {
        GameInstance storage game = games[gameId];
        return GameInfo({
            state: game.state,
            currentRound: 1,  // Always 1 as this is a single-round game
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
                currentRound: 1,  // Always 1 as this is a single-round game
                activePlayerCount: game.activePlayers.length
            });
        }
        return gamesInfo;
    }

    function getPlayers() external view override returns (address[] memory) {
        GameInstance storage game = games[gameIdCounter];
        return game.players;
    }

    function getPlayerGameId(address player) external view override returns (uint256) {
        return playerGameId[player];
    }

    function getActivePlayers() external view override returns (address[] memory) {
        GameInstance storage game = games[gameIdCounter];
        return game.activePlayers;
    }

    function getPlayerNumber(uint256 gameId, address player) external view override isValidGameId(gameId) returns (uint256) {
        require(games[gameId].isPlayer[player], "Player not in game");
        return games[gameId].playerNumbers[player];
    }

    // Additional view functions specific to Equilibrium
    function getPlayerTeam(uint256 gameId, address player) external view isValidGameId(gameId) returns (uint8) {
        require(games[gameId].isPlayer[player], "Player not in game");
        return games[gameId].playerTeams[player];
    }

    function getTeamSize(uint256 gameId, uint8 team) external view isValidGameId(gameId) returns (uint256) {
        require(team < NUM_TEAMS, "Invalid team number");
        return games[gameId].teamSizes[team];
    }

    function getPlayerInfo(uint256 gameId) external view isValidGameId(gameId) returns (EquilibriumPlayerInfo[] memory) {
        GameInstance storage game = games[gameId];
        EquilibriumPlayerInfo[] memory playersInfo = new EquilibriumPlayerInfo[](game.players.length);

        for (uint256 i = 0; i < game.players.length; i++) {
            address playerAddress = game.players[i];
            playersInfo[i] = EquilibriumPlayerInfo({
                playerAddress: playerAddress,
                playerNumber: game.playerNumbers[playerAddress],
                team: game.playerTeams[playerAddress],
                isActive: game.isActivePlayer[playerAddress]
            });
        }

        return playersInfo;
    }
} 