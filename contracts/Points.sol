// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Points
 * @notice A contract for managing a points system with referrals
 * @dev Points are awarded based on S deposits with a 25% referral bonus
 */
contract Points is Ownable {
    // =============================================================
    // ======================= Constants ============================
    // =============================================================
    /// @notice Number of points awarded per 1 S (S)
    uint256 public constant POINTS_PER_S = 50;
    
    /// @notice Number of points needed to cash out 1 S
    uint256 public constant POINTS_PER_S_CASHOUT = 75;
    
    /// @notice Maximum total points that can be issued
    uint256 public constant MAX_POINTS = 50_000_000;
    
    /// @notice Minimum deposit amount (1 S = 50 points)
    uint256 public constant MIN_DEPOSIT = 1 ether;
    
    /// @notice Maximum number of addresses to return in pagination
    uint256 private constant MAX_PAGE_SIZE = 1000;

    /// @notice Referral bonus percentage (in basis points, e.g. 5000 = 50%)
    uint256 public referralBonusBps = 5000;

    // =============================================================
    // ===================== State Variables ========================
    // =============================================================
    /// @notice Total points issued, including referral bonuses
    uint256 public totalPointsIssued;
    
    /// @notice Mapping of address to their total point balance (registration + referral)
    mapping(address => uint256) public points;
    
    /// @notice Mapping of address to their withdrawable referral point balance
    mapping(address => uint256) public referralPoints;
    
    /// @notice List of all addresses that have received points
    address[] public addressList;
    
    /// @notice Tracks if an address has received points
    mapping(address => bool) public hasPoints;

    /// @notice Mapping of authorized contracts that can award points directly
    mapping(address => bool) public authorizedContracts;

    // =============================================================
    // ==================== Referral System ========================
    // =============================================================
    /// @notice Maps referral codes to their owners
    mapping(string => address) public referralCodeToAddress;
    
    /// @notice Maps addresses to their referral codes
    mapping(address => string) public addressToReferralCode;
    
    /// @notice Maps addresses to the referral code they used
    mapping(address => string) public usedReferralCode;

    // =============================================================
    // ======================== Events =============================
    // =============================================================
    /// @notice Emitted when points are awarded
    /// @param recipient Address receiving points
    /// @param amount Number of points awarded
    event PointsAwarded(address indexed recipient, uint256 amount);
    
    /// @notice Emitted when S is withdrawn
    /// @param owner Address receiving the withdrawal
    /// @param amount Amount of S withdrawn
    event Withdrawn(address indexed owner, uint256 amount);
    
    /// @notice Emitted when a referral code is registered
    /// @param user Address registering the code
    /// @param code The referral code registered
    event ReferralCodeRegistered(address indexed user, string code);
    
    /// @notice Emitted when a referral code is used
    /// @param user Address using the code
    /// @param code Referral code used
    /// @param referrer Address that owns the referral code
    event ReferralUsed(address indexed user, string code, address indexed referrer);

    /// @notice Emitted when referral points are cashed out
    /// @param user Address cashing out points
    /// @param points Number of points cashed out
    /// @param ethAmount Amount of ETH received
    event ReferralPointsCashedOut(address indexed user, uint256 points, uint256 ethAmount);

    /// @notice Emitted when ETH is deposited for cashouts without points being awarded
    /// @param depositor Address that deposited the ETH
    /// @param amount Amount of ETH deposited
    event CashoutDepositReceived(address indexed depositor, uint256 amount);

    /// @notice Emitted when a contract is authorized or deauthorized
    /// @param contractAddress Address of the contract
    /// @param authorized Whether the contract is authorized
    event ContractAuthorizationChanged(address indexed contractAddress, bool authorized);

    /// @notice Emitted when points are awarded by an authorized contract
    /// @param recipient Address receiving points
    /// @param amount Number of points awarded
    /// @param authorizedContract Contract that awarded the points
    event PointsAwardedByContract(address indexed recipient, uint256 amount, address indexed authorizedContract);

    // =============================================================
    // ======================== Errors =============================
    // =============================================================
    error PointsCapReached(uint256 remaining);
    error InvalidDeposit(uint256 min);
    error InvalidReferralCode();
    error ReferralCodeTaken();
    error ReferralCodeTooLong();

    // =============================================================
    // ======================== Modifiers ===========================
    // =============================================================
    
    modifier onlyAuthorizedContract() {
        require(authorizedContracts[msg.sender], "Not authorized contract");
        _;
    }

    constructor() Ownable(msg.sender) {}

    // =============================================================
    // ==================== Deposit Functions ======================
    // =============================================================
    
    /// @notice Deposit S to receive points
    function deposit() external payable {
        _awardPoints(msg.sender);
    }

    /// @notice Deposit ETH to be used for cashouts without receiving points
    function depositForCashouts() external payable {
        require(msg.value > 0, "Must deposit some ETH");
        emit CashoutDepositReceived(msg.sender, msg.value);
    }

    /// @notice Deposit S to award points to another address
    /// @param recipient Address to receive the points
    function depositFor(address recipient) external payable {
        require(recipient != address(0), "Invalid recipient");
        _awardPoints(recipient);
    }

    /// @notice Deposit S with a referral code to award points to another address
    /// @param recipient Address to receive the points
    /// @param referralCode Referral code to use for the deposit
    function depositFor(address recipient, string calldata referralCode) external payable {
        require(recipient != address(0), "Invalid recipient");
        require(referralCodeToAddress[referralCode] != address(0), "Invalid referral code");
        
        // Only set referral code if user hasn't used one before
        if (bytes(usedReferralCode[recipient]).length == 0) {
            usedReferralCode[recipient] = referralCode;
            emit ReferralUsed(recipient, referralCode, referralCodeToAddress[referralCode]);
        }
        
        _awardPoints(recipient);
    }

    // =============================================================
    // ==================== Referral Functions =====================
    // =============================================================
    
    /// @notice Register or update a referral code
    /// @param code The desired referral code
    function registerReferralCode(string calldata code) external {
        // Validate code length
        if (bytes(code).length > 20) {
            revert ReferralCodeTooLong();
        }

        // Validate code is not empty
        if (bytes(code).length == 0) {
            revert InvalidReferralCode();
        }

        // Check if code is already taken by someone else
        address currentOwner = referralCodeToAddress[code];
        if (currentOwner != address(0) && currentOwner != msg.sender) {
            revert ReferralCodeTaken();
        }

        // Check if user already has a referral code
        if (bytes(addressToReferralCode[msg.sender]).length > 0) {
            revert ReferralCodeTaken();
        }

        // Register the new code
        referralCodeToAddress[code] = msg.sender;
        addressToReferralCode[msg.sender] = code;

        emit ReferralCodeRegistered(msg.sender, code);
    }

    // =============================================================
    // ==================== Internal Functions =====================
    // =============================================================
    
    /// @notice Award points based on S value and handle referral bonuses
    /// @param recipient Address to receive the points
    function _awardPoints(address recipient) internal {
        if (msg.value < MIN_DEPOSIT) {
            revert InvalidDeposit(MIN_DEPOSIT);
        }
        
        // Calculate base points from S value
        uint256 pointsToAward = (msg.value / 1e18) * POINTS_PER_S;
        pointsToAward += (msg.value % 1e18) * POINTS_PER_S / 1e18;
        
        // Track total points needed including potential referral bonus
        uint256 totalPointsNeeded = pointsToAward;
        
        // Handle referral bonus if applicable
        string memory referralCode = usedReferralCode[recipient];
        if (bytes(referralCode).length > 0) {
            // Calculate and award referral bonus using configurable percentage
            uint256 referralBonus = (pointsToAward * referralBonusBps) / 10000;
            totalPointsNeeded += referralBonus;
            
            // Verify points cap with bonus included
            if (totalPointsIssued + totalPointsNeeded > MAX_POINTS) {
                revert PointsCapReached(getRemainingPoints());
            }
            
            // Award bonus to referrer
            address referrer = referralCodeToAddress[referralCode];
            if (referrer != address(0)) {
                points[referrer] += referralBonus;
                referralPoints[referrer] += referralBonus;
                emit PointsAwarded(referrer, referralBonus);
            }
        } else {
            // Verify points cap for non-referral deposit
            if (totalPointsIssued + pointsToAward > MAX_POINTS) {
                revert PointsCapReached(getRemainingPoints());
            }
        }

        // Award points to recipient
        points[recipient] += pointsToAward;
        
        // Add recipient to address list if first time
        if (!hasPoints[recipient]) {
            addressList.push(recipient);
            hasPoints[recipient] = true;
        }
        
        totalPointsIssued += totalPointsNeeded;
        emit PointsAwarded(recipient, pointsToAward);
    }

    // =============================================================
    // ==================== View Functions =========================
    // =============================================================
    
    /// @notice Get points balance for an account
    /// @param account Address to check
    /// @return total Total points owned by the account
    /// @return withdrawable Number of points that can be withdrawn
    function getPoints(address account) external view returns (uint256 total, uint256 withdrawable) {
        return (points[account], referralPoints[account]);
    }

    /// @notice Get remaining points that can be issued
    /// @return Number of points remaining before cap
    function getRemainingPoints() public view returns (uint256) {
        return totalPointsIssued >= MAX_POINTS ? 0 : MAX_POINTS - totalPointsIssued;
    }

    /// @notice Get total number of addresses with points
    /// @return Number of addresses in the system
    function getAddressCount() external view returns (uint256) {
        return addressList.length;
    }

    /// @notice Get paginated list of addresses and their balances
    /// @param start Starting index
    /// @param size Number of addresses to return
    /// @return addresses Array of addresses
    /// @return balances Array of point balances
    /// @return withdrawableBalances Array of withdrawable point balances
    function getAddressesPaginated(uint256 start, uint256 size) 
        external 
        view 
        returns (
            address[] memory addresses, 
            uint256[] memory balances,
            uint256[] memory withdrawableBalances
        ) 
    {
        require(start < addressList.length, "Invalid start");
        require(size > 0 && size <= MAX_PAGE_SIZE, "Invalid size");
        
        uint256 end = Math.min(start + size, addressList.length);
        uint256 length = end - start;
        
        addresses = new address[](length);
        balances = new uint256[](length);
        withdrawableBalances = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            addresses[i] = addressList[start + i];
            balances[i] = points[addresses[i]];
            withdrawableBalances[i] = referralPoints[addresses[i]];
        }
    }

    /// @notice Get top 100 addresses by point balance
    /// @return topAddresses Array of addresses
    /// @return topBalances Array of point balances
    /// @return withdrawableBalances Array of withdrawable point balances
    function getLeaderboard() public view returns (
        address[] memory topAddresses, 
        uint256[] memory topBalances,
        uint256[] memory withdrawableBalances
    ) {
        uint256 length = Math.min(addressList.length, 100);
        topAddresses = new address[](length);
        topBalances = new uint256[](length);
        withdrawableBalances = new uint256[](length);
        
        // Copy addresses and balances
        for (uint256 i = 0; i < length; i++) {
            topAddresses[i] = addressList[i];
            topBalances[i] = points[addressList[i]];
            withdrawableBalances[i] = referralPoints[addressList[i]];
        }
        
        // Sort using QuickSort
        if (length > 1) {
            quickSort(topAddresses, topBalances, withdrawableBalances, 0, int256(length - 1));
        }
    }

    /// @notice QuickSort implementation for sorting addresses by balance
    function quickSort(
        address[] memory addresses,
        uint256[] memory balances,
        uint256[] memory withdrawable,
        int256 left,
        int256 right
    ) internal pure {
        if (left >= right) return;
        
        uint256 pivot = balances[uint256(left + (right - left) / 2)];
        
        int256 i = left;
        int256 j = right;
        while (i <= j) {
            while (balances[uint256(i)] > pivot) i++;
            while (balances[uint256(j)] < pivot) j--;
            
            if (i <= j) {
                (addresses[uint256(i)], addresses[uint256(j)]) = (addresses[uint256(j)], addresses[uint256(i)]);
                (balances[uint256(i)], balances[uint256(j)]) = (balances[uint256(j)], balances[uint256(i)]);
                (withdrawable[uint256(i)], withdrawable[uint256(j)]) = (withdrawable[uint256(j)], withdrawable[uint256(i)]);
                i++;
                j--;
            }
        }
        
        if (left < j) quickSort(addresses, balances, withdrawable, left, j);
        if (i < right) quickSort(addresses, balances, withdrawable, i, right);
    }

    // =============================================================
    // ==================== Admin Functions ========================
    // =============================================================
    
    /// @notice Withdraw accumulated S (owner only)
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Nothing to withdraw");
        
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Withdrawal failed");
        
        emit Withdrawn(msg.sender, balance);
    }

    /// @notice Register contract with Sonic FeeM
    function registerMe() external {
        (bool _success,) = address(0xDC2B0D2Dd2b7759D97D50db4eabDC36973110830).call(
            abi.encodeWithSignature("selfRegister(uint256)", 151)
        );
        require(_success, "FeeM registration failed");
    }

    /// @notice Update the referral bonus percentage
    /// @param newBonusBps New bonus percentage in basis points (e.g. 2500 = 25%)
    function setReferralBonus(uint256 newBonusBps) external onlyOwner {
        require(newBonusBps <= 10000, "Bonus cannot exceed 100%");
        referralBonusBps = newBonusBps;
    }

    /// @notice Manually assign points to an address (owner only)
    /// @param recipient Address to receive points
    /// @param amount Number of points to assign
    /// @param isReferralPoints Whether these points should be withdrawable as referral points
    function assignPoints(address recipient, uint256 amount, bool isReferralPoints) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than 0");
        require(totalPointsIssued + amount <= MAX_POINTS, "Would exceed points cap");

        // Update points balances
        points[recipient] += amount;
        if (isReferralPoints) {
            referralPoints[recipient] += amount;
        }
        
        // Add recipient to address list if first time
        if (!hasPoints[recipient]) {
            addressList.push(recipient);
            hasPoints[recipient] = true;
        }
        
        totalPointsIssued += amount;
        emit PointsAwarded(recipient, amount);
    }

    /// @notice Authorize or deauthorize a contract to award points directly
    /// @param contractAddress Address of the contract to authorize/deauthorize
    /// @param authorized Whether to authorize or deauthorize the contract
    function setContractAuthorization(address contractAddress, bool authorized) external onlyOwner {
        require(contractAddress != address(0), "Invalid contract address");
        
        authorizedContracts[contractAddress] = authorized;
        emit ContractAuthorizationChanged(contractAddress, authorized);
    }

    /// @notice Migrate a referral code for a user during contract migration (owner only)
    /// @param user Address of the user to assign the referral code to
    /// @param code The referral code to assign
    function migrateReferralCode(address user, string calldata code) external onlyOwner {
        require(user != address(0), "Invalid user address");
        
        // Validate code length
        if (bytes(code).length > 20) {
            revert ReferralCodeTooLong();
        }

        // Validate code is not empty
        if (bytes(code).length == 0) {
            revert InvalidReferralCode();
        }

        // Check if code is already taken by someone else
        address currentOwner = referralCodeToAddress[code];
        if (currentOwner != address(0) && currentOwner != user) {
            revert ReferralCodeTaken();
        }

        // Clear any existing referral code for this user
        string memory existingCode = addressToReferralCode[user];
        if (bytes(existingCode).length > 0) {
            delete referralCodeToAddress[existingCode];
        }

        // Register the new code
        referralCodeToAddress[code] = user;
        addressToReferralCode[user] = code;

        emit ReferralCodeRegistered(user, code);
    }

    /// @notice Migrate used referral code for a user during contract migration (owner only)
    /// @param user Address of the user who used the referral code
    /// @param referralCode The referral code they used
    function migrateUsedReferralCode(address user, string calldata referralCode) external onlyOwner {
        require(user != address(0), "Invalid user address");
        require(bytes(referralCode).length > 0, "Invalid referral code");
        
        // Verify the referral code exists and is owned by someone
        address referrer = referralCodeToAddress[referralCode];
        require(referrer != address(0), "Referral code does not exist");
        
        usedReferralCode[user] = referralCode;
        emit ReferralUsed(user, referralCode, referrer);
    }

    /// @notice Cash out referral points for ETH
    /// @param amount Number of referral points to cash out
    function cashOutReferralPoints(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(referralPoints[msg.sender] >= amount, "Insufficient referral points");
        
        // Calculate ETH amount rounded down to 2 decimal places
        // First calculate the result in cents (multiply by 100)
        uint256 centsAmount = (amount * 100) / POINTS_PER_S_CASHOUT;
        // Convert cents back to ETH with 18 decimals (multiply by 1e16 since we're in cents)
        uint256 ethAmount = centsAmount * 1e16;
        require(address(this).balance >= ethAmount, "Insufficient contract balance");
        
        // Update points before transfer
        referralPoints[msg.sender] -= amount;
        points[msg.sender] -= amount;
        totalPointsIssued -= amount;
        
        // Transfer ETH
        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "Transfer failed");
        
        emit ReferralPointsCashedOut(msg.sender, amount, ethAmount);
    }

    // =============================================================
    // ================ Authorized Contract Functions ===============
    // =============================================================
    
    /// @notice Award points directly to a recipient (only callable by authorized contracts)
    /// @param recipient Address to receive the points
    /// @param pointsAmount Number of points to award
    /// @param isWithdrawable Whether these points should be withdrawable as referral points
    function awardPointsForPayout(address recipient, uint256 pointsAmount, bool isWithdrawable) external onlyAuthorizedContract {
        require(recipient != address(0), "Invalid recipient");
        require(pointsAmount > 0, "Points amount must be greater than 0");
        
        // Verify points cap
        if (totalPointsIssued + pointsAmount > MAX_POINTS) {
            revert PointsCapReached(getRemainingPoints());
        }

        // Award points to recipient
        points[recipient] += pointsAmount;
        
        // If withdrawable, also add to referral points
        if (isWithdrawable) {
            referralPoints[recipient] += pointsAmount;
        }
        
        // Add recipient to address list if first time
        if (!hasPoints[recipient]) {
            addressList.push(recipient);
            hasPoints[recipient] = true;
        }
        
        totalPointsIssued += pointsAmount;
        emit PointsAwardedByContract(recipient, pointsAmount, msg.sender);
    }
}
