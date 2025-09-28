// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/**
 * @title SimpleBoringVault
 * @notice A simplified vault that holds strategy capital and executes trades with USD-based accounting
 * @dev 80% of liquidity from the hook will be managed here, with shares representing USD value
 */
contract SimpleBoringVault is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    // ========================================= STATE =========================================

    /**
     * @notice The UniversalPrivacyHook that can deposit funds
     */
    address public immutable hook;

    /**
     * @notice The SwapManager AVS that can execute strategies
     */
    address public immutable tradeManager;

    /**
     * @notice Pyth oracle for price feeds
     */
    IPyth public immutable pyth;

    /**
     * @notice Track token balances deposited from hook
     */
    mapping(address => uint256) public tokenBalances;

    /**
     * @notice Track USD-based shares for each depositor
     */
    mapping(address => uint256) public userShares;

    /**
     * @notice Total USD value of all shares
     */
    uint256 public totalSharesUSD;

    /**
     * @notice Mapping of token addresses to their Pyth price feed IDs
     */
    mapping(address => bytes32) public tokenPriceFeedIds;

    /**
     * @notice Track which addresses are authorized to execute
     */
    mapping(address => bool) public authorizedExecutors;

    /**
     * @notice Price staleness threshold in seconds
     */
    uint256 public constant PRICE_STALENESS_THRESHOLD = 60;

    // ========================================= EVENTS =========================================

    event Deposited(address indexed token, uint256 amount, uint256 usdValue, address indexed from);
    event Withdrawn(address indexed token, uint256 amount, uint256 usdValue, address indexed to);
    event StrategyExecuted(address indexed target, bytes data, uint256 value, bytes result);
    event ExecutorUpdated(address indexed executor, bool authorized);
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed to);
    event PriceFeedIdSet(address indexed token, bytes32 feedId);

    // ========================================= ERRORS =========================================

    error Unauthorized();
    error InsufficientBalance();
    error ExecutionFailed();
    error ZeroAddress();
    error ZeroAmount();
    error PriceFeedNotSet();
    error StalePrice();
    error InsufficientShares();

    // ========================================= MODIFIERS =========================================

    modifier onlyHook() {
        if (msg.sender != hook) revert Unauthorized();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != hook && msg.sender != tradeManager && !authorizedExecutors[msg.sender]) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyTradeManager() {
        if (msg.sender != tradeManager) revert Unauthorized();
        _;
    }

    // ========================================= CONSTRUCTOR =========================================

    constructor(address _hook, address _tradeManager, address _pythContract) {
        if (_hook == address(0)) revert ZeroAddress();
        if (_tradeManager == address(0)) revert ZeroAddress();
        if (_pythContract == address(0)) revert ZeroAddress();

        hook = _hook;
        tradeManager = _tradeManager;
        pyth = IPyth(_pythContract);

        // Initialize common stablecoin price feed IDs
        // USDC/USD price feed
        tokenPriceFeedIds[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
        // USDT/USD price feed
        tokenPriceFeedIds[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b;
        // DAI/USD price feed
        tokenPriceFeedIds[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 0xb0948a5e5313200c632b51bb5ca32f6de0d36e9950a942d19751e833f70dabfd;
    }

    // ========================================= EXTERNAL FUNCTIONS =========================================

    /**
     * @notice Deposit tokens from the hook (80% of liquidity) with USD-based accounting
     * @param token The token to deposit
     * @param amount The amount to deposit
     * @param priceUpdate The Pyth price update data
     */
    function deposit(
        address token,
        uint256 amount,
        bytes[] calldata priceUpdate
    ) external payable onlyHook nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (tokenPriceFeedIds[token] == bytes32(0)) revert PriceFeedNotSet();

        // Update Pyth price feeds
        uint fee = pyth.getUpdateFee(priceUpdate);
        pyth.updatePriceFeeds{ value: fee }(priceUpdate);

        // Get the current USD price of the token
        uint256 usdValue = getTokenValueInUSD(token, amount);

        // Transfer tokens from hook to this vault
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Update balance tracking
        tokenBalances[token] += amount;

        // Update USD-based shares
        userShares[msg.sender] += usdValue;
        totalSharesUSD += usdValue;

        emit Deposited(token, amount, usdValue, msg.sender);
    }

    /**
     * @notice Execute a strategy call through the vault
     * @param target The target contract to call
     * @param data The calldata for the call
     * @param value The ETH value to send with the call
     * @return result The return data from the call
     */
    function execute(
        address target,
        bytes calldata data,
        uint256 value
    ) external onlyAuthorized nonReentrant returns (bytes memory result) {
        // Make the external call
        result = target.functionCallWithValue(data, value);

        emit StrategyExecuted(target, data, value, result);
    }

    /**
     * @notice Execute multiple strategy calls in sequence
     * @param targets Array of target contracts
     * @param dataArray Array of calldata
     * @param values Array of ETH values
     * @return results Array of return data
     */
    function batchExecute(
        address[] calldata targets,
        bytes[] calldata dataArray,
        uint256[] calldata values
    ) external onlyAuthorized nonReentrant returns (bytes[] memory results) {
        uint256 length = targets.length;
        require(length == dataArray.length && length == values.length, "Length mismatch");

        results = new bytes[](length);

        for (uint256 i = 0; i < length; i++) {
            results[i] = targets[i].functionCallWithValue(dataArray[i], values[i]);
            emit StrategyExecuted(targets[i], dataArray[i], values[i], results[i]);
        }
    }

    /**
     * @notice Withdraw tokens based on USD share value
     * @param token The token to withdraw
     * @param usdAmount The USD value to withdraw
     * @param to The recipient address
     * @param priceUpdate The Pyth price update data
     */
    function withdraw(
        address token,
        uint256 usdAmount,
        address to,
        bytes[] calldata priceUpdate
    ) external payable onlyHook nonReentrant {
        if (userShares[msg.sender] < usdAmount) revert InsufficientShares();
        if (tokenPriceFeedIds[token] == bytes32(0)) revert PriceFeedNotSet();

        // Update Pyth price feeds
        uint fee = pyth.getUpdateFee(priceUpdate);
        pyth.updatePriceFeeds{ value: fee }(priceUpdate);

        // Calculate token amount based on USD value
        uint256 tokenAmount = getTokenAmountFromUSD(token, usdAmount);

        if (tokenBalances[token] < tokenAmount) revert InsufficientBalance();

        // Update USD shares
        userShares[msg.sender] -= usdAmount;
        totalSharesUSD -= usdAmount;

        // Update balance tracking
        tokenBalances[token] -= tokenAmount;

        // Transfer tokens
        IERC20(token).safeTransfer(to, tokenAmount);

        emit Withdrawn(token, tokenAmount, usdAmount, to);
    }

    /**
     * @notice Emergency withdraw function for trade manager
     * @dev Only callable by trade manager in case of emergency
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external onlyTradeManager nonReentrant {
        if (tokenBalances[token] < amount) revert InsufficientBalance();

        // Update balance tracking
        tokenBalances[token] -= amount;

        // Transfer tokens
        IERC20(token).safeTransfer(to, amount);

        emit EmergencyWithdraw(token, amount, to);
    }

    /**
     * @notice Update authorized executor status
     * @param executor The executor address
     * @param authorized Whether the executor is authorized
     */
    function setExecutor(address executor, bool authorized) external onlyTradeManager {
        authorizedExecutors[executor] = authorized;
        emit ExecutorUpdated(executor, authorized);
    }

    /**
     * @notice Get the current balance of a token in the vault
     * @param token The token address
     * @return The balance amount
     */
    function getBalance(address token) external view returns (uint256) {
        return tokenBalances[token];
    }

    /**
     * @notice Check if an address is authorized to execute
     * @param executor The address to check
     * @return Whether the address is authorized
     */
    function isAuthorized(address executor) external view returns (bool) {
        return executor == hook || executor == tradeManager || authorizedExecutors[executor];
    }

    /**
     * @notice Approve a token for spending by a protocol
     * @dev This is needed for the vault to interact with DeFi protocols
     * @param token The token to approve
     * @param spender The spender address
     * @param amount The amount to approve
     */
    function approveToken(
        address token,
        address spender,
        uint256 amount
    ) external onlyAuthorized {
        IERC20(token).safeApprove(spender, 0); // Reset to 0 first
        IERC20(token).safeApprove(spender, amount);
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}

    /**
     * @notice Fallback function
     */
    fallback() external payable {}

    // ========================================= PRICE FEED FUNCTIONS =========================================

    /**
     * @notice Set or update the price feed ID for a token
     * @param token The token address
     * @param feedId The Pyth price feed ID
     */
    function setPriceFeedId(address token, bytes32 feedId) external onlyTradeManager {
        tokenPriceFeedIds[token] = feedId;
        emit PriceFeedIdSet(token, feedId);
    }

    /**
     * @notice Get the USD value of a token amount
     * @param token The token address
     * @param amount The token amount
     * @return The USD value (scaled to 18 decimals)
     */
    function getTokenValueInUSD(address token, uint256 amount) public view returns (uint256) {
        bytes32 feedId = tokenPriceFeedIds[token];
        if (feedId == bytes32(0)) revert PriceFeedNotSet();

        PythStructs.Price memory price = pyth.getPriceNoOlderThan(feedId, PRICE_STALENESS_THRESHOLD);

        // Get token decimals (assuming standard ERC20 with decimals())
        uint8 tokenDecimals = IERC20Metadata(token).decimals();

        // Convert price to 18 decimals for consistent math
        // Pyth prices have their own exponent, need to handle carefully
        int32 priceExponent = price.expo;
        uint64 priceValue = price.price;

        // Calculate USD value: amount * price / 10^tokenDecimals
        // Adjust for price exponent and normalize to 18 decimals
        uint256 usdValue;
        if (priceExponent >= 0) {
            usdValue = (amount * priceValue * (10 ** uint32(priceExponent)) * 1e18) / (10 ** tokenDecimals);
        } else {
            uint32 absExponent = uint32(-priceExponent);
            usdValue = (amount * priceValue * 1e18) / (10 ** tokenDecimals * 10 ** absExponent);
        }

        return usdValue;
    }

    /**
     * @notice Get the token amount for a given USD value
     * @param token The token address
     * @param usdAmount The USD amount (18 decimals)
     * @return The token amount
     */
    function getTokenAmountFromUSD(address token, uint256 usdAmount) public view returns (uint256) {
        bytes32 feedId = tokenPriceFeedIds[token];
        if (feedId == bytes32(0)) revert PriceFeedNotSet();

        PythStructs.Price memory price = pyth.getPriceNoOlderThan(feedId, PRICE_STALENESS_THRESHOLD);

        // Get token decimals
        uint8 tokenDecimals = IERC20Metadata(token).decimals();

        // Convert price to handle exponent
        int32 priceExponent = price.expo;
        uint64 priceValue = price.price;

        // Calculate token amount: usdAmount / price * 10^tokenDecimals
        uint256 tokenAmount;
        if (priceExponent >= 0) {
            tokenAmount = (usdAmount * (10 ** tokenDecimals)) / (priceValue * (10 ** uint32(priceExponent)) * 1e18);
        } else {
            uint32 absExponent = uint32(-priceExponent);
            tokenAmount = (usdAmount * (10 ** tokenDecimals) * (10 ** absExponent)) / (priceValue * 1e18);
        }

        return tokenAmount;
    }

    /**
     * @notice Get user's USD share value
     * @param user The user address
     * @return The USD value of user's shares
     */
    function getUserSharesUSD(address user) external view returns (uint256) {
        return userShares[user];
    }

    /**
     * @notice Get total USD value in vault
     * @return The total USD value
     */
    function getTotalValueUSD() external view returns (uint256) {
        return totalSharesUSD;
    }
}