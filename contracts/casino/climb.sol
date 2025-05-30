pragma solidity ^0.8.28;
 
import { IEntropyConsumer } from "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import { IEntropy } from "@pythnetwork/entropy-sdk-solidity/IEntropy.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Interface for Points contract
interface IPoints {
  function depositFor(address recipient) external payable;
  function awardPointsForPayout(address recipient, uint256 pointsAmount, bool isWithdrawable) external;
}
 
contract Climb is IEntropyConsumer, ReentrancyGuard, Ownable {
  // ============ Constants ============
  uint256 public constant MIN_DEPOSIT = 1 ether;
  uint8 public constant MAX_LEVEL = 10;
  uint8 public constant MIN_CASHOUT_LEVEL = 1;
  uint32 public constant MULTIPLIER_PRECISION = 100; // Multipliers are stored * 100
  uint16 public constant ODDS_PRECISION = 10000; // Odds are out of 10000
  
  // ============ Configurable Parameters ============
  uint256 public maxDeposit = 1 ether; // Can be changed by owner
  bool public pointsAreWithdrawable = false; // Can be changed by owner
  
  // ============ State Variables ============
  IEntropy entropy;
  IPoints public pointsContract; // Points contract interface
  
  // Enum for different types of entropy requests
  enum RequestType { NONE, CLIMB, CASHOUT, AUTO_CLIMB }
  
  // Game state for each player's current active game
  struct GameState {
    uint8 currentLevel;      // Current level (0-10, starts at 0)
    bool isActive;           // Whether game is in progress
    uint64 pendingSequence;  // Sequence number for pending request
    RequestType pendingType; // Type of pending request
    uint256 startTime;       // When the game started
    uint256 depositAmount;   // Amount deposited by player
    uint256 gameId;          // Unique game ID
    uint8 targetLevel;       // Target level for auto-climb feature
  }
  
  // Completed game record for history
  struct CompletedGame {
    uint256 gameId;          // Unique game ID
    address player;          // Player address
    uint8 finalLevel;        // Final level reached
    bool success;            // Whether game ended successfully (cashOut/win) or bust
    uint32 finalMultiplier;  // Final multiplier achieved
    uint256 depositAmount;   // Amount deposited
    uint256 payout;          // Amount paid out (0 if busted)
    uint256 startTime;       // When game started
    uint256 endTime;         // When game ended
    string endReason;        // "cashOut", "win", or "bust"
    bool paidInPoints;       // Whether payout was in points instead of Sonic
  }
  
  // Mapping from player address to their current active game state
  mapping(address => GameState) public playerGames;
  
  // Mapping from gameId to completed game record
  mapping(uint256 => CompletedGame) public completedGames;
  
  // Mapping from player address to array of their completed game IDs
  mapping(address => uint256[]) public playerGameHistory;
  
  // Mapping from sequence number to player address for entropy callbacks
  mapping(uint64 => address) private sequenceToPlayer;
  
  // Mapping from sequence number to cashout request type
  mapping(uint64 => bool) private sequenceIsCashout;
  
  // Mapping to store entropy results
  mapping(uint64 => uint256) private entropyResults;
  
  // Global game counter
  uint256 public totalGamesPlayed;
  
  // Odds of reaching each level (multiplied by 100 for precision)
  // odds[0] = 1000 (100% to reach level 0), odds[1] = 8909 (89.09% to reach level 1), etc.
  uint16[11] public odds;
  
  // Multipliers for each level (multiplied by 100 for precision)
  // multiplier[0] = 100 (1.00×), multiplier[1] = 110 (1.10×), etc.
  uint32[11] public multiplier;
  
  // Point multipliers for each level when paying out in points (raw multipliers, not * 100)
  // pointMultiplier[1] = 20 (20×), pointMultiplier[2] = 35 (35×), etc.
  uint32[11] public pointMultiplier;
  
  // Event data structures for cleaner events
  struct GameStartData {
    address player;
    uint256 gameId;
    uint256 timestamp;
    uint256 depositAmount;
  }
  
  struct GameEndData {
    address player;
    uint256 gameId;
    uint8 finalLevel;
    bool success;
    uint32 finalMultiplier;
    uint256 payout;
    string endReason;
    bool paidInPoints;
  }
  
  struct RequestData {
    address player;
    uint256 gameId;
    uint8 level;
    uint64 sequenceNumber;
  }
  
  // Events
  event GameStarted(GameStartData data);
  event RequestAttempted(RequestData data, bool isCashout);
  event ClimbResult(address indexed player, uint256 indexed gameId, uint8 fromLevel, uint8 newLevel, bool success, bool gameEnded, uint256 randomNumber);
  event PlayerCashedOut(address indexed player, uint256 indexed gameId, uint8 level, uint32 multiplierValue, uint256 payout, bool paidInPoints);
  event GameEnded(GameEndData data);
  event AutoClimbCompleted(address indexed player, uint256 indexed gameId, uint8 startLevel, uint8 finalLevel, uint8 targetLevel, bool reachedTarget);
  event MaxDepositChanged(uint256 oldMaxDeposit, uint256 newMaxDeposit);
  event FundsDeposited(address indexed depositor, uint256 amount);
  event PointsContractUpdated(address indexed oldContract, address indexed newContract);
  event PointsWithdrawableChanged(bool oldValue, bool newValue);
  event EntropyReceived(address indexed player, uint256 indexed gameId, uint64 sequenceNumber, uint256 randomNumber);
  
  // ============ Modifiers ============
  modifier hasActiveGame() {
    require(playerGames[msg.sender].isActive, "No active game");
    _;
  }
  
  modifier noPendingAction() {
    require(playerGames[msg.sender].pendingType == RequestType.NONE, "Cannot perform action while request is pending");
    _;
  }
  
  modifier validLevel(uint8 level) {
    require(level <= MAX_LEVEL, "Invalid level");
    _;
  }
  
  modifier validDepositAmount() {
    require(msg.value >= MIN_DEPOSIT, "Deposit below minimum");
    require(msg.value <= maxDeposit, "Deposit exceeds maximum");
    _;
  }

  constructor(address entropyAddress, address pointsAddress) Ownable(msg.sender) {
    entropy = IEntropy(entropyAddress);
    pointsContract = IPoints(pointsAddress);
    totalGamesPlayed = 0;
    
    // Initialize odds for reaching each level (0-indexed)
    odds[0] = 1000;   // Level 0: 100% (everyone starts here)
    odds[1] = 8909;   // Level 1: 89.09%
    odds[2] = 7142;   // Level 2: 71.42%
    odds[3] = 7299;   // Level 3: 72.99%
    odds[4] = 6483;   // Level 4: 64.83%
    odds[5] = 5830;   // Level 5: 58.30%
    odds[6] = 4854;   // Level 6: 48.54%
    odds[7] = 3880;   // Level 7: 38.80%
    odds[8] = 4845;   // Level 8: 48.45%
    odds[9] = 2420;   // Level 9: 24.20%
    odds[10] = 1936;  // Level 10: 19.36%
    
    // Initialize multipliers for each level
    multiplier[0] = 100;    // Level 0: 1.00× (deposit amount)
    multiplier[1] = 110;    // Level 1: 1.10×
    multiplier[2] = 150;    // Level 2: 1.50×
    multiplier[3] = 200;    // Level 3: 2.00×
    multiplier[4] = 300;    // Level 4: 3.00×
    multiplier[5] = 500;    // Level 5: 5.00×
    multiplier[6] = 1000;   // Level 6: 10.00×
    multiplier[7] = 2500;   // Level 7: 25.00×
    multiplier[8] = 5000;   // Level 8: 50.00×
    multiplier[9] = 20000;  // Level 9: 200.00×
    multiplier[10] = 100000; // Level 10: 1000.00×
    
    // Initialize point multipliers for each level (raw multipliers)
    pointMultiplier[0] = 0;     // Level 0: Cannot cash out at level 0
    pointMultiplier[1] = 20;    // Level 1: 20×
    pointMultiplier[2] = 35;    // Level 2: 35×
    pointMultiplier[3] = 50;    // Level 3: 50×
    pointMultiplier[4] = 100;   // Level 4: 100×
    pointMultiplier[5] = 250;   // Level 5: 250×
    pointMultiplier[6] = 500;   // Level 6: 500×
    pointMultiplier[7] = 1250;  // Level 7: 1250×
    pointMultiplier[8] = 2500;  // Level 8: 2500×
    pointMultiplier[9] = 10000; // Level 9: 10000×
    pointMultiplier[10] = 50000; // Level 10: 50000×
  }

  // Start a new game with ETH deposit
  function startGame() public payable nonReentrant validDepositAmount {
    require(!playerGames[msg.sender].isActive, "Game already in progress");
    require(playerGames[msg.sender].pendingType == RequestType.NONE, "Pending request must be resolved first");
    
    totalGamesPlayed++;
    
    playerGames[msg.sender] = GameState({
      currentLevel: 0,
      isActive: true,
      pendingSequence: 0,
      pendingType: RequestType.NONE,
      startTime: block.timestamp,
      depositAmount: msg.value,
      gameId: totalGamesPlayed,
      targetLevel: 0
    });
    
    emit GameStarted(GameStartData({
      player: msg.sender,
      gameId: totalGamesPlayed,
      timestamp: block.timestamp,
      depositAmount: msg.value
    }));
  }
  
  // Internal function to save completed game to history
  function _saveCompletedGame(address player, uint8 finalLevel, bool success, uint32 finalMultiplier, uint256 payout, string memory endReason, bool paidInPoints) internal {
    GameState memory game = playerGames[player];
    
    CompletedGame memory completedGame = CompletedGame({
      gameId: game.gameId,
      player: player,
      finalLevel: finalLevel,
      success: success,
      finalMultiplier: finalMultiplier,
      depositAmount: game.depositAmount,
      payout: payout,
      startTime: game.startTime,
      endTime: block.timestamp,
      endReason: endReason,
      paidInPoints: paidInPoints
    });
    
    // Store completed game
    completedGames[game.gameId] = completedGame;
    
    // Add to player's history
    playerGameHistory[player].push(game.gameId);
  }
  
  // Player chooses to cash out at current level - now requests random number for payout type
  function cashOut() external payable nonReentrant hasActiveGame noPendingAction {
    GameState storage game = playerGames[msg.sender];
    require(game.currentLevel >= MIN_CASHOUT_LEVEL && game.currentLevel <= MAX_LEVEL, "Cannot cash out at level 0");
    
    uint64 sequenceNumber = _requestEntropy(game, RequestType.CASHOUT, 100);
    emit RequestAttempted(RequestData({
      player: msg.sender,
      gameId: game.gameId,
      level: game.currentLevel,
      sequenceNumber: sequenceNumber
    }), true);
  }
  
  // Player chooses to climb to the next level
  function climb() public payable nonReentrant hasActiveGame noPendingAction returns (uint64) {
    GameState storage game = playerGames[msg.sender];
    require(game.currentLevel < MAX_LEVEL, "Already at maximum level");
    
    uint64 sequenceNumber = _requestEntropy(game, RequestType.CLIMB, 0);
    emit RequestAttempted(RequestData({
      player: msg.sender,
      gameId: game.gameId,
      level: game.currentLevel,
      sequenceNumber: sequenceNumber
    }), false);
    
    return sequenceNumber;
  }
  
  // Player chooses to automatically climb to a target level
  function autoClimb(uint8 targetLevel) external payable nonReentrant hasActiveGame noPendingAction returns (uint64) {
    GameState storage game = playerGames[msg.sender];
    require(targetLevel > game.currentLevel, "Target level must be higher than current level");
    require(targetLevel <= MAX_LEVEL, "Target level exceeds maximum");
    
    // Store target level for use in entropy callback
    game.targetLevel = targetLevel;
    
    uint64 sequenceNumber = _requestEntropy(game, RequestType.AUTO_CLIMB, 0);
    emit RequestAttempted(RequestData({
      player: msg.sender,
      gameId: game.gameId,
      level: game.currentLevel,
      sequenceNumber: sequenceNumber
    }), false);
    
    return sequenceNumber;
  }
  
  // Generate user random number for entropy request
  function _generateUserRandomNumber(uint8 currentLevel) private view returns (bytes32) {
    return keccak256(abi.encodePacked(
      block.timestamp,
      block.prevrandao,
      msg.sender,
      blockhash(block.number - 1),
      currentLevel
    ));
  }
  
  // Helper function to request entropy and update game state
  function _requestEntropy(GameState storage game, RequestType requestType, uint8 levelOffset) private returns (uint64) {
    bytes32 userRandomNumber = _generateUserRandomNumber(game.currentLevel + levelOffset);
    
    address entropyProvider = entropy.getDefaultProvider();
    uint256 fee = entropy.getFee(entropyProvider);
    require(msg.value >= fee, "Insufficient fee for entropy request");

    uint64 sequenceNumber = entropy.requestWithCallback{ value: fee }(
      entropyProvider,
      userRandomNumber
    );
    
    // Update game state
    game.pendingSequence = sequenceNumber;
    game.pendingType = requestType;
    sequenceToPlayer[sequenceNumber] = msg.sender;
    sequenceIsCashout[sequenceNumber] = (requestType == RequestType.CASHOUT);
    
    return sequenceNumber;
  }
  
  // Get the success threshold for climbing from current level to next level
  function getSuccessThreshold(uint8 currentLevel) public view returns (uint256) {
    require(currentLevel < MAX_LEVEL, "Invalid level for climbing");
    uint8 targetLevel = currentLevel + 1;
    uint16 targetOdds = odds[targetLevel];
    return (uint256(targetOdds) * type(uint256).max) / ODDS_PRECISION;
  }
  
  // Check if a random number represents success for climbing to next level
  function isClimbSuccessful(uint256 randomNumber, uint8 currentLevel) public view returns (bool) {
    uint256 threshold = getSuccessThreshold(currentLevel);
    return randomNumber <= threshold;
  }

  // Check if a random number represents points payout (50% chance)
  function isPointsPayout(uint256 randomNumber) public pure returns (bool) {
    return randomNumber % 2 == 0;
  }

  function entropyCallback(
    uint64 sequenceNumber,
    address provider,
    bytes32 randomNumber
  ) internal override {
    address player = sequenceToPlayer[sequenceNumber];
    if (player == address(0)) return; // Just return if unknown sequence
    
    GameState storage game = playerGames[player];
    if (game.pendingType == RequestType.NONE) return; // Just return if no pending request
    if (game.pendingSequence != sequenceNumber) return; // Just return if mismatch
    
    // Store the entropy result
    uint256 randomUint = uint256(randomNumber);
    entropyResults[sequenceNumber] = randomUint;
    
    // Emit that we received entropy
    emit EntropyReceived(player, game.gameId, sequenceNumber, randomUint);
    
    // Add back proper climb logic with safer math
    if (game.pendingType == RequestType.CLIMB) {
      uint8 currentLevel = game.currentLevel;
      
      // Simple success check using modulo to avoid complex math
      // Use the odds directly: odds[1] = 8909 means 89.09% success
      if (currentLevel < MAX_LEVEL) {
        uint8 targetLevel = currentLevel + 1;
        uint16 targetOdds = odds[targetLevel];
        
        // Simple percentage check: random % 10000 < targetOdds
        bool success = (randomUint % ODDS_PRECISION) < targetOdds;
        
        if (success) {
          // Successful climb
          game.currentLevel = targetLevel;
        } else {
          // Failed climb - end game
          game.isActive = false;
          
          // Award 10 consolation points for bust
          pointsContract.awardPointsForPayout(player, 10, pointsAreWithdrawable);
          
          // Save completed game (bust with consolation points)
          _saveCompletedGame(player, currentLevel, false, 0, 10, "bust", true);
          
          // Emit game ended event
          emit GameEnded(GameEndData({
            player: player,
            gameId: game.gameId,
            finalLevel: currentLevel,
            success: false,
            finalMultiplier: 0,
            payout: 10,
            endReason: "bust",
            paidInPoints: true
          }));
        }
        
        // Emit climb result event
        emit ClimbResult(player, game.gameId, currentLevel, game.currentLevel, success, !success, randomUint);
      }
    }
    // Add back cashout logic with automatic distribution
    else if (game.pendingType == RequestType.CASHOUT) {
      uint8 currentLevel = game.currentLevel;
      
      // Determine if payout is in points or ETH (50% chance each)
      bool payInPoints = isPointsPayout(randomUint);
      uint32 finalMultiplier;
      uint256 payout;
      
      if (payInPoints) {
        // Points payout - convert ETH amount to points
        finalMultiplier = pointMultiplier[currentLevel];
        // Convert ETH to points: 1 ETH = finalMultiplier points (not wei)
        payout = (game.depositAmount / 1 ether) * finalMultiplier;
        
        // Award points directly (external call)
        pointsContract.awardPointsForPayout(player, payout, pointsAreWithdrawable);
      } else {
        // ETH payout
        finalMultiplier = multiplier[currentLevel];
        payout = (game.depositAmount * finalMultiplier) / MULTIPLIER_PRECISION;
        
        // Transfer ETH directly (external call)
        (bool success, ) = payable(player).call{value: payout}("");
        require(success, "ETH transfer failed");
      }
      
      // End the game
      game.isActive = false;
      
      // Emit cashout event
      emit PlayerCashedOut(player, game.gameId, currentLevel, finalMultiplier, payout, payInPoints);
      
      // Save completed game
      _saveCompletedGame(player, currentLevel, true, finalMultiplier, payout, "cashOut", payInPoints);
      
      // Emit game ended event
      emit GameEnded(GameEndData({
        player: player,
        gameId: game.gameId,
        finalLevel: currentLevel,
        success: true,
        finalMultiplier: finalMultiplier,
        payout: payout,
        endReason: "cashOut",
        paidInPoints: payInPoints
      }));
    }
    // Handle auto-climb logic
    else if (game.pendingType == RequestType.AUTO_CLIMB) {
      _handleAutoClimb(player, game, randomUint);
    }
    
    // Clear pending state
    game.pendingType = RequestType.NONE;
    game.pendingSequence = 0;
    
    // Clean up sequence mappings
    delete sequenceToPlayer[sequenceNumber];
    delete sequenceIsCashout[sequenceNumber];
  }
  
  // Helper function to handle auto-climb logic
  function _handleAutoClimb(address player, GameState storage game, uint256 baseRandom) internal {
    uint8 currentLevel = game.currentLevel;
    uint8 targetLevel = game.targetLevel;
    uint8 startLevel = currentLevel; // Remember starting level for event
    
    // Simulate climbs from current level to target level
    for (uint8 level = currentLevel; level < targetLevel; level++) {
      // Generate pseudo-random number for this level using base entropy + level + player
      uint256 levelRandom = uint256(keccak256(abi.encodePacked(baseRandom, level, player, game.gameId)));
      
      uint8 nextLevel = level + 1;
      uint16 targetOdds = odds[nextLevel];
      
      // Check if climb is successful using same logic as manual climb
      bool success = (levelRandom % ODDS_PRECISION) < targetOdds;
      
      if (!success) {
        // Failed climb - end game at this level
        game.isActive = false;
        
        // Award 10 consolation points for bust
        pointsContract.awardPointsForPayout(player, 10, pointsAreWithdrawable);
        
        // Emit auto-climb completion event (failed to reach target)
        emit AutoClimbCompleted(player, game.gameId, startLevel, level, targetLevel, false);
        
        // Save completed game (bust with consolation points)
        _saveCompletedGame(player, level, false, 0, 10, "bust", true);
        
        // Emit climb result for the failed level - show attempted transition
        emit ClimbResult(player, game.gameId, level, nextLevel, false, true, levelRandom);
        
        // Emit game ended event
        emit GameEnded(GameEndData({
          player: player,
          gameId: game.gameId,
          finalLevel: level,
          success: false,
          finalMultiplier: 0,
          payout: 10,
          endReason: "bust",
          paidInPoints: true
        }));
        
        return; // Exit function - game is over
      } else {
        // Successful climb - advance to next level
        game.currentLevel = nextLevel;
        
        // Emit climb result for successful level
        emit ClimbResult(player, game.gameId, level, nextLevel, true, false, levelRandom);
      }
    }
    
    // If we reach here, all climbs were successful!
    // Emit auto-climb completion event (successfully reached target)
    emit AutoClimbCompleted(player, game.gameId, startLevel, targetLevel, targetLevel, true);
    
    // Player is now at target level and can cash out or continue climbing manually
    // Game remains active for player to decide next action
  }
  
  // ============ View Functions ============
  function getPlayerGame(address player) external view returns (GameState memory) {
    return playerGames[player];
  }
  
  function getOdds(uint8 level) external view validLevel(level) returns (uint16) {
    return odds[level];
  }
  
  function getMultiplier(uint8 level) external view validLevel(level) returns (uint32) {
    return multiplier[level];
  }
  
  function getPointMultiplier(uint8 level) external view validLevel(level) returns (uint32) {
    return pointMultiplier[level];
  }
  
  function canPlayerClimb(address player) external view returns (bool) {
    GameState memory game = playerGames[player];
    return game.isActive && game.pendingType == RequestType.NONE && game.currentLevel < MAX_LEVEL;
  }
  
  function canPlayerCashOut(address player) external view returns (bool) {
    GameState memory game = playerGames[player];
    return game.isActive && game.pendingType == RequestType.NONE && game.currentLevel >= MIN_CASHOUT_LEVEL;
  }
  
  function canPlayerAutoClimb(address player, uint8 targetLevel) external view returns (bool) {
    GameState memory game = playerGames[player];
    return game.isActive && 
           game.pendingType == RequestType.NONE && 
           targetLevel > game.currentLevel && 
           targetLevel <= MAX_LEVEL;
  }
  
  function getAutoClimbSuccessProbability(address player, uint8 targetLevel) external view returns (uint256) {
    GameState memory game = playerGames[player];
    require(game.isActive, "No active game");
    require(targetLevel > game.currentLevel, "Target level must be higher than current level");
    require(targetLevel <= MAX_LEVEL, "Target level exceeds maximum");
    
    // Calculate cumulative probability of reaching target level
    uint256 cumulativeProbability = ODDS_PRECISION; // Start at 100%
    
    for (uint8 level = game.currentLevel + 1; level <= targetLevel; level++) {
      cumulativeProbability = (cumulativeProbability * odds[level]) / ODDS_PRECISION;
    }
    
    return cumulativeProbability; // Returns probability out of ODDS_PRECISION (10000)
  }
  
  function getAutoClimbPathDetails(address player, uint8 targetLevel) external view returns (
    uint8[] memory levels,
    uint16[] memory levelOdds,
    uint32[] memory sonicMultipliers,
    uint32[] memory pointMultipliers_,
    uint256 overallSuccessProbability
  ) {
    GameState memory game = playerGames[player];
    require(game.isActive, "No active game");
    require(targetLevel > game.currentLevel, "Target level must be higher than current level");
    require(targetLevel <= MAX_LEVEL, "Target level exceeds maximum");
    
    uint8 pathLength = targetLevel - game.currentLevel;
    levels = new uint8[](pathLength);
    levelOdds = new uint16[](pathLength);
    sonicMultipliers = new uint32[](pathLength);
    pointMultipliers_ = new uint32[](pathLength);
    
    uint256 cumulativeProbability = ODDS_PRECISION;
    
    for (uint8 i = 0; i < pathLength; i++) {
      uint8 level = game.currentLevel + 1 + i;
      levels[i] = level;
      levelOdds[i] = odds[level];
      sonicMultipliers[i] = multiplier[level];
      pointMultipliers_[i] = pointMultiplier[level];
      
      cumulativeProbability = (cumulativeProbability * odds[level]) / ODDS_PRECISION;
    }
    
    overallSuccessProbability = cumulativeProbability;
  }
  
  function getPotentialPayout(address player, uint8 level, bool isPoints) external view validLevel(level) returns (uint256) {
    GameState memory game = playerGames[player];
    require(game.isActive, "No active game");
    
    if (isPoints) {
      return game.depositAmount * pointMultiplier[level];
    } else {
      return (game.depositAmount * multiplier[level]) / MULTIPLIER_PRECISION;
    }
  }
  
  function getClimbOdds(address player) external view returns (uint16) {
    GameState memory game = playerGames[player];
    require(game.isActive, "No active game");
    require(game.currentLevel < MAX_LEVEL, "Already at maximum level");
    return odds[game.currentLevel + 1];
  }
  
  // Game history functions
  function getCompletedGame(uint256 gameId) external view returns (CompletedGame memory) {
    return completedGames[gameId];
  }
  
  function getPlayerGameCount(address player) external view returns (uint256) {
    return playerGameHistory[player].length;
  }
  
  function getPlayerGameHistory(address player) external view returns (uint256[] memory) {
    return playerGameHistory[player];
  }
  
  function getPlayerGameHistoryPaginated(address player, uint256 offset, uint256 limit) external view returns (CompletedGame[] memory) {
    uint256[] memory gameIds = playerGameHistory[player];
    require(offset < gameIds.length, "Offset out of bounds");
    
    uint256 end = offset + limit;
    if (end > gameIds.length) {
      end = gameIds.length;
    }
    
    CompletedGame[] memory games = new CompletedGame[](end - offset);
    for (uint256 i = offset; i < end; i++) {
      games[i - offset] = completedGames[gameIds[i]];
    }
    
    return games;
  }
  
  function getPlayerStats(address player) external view returns (
    uint256 totalGames,
    uint256 totalWins,
    uint256 totalBusts,
    uint256 totalDeposited,
    uint256 netProfit,
    uint256 totalAliceWon,
    uint256 totalSonicWon,
    uint8 highestLevelReached
  ) {
    uint256[] memory gameIds = playerGameHistory[player];
    totalGames = gameIds.length;
    
    for (uint256 i = 0; i < gameIds.length; i++) {
      CompletedGame memory game = completedGames[gameIds[i]];
      totalDeposited += game.depositAmount;
      
      if (game.success) {
        totalWins++;
        
        // Track points vs ETH payouts
        if (game.paidInPoints) {
          totalAliceWon += game.payout;
        } else {
          totalSonicWon += game.payout;
        }
      } else {
        totalBusts++;
      }
      
      // Track highest level reached
      if (game.finalLevel > highestLevelReached) {
        highestLevelReached = game.finalLevel;
      }
    }
    
    // Only consider ETH payouts for net profit calculation since points are rewards
    if (totalSonicWon >= totalDeposited) {
      netProfit = totalSonicWon - totalDeposited;
    } else {
      netProfit = 0; // Represent loss as 0 for simplicity, or you could use int256
    }
  }
  
  // ============ Batch View Functions for UI ============
  
  /// @notice Get all odds for all levels (useful for UI tables)
  function getAllOdds() external view returns (uint16[11] memory) {
    return odds;
  }
  
  /// @notice Get all Sonic multipliers for all levels
  function getAllMultipliers() external view returns (uint32[11] memory) {
    return multiplier;
  }
  
  /// @notice Get all point multipliers for all levels  
  function getAllPointMultipliers() external view returns (uint32[11] memory) {
    return pointMultiplier;
  }
  
  /// @notice Get complete level info for UI display
  function getLevelInfo(uint8 level) external view validLevel(level) returns (
    uint16 oddsToReach,
    uint32 sonicMultiplier, 
    uint32 pointMultiplier_,
    bool canCashOut
  ) {
    return (
      odds[level],
      multiplier[level],
      pointMultiplier[level],
      level >= MIN_CASHOUT_LEVEL
    );
  }
  
  /// @notice Get all level info at once for efficient UI loading
  function getAllLevelInfo() external view returns (
    uint16[11] memory allOdds,
    uint32[11] memory allSonicMultipliers,
    uint32[11] memory allPointMultipliers,
    uint8 minCashoutLevel,
    uint8 maxLevel
  ) {
    return (
      odds,
      multiplier, 
      pointMultiplier,
      MIN_CASHOUT_LEVEL,
      MAX_LEVEL
    );
  }
  
  // ============ ETH Management ============
  receive() external payable {
    // Allow ETH deposits to fund the contract
    emit FundsDeposited(msg.sender, msg.value);
  }
  
  function depositFunds() external payable onlyOwner {
    // Explicit function for owner to deposit ETH
    require(msg.value > 0, "Must deposit some ETH");
    emit FundsDeposited(msg.sender, msg.value);
  }
  
  // ============ Owner Functions ============
  function setMaxDeposit(uint256 newMaxDeposit) external onlyOwner {
    require(newMaxDeposit >= MIN_DEPOSIT, "Max deposit cannot be below minimum deposit");
    require(newMaxDeposit > 0, "Max deposit must be greater than zero");
    
    uint256 oldMaxDeposit = maxDeposit;
    maxDeposit = newMaxDeposit;
    
    emit MaxDepositChanged(oldMaxDeposit, newMaxDeposit);
  }
  
  function setPointsContract(address newPointsContract) external onlyOwner {
    require(newPointsContract != address(0), "Invalid points contract address");
    
    address oldContract = address(pointsContract);
    pointsContract = IPoints(newPointsContract);
    
    emit PointsContractUpdated(oldContract, newPointsContract);
  }
  
  function setPointsWithdrawable(bool withdrawable) external onlyOwner {
    bool oldValue = pointsAreWithdrawable;
    pointsAreWithdrawable = withdrawable;
    
    emit PointsWithdrawableChanged(oldValue, withdrawable);
  }
  
  function withdraw(uint256 amount) external onlyOwner {
    require(address(this).balance >= amount, "Insufficient balance");
    
    (bool success, ) = payable(owner()).call{value: amount}("");
    require(success, "Withdrawal failed");
  }
  
  function getContractBalance() external view returns (uint256) {
    return address(this).balance;
  }

  function getEntropy() internal view override returns (address) {
    return address(entropy);
  }
}
 