// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "./interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract StableStake is Ownable, AccessControl, ReentrancyGuard {
  using SafeERC20 for IERC20;

  struct UserData {
    DepositEntity[] deposits;
    uint256 affiliateInterests;
    uint256 affiliateCount;
    address sponsor;
  }

  // Deposit entities: one particular deposit, of a given size and type (see types below)
  struct DepositEntity {
    uint256 depositType;
    uint256 depositSize; // How many stablecoin tokens (e18)
    uint256 creationTime;
    uint256 lastClaimTime;
  }

  // Deoposit types: mutable, describe the interests given by each DepositEntity
  struct DepositType {
    uint256 depositType;
    uint256 lockPeriod; // Deposit cannot be withdrawn before the end of this period
    uint256 minimalDeposit;
    uint256 multiplier; // (/1000) - Example: 100 means a 10% per month ROI
    uint256 interestInterval; // Interests
  }

  mapping(address => UserData) private _users;
  mapping(uint256 => DepositType) private _depositTypes;
  mapping(address => bool) private _exemptFromFees;
  mapping(address => bool) private _isBlacklisted;

  uint256 public constant MAXIMUM_DEPOSITS_PER_ACCOUNT = 100; // Here to avoid cashout fails

  // IUniswapV2Router02 public dexRouter;
  IERC20 public supportedToken;

  address payable public investmentWallet; // The safe that stores the USDC from the deposits
  address payable public feesWallet; // The safe that stores the USDC from the fees

  uint256 public totalDepositTypes = 0;
  uint256 public totalDepositsCreated = 0;
  uint256 public totalDepositedAmount = 0;
  uint256 public totalEarnedAmount = 0;

  // DAO: open or close deposits and withdrawals
  bool public isDepositCreationPaused = false; // If set to true, no deposits can be created
  bool public isCashoutPaused = false; // If set to true, no interests can be claimed + no deposits can be withdawn

  // Fees: distributed between fees wallet (createDepositFee) and the investment wallet (what's left)
  uint256 private createDepositFee = 0; // Funds collected when creating a deposit (/1000) for fees wallet - Defaut: 0%
  uint256 private feeBalance = 0;
  uint256 private minimumFeeBalanceToSend = 100e18; // Threshold to send tokens made from fees to fees wallet (default: $USDC 100)

  uint256 private sponsorFee = 250; // Percentage of the depositSize that is also added to sponsor's balance (/1000) - cannot be claimed before 30 days - (/1000)
  uint256 private cashoutFee = 50; // Fee collected when cashing out a deposit (/1000)
  uint256 private vestingPeriodOfAffiliateInterests; // An user cannot claim his affiliate interests before this amount of time after his 1st deposit (90 days)

  uint256 private maximumFirstDepositAmount = 10_000e18; // USD 10k
  uint256 private maximumDepositAmount = 100_000e18; // USD 100k

  // // Swapping booleans. Here to avoid having two swaps in the same block
  // bool private swapping = false;

  // Events
  event DepositEntityCreated(address account, uint256 depositType, uint256 depositSize, uint256 creationTime);
  event DepositTypeUpdated(
    uint256 depositType,
    uint256 lockPeriod,
    uint256 multiplier,
    uint256 interestInterval,
    uint256 depositInterestPerPeriod
  );
  event DepositTypeDeleted(uint256 depositType);
  event SupportedTokenClaimed(address account, uint256 amount, uint256 claimTime);
  event SupportedTokenCompounded(address account, uint256 depositIndex, uint256 amount, uint256 compoundTime);
  event SentFeeBalance(uint256 amount);

  constructor(
    address payable _feesWallet,
    address payable _investmentWallet,
    address _supportedTokenAddress,
    uint256 _initialInterval,
    uint256 _initialVestingPeriodOfAffiliateInterests
  ) {
    feesWallet = _feesWallet;
    investmentWallet = _investmentWallet;
    supportedToken = IERC20(_supportedTokenAddress);
    // dexRouter = IUniswapV2Router02(_dexRouter);
    _exemptFromFees[msg.sender] = true;

    // Initial deposit types:
    // Minimal investment: USD 50
    // ROI: 12% per month
    // Lock period: 30 days

    // Add initial deposit types
    _createNewDepositType(_initialInterval, 50e18, 120, _initialInterval);

    // Affiliate interests are vested for 90 days
    vestingPeriodOfAffiliateInterests = _initialVestingPeriodOfAffiliateInterests;
  }

  receive() external payable {}

  /* 1. EXTERNAL FUNCTIONS - callable by users to deposit, withdraw and compound */

  // 1.1 - Related to deposit creation

  // Standard function for creating a deposit - requires the sender to pay a certain amount of supported token
  function createDepositWithTokens(
    uint256 _depositSize,
    uint256 _depositType,
    address _sponsor
  ) external nonReentrant {
    // Checks
    require(!isDepositCreationPaused, "Deposit creation is paused");
    require(!_isBlacklisted[msg.sender], "User is blacklisted");
    require(_sponsor != msg.sender, "Cannot be your own sponsor");
    require(_depositSize >= _depositTypes[_depositType].minimalDeposit, "Deposit size is too low");

    // Make sure deposit size does not exceed the limits
    if (_users[msg.sender].deposits.length == 0) {
      require(_depositSize < maximumFirstDepositAmount, "Deposit size exceeds maximum first deposit amount");
    } else {
      require(_depositSize < maximumDepositAmount, "Deposit size exceeds maximum deposit amount");
    }

    // Transfer tokens and swap if needed
    _processSupportedTokenFromDepositCreation(_depositSize);

    // User does not have a sponsor yet + _sponsor is a non blacklisted address: add new sponsor and handle bonus (only for 1st deposit)
    if (
      _users[msg.sender].sponsor == address(0) &&
      _sponsor != address(0) &&
      !_isBlacklisted[_sponsor] &&
      _users[msg.sender].deposits.length == 0
    ) {
      // Security check
      require(msg.sender != _users[_sponsor].sponsor, "Cannot be your sponsor's sponsor");
      // Handle sponsor address
      _users[msg.sender].sponsor = _sponsor;
      // Handle sponsor affiliate count
      _users[_sponsor].affiliateCount++;
      // Handle sponsor bonus
      _users[_sponsor].affiliateInterests += (_depositSize * sponsorFee) / 1000;
    }
    // Other cases:
    // - _sponsor is address(0): Do nothing
    // - User already has a sponsor: He already gave a bonus to his sponsor during his 1st deposit. Do nothing

    // Create a normal deposit entity
    _createDeposit(msg.sender, _depositType, _depositSize);
  }

  // 1.2 - Related to deposit cashout

  function cashoutAllDeposits() external nonReentrant {
    require(!isCashoutPaused, "Cashouts are paused");
    require(!_isBlacklisted[msg.sender], "User is blacklisted");
    DepositEntity[] memory deposits = _users[msg.sender].deposits;
    require(deposits.length > 0, "No deposit to cashout");

    // Count the sum of all deposit sizes to make sure a cashout is relevant
    // Note: Only cashout deposits for which lock period is over
    uint256 totalDepositValueAvailable = 0;
    
    for (uint256 i = 0; i < deposits.length; i++) {
      if (block.timestamp - deposits[0].creationTime > _depositTypes[deposits[i].depositType].lockPeriod) {
        totalDepositValueAvailable += deposits[i].depositSize;
        // Update storage data - delete deposit
        _users[msg.sender].deposits[i].lastClaimTime = block.timestamp;
        _users[msg.sender].deposits[i].depositSize = 0;
      }
    }

    // Also cashout affiliate interests (only if vesting period is over)
    if (block.timestamp - deposits[0].creationTime > vestingPeriodOfAffiliateInterests) {
      totalDepositValueAvailable += _users[msg.sender].affiliateInterests;
      _users[msg.sender].affiliateInterests = 0;
    }

    require(totalDepositValueAvailable > 0, "Nothing to cashout");

    // Cashout previously stored value of supported tokens - process cashout fees
    if (_exemptFromFees[msg.sender]) {
      // No fees: simple cashout
      _cashout(totalDepositValueAvailable);
    } else {
      // Calculate cashout fee
      uint256 fee = (totalDepositValueAvailable * cashoutFee) / 1000;
      uint256 toSend = totalDepositValueAvailable - fee;

      // Add fee to balance
      feeBalance += fee;
      if (feeBalance > minimumFeeBalanceToSend) {
        _sendFeeBalance();
      }

      // Cashout
      _cashout(toSend);
    }
  }

  function cashoutDeposit(uint256 _depositIndex) external nonReentrant {
    // Checks
    require(!isCashoutPaused, "Cashouts are paused");
    require(!_isBlacklisted[msg.sender], "User is blacklisted");
    DepositEntity memory deposit = _users[msg.sender].deposits[_depositIndex];
    require(
      _depositIndex < _users[msg.sender].deposits.length,
      "Trying to cashout a deposit that does not exist"
    );
    require(
      block.timestamp >
        _users[msg.sender].deposits[0].creationTime + _depositTypes[deposit.depositType].lockPeriod,
      "Cannot cashout deposit before the end of lock period"
    );

    // Store the amount to cashout before updating storage data
    uint256 depositValueAvailable = deposit.depositSize;
    require(depositValueAvailable > 0, "Nothing to cashout");

    // Update storage data - delete deposit
    _users[msg.sender].deposits[_depositIndex].lastClaimTime = block.timestamp;
    _users[msg.sender].deposits[_depositIndex].depositSize = 0;

    // Cashout previously stored value of supported tokens - process cashout fees
    if (_exemptFromFees[msg.sender]) {
      // No fees: simple cashout
      _cashout(depositValueAvailable);
    } else {
      // Calculate cashout fee
      uint256 fee = (depositValueAvailable * cashoutFee) / 1000;
      uint256 toSend = depositValueAvailable - fee;

      // Add fee to balance
      feeBalance += fee;
      if (feeBalance > minimumFeeBalanceToSend) {
        _sendFeeBalance();
      }

      // Cashout
      _cashout(toSend);
    }
  }

  // 1.3 - Related to interests cashout

  // Claimable interests for each deposit will be sent to the user in the appropriate supported token
  function cashoutAllInterests() external nonReentrant {
    require(!isCashoutPaused, "Cashouts are paused");
    require(!_isBlacklisted[msg.sender], "User is blacklisted");
    DepositEntity[] memory deposits = _users[msg.sender].deposits;
    require(deposits.length > 0, "No deposit to cashout interests from");

    // Count the sum of all deposit sizes to make sure a cashout is relevant
    uint256 totalInterestValueAvailable = 0;
    for (uint256 i = 0; i < deposits.length; i++) {
      // Only cashout interests from deposits that have claimable interests
      if (
        block.timestamp - deposits[i].lastClaimTime > _depositTypes[deposits[i].depositType].interestInterval
      ) {
        // Adds interest value available
        totalInterestValueAvailable += _calcDepositInterestAvailable(deposits[i]);
        // Update storage data - updates last claim time
        _users[msg.sender].deposits[i].lastClaimTime = _calcNewLastClaimTime(deposits[i]);
      }
    }

    require(totalInterestValueAvailable > 0, "Nothing to cashout");

    // Cashout previously stored value of supported tokens - process cashout fees
    if (_exemptFromFees[msg.sender]) {
      // No fees: simple cashout
      _cashout(totalInterestValueAvailable);
    } else {
      // Calculate cashout fee
      uint256 fee = (totalInterestValueAvailable * cashoutFee) / 1000;
      uint256 toSend = totalInterestValueAvailable - fee;

      // Add fee to balance
      feeBalance += fee;
      if (feeBalance > minimumFeeBalanceToSend) {
        _sendFeeBalance();
      }

      // Cashout
      _cashout(toSend);
    }
  }

  // Cashout a single deposit's interests
  function cashoutInterest(uint256 _depositIndex) external nonReentrant {
    require(!isCashoutPaused, "Cashouts are paused");
    require(!_isBlacklisted[msg.sender], "User is blacklisted");
    require(
      _depositIndex < _users[msg.sender].deposits.length,
      "Trying to cashout interests from a deposit that does not exist"
    );
    DepositEntity storage deposit = _users[msg.sender].deposits[_depositIndex];

    uint256 interestAvailable = _getDepositInterestAvailable(_users[msg.sender].deposits[_depositIndex]);
    require(interestAvailable > 0, "Nothing to cashout");

    _users[msg.sender].deposits[_depositIndex].lastClaimTime = _getNewLastClaimTime(deposit);

    // Cashout previously stored value of supported tokens - process cashout fees
    if (_exemptFromFees[msg.sender]) {
      // No fees: simple cashout
      _cashout(interestAvailable);
    } else {
      // Calculate cashout fee
      uint256 fee = (interestAvailable * cashoutFee) / 1000;
      uint256 toSend = interestAvailable - fee;

      // Add fee to balance
      feeBalance += fee;
      if (feeBalance > minimumFeeBalanceToSend) {
        _sendFeeBalance();
      }

      // Cashout
      _cashout(toSend);
    }
  }

  // Cashout a deposit's available interests and directly reinvest them by increasing the deposit's size
  // Note: No fees
  function cashoutAndCompound(uint256 _depositIndex) external nonReentrant {
    require(!_isBlacklisted[msg.sender], "User is blacklisted");

    DepositEntity storage deposit = _users[msg.sender].deposits[_depositIndex];

    uint256 interestAvailable = _getDepositInterestAvailable(_users[msg.sender].deposits[_depositIndex]);
    require(interestAvailable > 0, "Nothing to compound");

    // Update last claim time
    deposit.lastClaimTime = _getNewLastClaimTime(deposit);

    // Handle compound
    _compound(_depositIndex, interestAvailable);
  }

  // Compound all deposits (only the ones with available interests)
  function cashoutAndCompoundAll() external nonReentrant {
    require(!_isBlacklisted[msg.sender], "User is blacklisted");
    DepositEntity[] storage deposits = _users[msg.sender].deposits;
    require(deposits.length > 0, "No deposit to compound");

    // Count the sum of all deposit sizes to make sure a cashout and compound is relevant
    uint256 totalInterestValueAvailable = 0;
    for (uint256 i = 0; i < deposits.length; i++) {
      // Only cashout interests from deposits that have claimable interests
      if (
        block.timestamp - deposits[i].lastClaimTime > _depositTypes[deposits[i].depositType].interestInterval
      ) {
        totalInterestValueAvailable += _calcDepositInterestAvailable(deposits[i]);
        // Update storage data - reset last claim time
        deposits[i].lastClaimTime = _calcNewLastClaimTime(deposits[i]);
      }
    }

    require(totalInterestValueAvailable > 0, "Nothing to compound");

    // Handle compound - update 1st deposit
    _compound(0, totalInterestValueAvailable);
  }

  // Compound affiliate interests - only if user has a deposit older than the lock period for affiliate interests
  function compoundAffiliateInterests() external nonReentrant {
    // Checks
    require(!_isBlacklisted[msg.sender], "User is blacklisted");
    require(
      _users[msg.sender].deposits.length > 0,
      "Cannot compound affiliate interests: user does not have any deposit"
    );
    require(
      block.timestamp - _users[msg.sender].deposits[0].creationTime > vestingPeriodOfAffiliateInterests,
      "Cannot compound affiliate interests before the end of lock period"
    );

    // Store the amount to compound before updating storage data
    uint256 affiliateInterestValueAvailable = _users[msg.sender].affiliateInterests;
    require(affiliateInterestValueAvailable > 0, "Nothing to cashout");

    // Handle compound - update 1st deposit
    _compound(0, affiliateInterestValueAvailable);

    // Reset affiliate interests
    _users[msg.sender].affiliateInterests = 0;
  }

  /* 2. INTERNAL FUNCTIONS */

  // 2.1 - Related to deposits and interests

  function _createDeposit(
    address _account,
    uint256 _depositType,
    uint256 _depositSize
  ) internal {
    require(
      _users[_account].deposits.length < MAXIMUM_DEPOSITS_PER_ACCOUNT,
      "Maximum number of deposits reached for this account"
    );
    require(
      _depositType < totalDepositTypes,
      "Trying to create a deposit of a deposit type that does not exist"
    );
    require(_depositSize > 0, "Cannot create a deposit with a size of 0");

    _users[_account].deposits.push(
      DepositEntity({
        depositType: _depositType,
        depositSize: _depositSize,
        creationTime: block.timestamp,
        lastClaimTime: block.timestamp
      })
    );
    totalDepositsCreated++;
    totalDepositedAmount += _depositType;

    emit DepositEntityCreated(_account, _depositType, _depositSize, block.timestamp);
  }

  // Cashout - no cashout fees
  function _cashout(uint256 _amount) internal {
    require(!isCashoutPaused, "Cashouts are paused");
    require(_amount > 0, "Cannot cashout 0 supported token");

    // Transfer supported tokens to the user
    supportedToken.transfer(msg.sender, _amount);

    totalEarnedAmount += _amount;

    emit SupportedTokenClaimed(msg.sender, _amount, block.timestamp);
  }

  // Compound
  function _compound(uint256 _depositIndex, uint256 _amount) internal {
    require(_amount > 0, "Cannot compound 0 supported token");

    // Update deposit entity
    _users[msg.sender].deposits[_depositIndex].depositSize += _amount;

    emit SupportedTokenCompounded(msg.sender, _depositIndex, _amount, block.timestamp);
  }

  // Returns the time before next interest is available for a deposit
  function _getTimeUntilNextInterest(DepositEntity memory _deposit) internal view returns (uint256) {
    uint256 _depositType = _deposit.depositType;
    uint256 interval = _depositTypes[_depositType].interestInterval;
    uint256 lastClaimTime = _deposit.lastClaimTime;
    uint256 sinceLastClaim = block.timestamp - lastClaimTime;

    uint256 incompletePeriod = 0;

    if (sinceLastClaim > interval) {
      incompletePeriod = sinceLastClaim % interval;
    } else incompletePeriod = sinceLastClaim;

    return interval - incompletePeriod;
  }

  // Peforms a safety check, then returns the amount of interests available for a deposit
  function _getDepositInterestAvailable(DepositEntity memory _deposit) internal view returns (uint256) {
    if (block.timestamp - _deposit.lastClaimTime > _depositTypes[_deposit.depositType].interestInterval) {
      return _calcDepositInterestAvailable(_deposit);
    }
    return 0;
  }

  // Returns the amount of interests available for a deposit
  function _calcDepositInterestAvailable(DepositEntity memory _deposit) internal view returns (uint256) {
    uint256 _depositType = _deposit.depositType;
    require(
      _depositTypes[_depositType].interestInterval > 0,
      "The deposit interval of this deposit type is 0"
    );
    require(_depositTypes[_depositType].multiplier > 0, "The deposit multiplier of this deposit type is 0");

    // Math: since last claim / interval * interest per period (which is depositSize * multiplier)
    return
      (((block.timestamp - _deposit.lastClaimTime) / _depositTypes[_depositType].interestInterval) *
        _deposit.depositSize *
        _depositTypes[_depositType].multiplier) / 1000;
  }

  // Peforms a safety check, then returns the last claim time for a deposit
  function _getNewLastClaimTime(DepositEntity memory _deposit) internal view returns (uint256) {
    if (block.timestamp - _deposit.lastClaimTime > _depositTypes[_deposit.depositType].interestInterval) {
      return _calcNewLastClaimTime(_deposit);
    }
    // If less than one period since last claim time: don't update last claim time
    return _deposit.lastClaimTime;
  }

  function _calcNewLastClaimTime(DepositEntity memory _deposit) internal view returns (uint256) {
    uint256 depositType = _deposit.depositType;
    uint256 interval = _depositTypes[depositType].interestInterval;
    require(interval > 0, "The deposit interval of this deposit type is 0");
    uint256 lastClaimTime = _deposit.lastClaimTime;

    // Logic: (since last claim - incomplete period) / interval
    uint256 numberOfFullPeriodsTimesInterval = ((block.timestamp - lastClaimTime) -
      ((block.timestamp - lastClaimTime) % interval));

    // Logic: newLastClaim = lastClaimTime + numberOfFullPeriods * interval
    return lastClaimTime + numberOfFullPeriodsTimesInterval;
  }

  // 2.2 - Related to payments and supported tokens

  // Handles a transfer of "_amount" supported tokens to the contract when creating a deposit, collects fees and swaps to BNB if appropriate
  function _processSupportedTokenFromDepositCreation(uint256 _amount) internal {
    require(supportedToken.balanceOf(msg.sender) >= _amount, "Supported token balance too low");
    require(_amount > 0, "Cannot transfer 0 supported tokens");

    // Calculate amount to invest and fees
    uint256 fees = (_amount * createDepositFee) / 1000;

    // Send to investment wallet
    supportedToken.safeTransferFrom(msg.sender, investmentWallet, _amount);

    // Deposit creation fee
    feeBalance += fees;

    // Send fees
    if (feeBalance > minimumFeeBalanceToSend) {
      _sendFeeBalance();
    }
  }

  // Sends fees to the fees wallet
  function _sendFeeBalance() internal {
    require(feeBalance > 0, "Not enough supported tokens in fee balance to send to fees wallet");

    // Send USDC to fees wallet
    supportedToken.transfer(feesWallet, feeBalance);

    emit SentFeeBalance(feeBalance);

    // Update feeBalance
    feeBalance = 0;
  }

  // Creates a new deposit type
  function _createNewDepositType(
    uint256 _lockPeriod,
    uint256 _minimalDeposit,
    uint256 _multiplier,
    uint256 _interestInterval
  ) internal {
    _depositTypes[totalDepositTypes] = DepositType(
      totalDepositTypes,
      _lockPeriod,
      _minimalDeposit,
      _multiplier,
      _interestInterval
    );

    emit DepositTypeUpdated(totalDepositTypes, _lockPeriod, _minimalDeposit, _multiplier, _interestInterval);

    totalDepositTypes++;
  }

  /* 3. VIEW FUNCTIONS */

  // 3.1 - Related to available interests

  // Returns the amount of interests available for a given account (all deposits combined)
  function getAccountInterestAvailable(address _account) external view returns (uint256) {
    DepositEntity[] memory deposits = _users[_account].deposits;
    uint256 interestAvailable = 0;
    for (uint256 i = 0; i < deposits.length; i++) {
      if (
        block.timestamp - deposits[i].lastClaimTime > _depositTypes[deposits[i].depositType].interestInterval
      ) {
        interestAvailable += _getDepositInterestAvailable(deposits[i]);
      }
    }
    return interestAvailable;
  }

  // Returns the amount of interests available for a given account (for each deposit)
  function getAccountInterestAvailableAsArray(address _account) external view returns (uint256[] memory) {
    DepositEntity[] memory deposits = _users[_account].deposits;
    uint256 numberOfDeposits = deposits.length;
    uint256[] memory interestsAvailable = new uint256[](numberOfDeposits);

    for (uint256 i = 0; i < numberOfDeposits; i++) {
      if (
        block.timestamp - deposits[i].lastClaimTime > _depositTypes[deposits[i].depositType].interestInterval
      ) {
        interestsAvailable[i] = _getDepositInterestAvailable(deposits[i]);
      } else {
        interestsAvailable[i] = 0;
      }
    }
    return interestsAvailable;
  }

  function getDepositInterestAvailable(address _account, uint256 _depositIndex)
    external
    view
    returns (uint256)
  {
    return _getDepositInterestAvailable(_users[_account].deposits[_depositIndex]);
  }

  // 3.2 - Related to deposits

  // Returns the deposited value for a given account (all deposits combined)
  function getAccountDepositedValue(address _account) external view returns (uint256) {
    DepositEntity[] memory deposits = _users[_account].deposits;
    uint256 depositedValue = 0;
    for (uint256 i = 0; i < deposits.length; i++) {
      depositedValue += deposits[i].depositSize;
    }
    return depositedValue;
  }

  function getDeposit(address _account, uint256 _depositIndex) external view returns (DepositEntity memory) {
    return _users[_account].deposits[_depositIndex];
  }

  function getDepositCount(address _account) external view returns (uint256) {
    return _users[_account].deposits.length;
  }

  function getTotalDepositsCreated() external view returns (uint256) {
    return totalDepositsCreated;
  }

  function getTotalDepositedAmount() external view returns (uint256) {
    return totalDepositedAmount;
  }

  function getTotalEarnedAmount() external view returns (uint256) {
    return totalEarnedAmount;
  }

  // 3.3 - Related to deposit types

  // 3.3.1 - Lock periods

  // Returns the lock periods for each deposit type
  function getLockPeriods() external view returns (uint256[] memory) {
    uint256[] memory lockPeriods = new uint256[](totalDepositTypes);

    for (uint256 i = 0; i < totalDepositTypes; i++) {
      lockPeriods[i] = getLockPeriod(i);
    }

    return lockPeriods;
  }

  function getLockPeriod(uint256 _depositType) public view returns (uint256) {
    return _depositTypes[_depositType].lockPeriod;
  }

  // 3.3.2 - Interest intervals

  // Returns the deposit intervals for each deposit type
  function getInterestIntervals() external view returns (uint256[] memory) {
    uint256[] memory interestIntervals = new uint256[](totalDepositTypes);

    for (uint256 i = 0; i < totalDepositTypes; i++) {
      interestIntervals[i] = getInterestInterval(i);
    }

    return interestIntervals;
  }

  function getInterestInterval(uint256 _depositType) public view returns (uint256) {
    return _depositTypes[_depositType].interestInterval;
  }

  // 3.3.3 - Multipliers

  // Returns the multipliers for each deposit type
  function getMultipliers() external view returns (uint256[] memory) {
    uint256[] memory multipliers = new uint256[](totalDepositTypes);

    for (uint256 i = 0; i < totalDepositTypes; i++) {
      multipliers[i] = getMultiplier(i);
    }

    return multipliers;
  }

  function getMultiplier(uint256 _depositType) public view returns (uint256) {
    return _depositTypes[_depositType].multiplier;
  }

  // 3.3.4 - Account's deposit types

  function getAccountTypes(address _account) external view returns (uint256[] memory) {
    DepositEntity[] memory deposits = _users[_account].deposits;
    uint256 numberOfDeposits = deposits.length;
    uint256[] memory depositTypes = new uint256[](numberOfDeposits);

    for (uint256 i = 0; i < numberOfDeposits; i++) {
      depositTypes[i] = deposits[i].depositType;
    }

    return depositTypes;
  }

  function getDepositType(address _account, uint256 _depositIndex) external view returns (uint256) {
    return _users[_account].deposits[_depositIndex].depositType;
  }

  // 3.4 - Related to deposit entities

  // 3.4.1 - Creation times

  function getAccountCreationTimes(address _account) external view returns (uint256[] memory) {
    DepositEntity[] memory deposits = _users[_account].deposits;
    uint256 numberOfDeposits = deposits.length;
    uint256[] memory creationTimes = new uint256[](numberOfDeposits);

    for (uint256 i = 0; i < numberOfDeposits; i++) {
      creationTimes[i] = deposits[i].creationTime;
    }

    return creationTimes;
  }

  function getDepositCreationTime(address _account, uint256 _depositIndex) external view returns (uint256) {
    return _users[_account].deposits[_depositIndex].creationTime;
  }

  // 3.4.2 Unlock time

  function getAccountUnlockTime(address _account) external view returns (uint256) {
    if (
      _users[_account].deposits.length > 0 &&
      _users[_account].deposits[0].creationTime + getLockPeriod(_users[_account].deposits[0].depositType) >
      block.timestamp
    ) {
      return
        _users[_account].deposits[0].creationTime + getLockPeriod(_users[_account].deposits[0].depositType);
    } else return 0;
  }

  function getTimeUntilAccountUnlockTime(address _account) external view returns (uint256) {
    if (
      _users[_account].deposits.length > 0 &&
      _users[_account].deposits[0].creationTime + getLockPeriod(_users[_account].deposits[0].depositType) >
      block.timestamp
    ) {
      return
        _users[_account].deposits[0].creationTime +
        getLockPeriod(_users[_account].deposits[0].depositType) -
        block.timestamp;
    } else return 0;
  }

  function getIsAccountUnlocked(address _account) external view returns (bool) {
    return (_users[_account].deposits.length > 0 &&
      _users[_account].deposits[0].creationTime + getLockPeriod(_users[_account].deposits[0].depositType) <
      block.timestamp);
  }

  // 3.4.3 Affiliate rewards unlock time

  function getAccountAffiliateRewardsUnlockTime(address _account) external view returns (uint256) {
    if (
      _users[_account].deposits.length > 0 &&
      _users[_account].deposits[0].creationTime + vestingPeriodOfAffiliateInterests > block.timestamp
    ) {
      return _users[_account].deposits[0].creationTime + vestingPeriodOfAffiliateInterests;
    } else return 0;
  }

  function getTimeUntilAccountAffiliateRewardsUnlockTime(address _account) external view returns (uint256) {
    if (
      _users[_account].deposits.length > 0 &&
      _users[_account].deposits[0].creationTime + vestingPeriodOfAffiliateInterests > block.timestamp
    ) {
      return _users[_account].deposits[0].creationTime + vestingPeriodOfAffiliateInterests - block.timestamp;
    } else return 0;
  }

  function getIsAccountAffiliateRewardsUnlocked(address _account) external view returns (bool) {
    return (_users[_account].deposits.length > 0 &&
      _users[_account].deposits[0].creationTime + vestingPeriodOfAffiliateInterests < block.timestamp);
  }

  // 3.4.4 - Next claim times

  // Returns the next claim times for a given account (for each deposit)
  function getAccountNextInterestTimes(address _account) external view returns (uint256[] memory) {
    DepositEntity[] memory deposits = _users[_account].deposits;
    uint256 numberOfDeposits = deposits.length;
    uint256[] memory nextInterestTimes = new uint256[](numberOfDeposits);

    for (uint256 i = 0; i < numberOfDeposits; i++) {
      nextInterestTimes[i] = _getTimeUntilNextInterest(deposits[i]);
    }
    return nextInterestTimes;
  }

  // 3.4.5 - Last claim times

  function getAccountLastClaimTimes(address _account) external view returns (uint256[] memory) {
    DepositEntity[] memory deposits = _users[_account].deposits;
    uint256 numberOfDeposits = deposits.length;
    uint256[] memory lastClaimTimes = new uint256[](numberOfDeposits);

    for (uint256 i = 0; i < numberOfDeposits; i++) {
      lastClaimTimes[i] = deposits[i].lastClaimTime;
    }

    return lastClaimTimes;
  }

  function getDepositLastClaimTime(address _account, uint256 _depositIndex) external view returns (uint256) {
    return _users[_account].deposits[_depositIndex].lastClaimTime;
  }

  // 3.4.6 - Deposit sizes

  function getAccountDepositSizes(address _account) external view returns (uint256[] memory) {
    DepositEntity[] memory deposits = _users[_account].deposits;
    uint256 numberOfDeposits = deposits.length;
    uint256[] memory depositSizes = new uint256[](numberOfDeposits);

    for (uint256 i = 0; i < numberOfDeposits; i++) {
      depositSizes[i] = deposits[i].depositSize;
    }

    return depositSizes;
  }

  // 3.5 - Related to affiliates

  // Returns affiliate interests
  function getAffiliateInterestsAvailable(address _account) external view returns (uint256) {
    return _users[_account].affiliateInterests;
  }

  function getAffiliateInterestsAvailability(address _account) external view returns (bool) {
    return block.timestamp - _users[_account].deposits[0].creationTime > vestingPeriodOfAffiliateInterests;
  }

  function getAffiliateCount(address _account) external view returns (uint256) {
    return _users[_account].affiliateCount;
  }

  // 3.7 - Blacklist

  function isBlacklisted(address _address) external view returns (bool) {
    return _isBlacklisted[_address];
  }

  /* 4. DAO FUNCTIONS - callable by owner only */

  // 4.1 - Related to deposit types

  function createNewDepositType(
    uint256 _lockPeriod,
    uint256 _minimalDeposit,
    uint256 _multiplier,
    uint256 _interestInterval
  ) external onlyOwner {
    _createNewDepositType(_lockPeriod, _minimalDeposit, _multiplier, _interestInterval);
  }

  // Remove the last deposit type from the list
  function removeDepositType() external onlyOwner {
    require(totalDepositTypes > 0, "No deposit types to remove");
    updateDepositType(totalDepositTypes - 1, 0, 0, 0, 0);
    totalDepositTypes--;

    emit DepositTypeDeleted(totalDepositTypes);
  }

  function updateDepositType(
    uint256 _depositType,
    uint256 _lockPeriod,
    uint256 _minimalDeposit,
    uint256 _multiplier,
    uint256 _interestInterval
  ) public onlyOwner {
    require(_depositType < totalDepositTypes, "Trying to update a deposit type that does not exist");
    _depositTypes[_depositType] = DepositType(
      _depositType,
      _lockPeriod,
      _minimalDeposit,
      _multiplier,
      _interestInterval
    );

    emit DepositTypeUpdated(_depositType, _lockPeriod, _minimalDeposit, _multiplier, _interestInterval);
  }

  // 4.2 - Related to updating deposit entities (note: dangerous functions; use carefully)

  function updateDepositSize(
    address _account,
    uint256 _depositIndex,
    uint256 _depositSize
  ) external onlyOwner {
    _users[_account].deposits[_depositIndex].depositSize = _depositSize;
  }

  function updateDepositLastClaimTime(
    address _account,
    uint256 _depositIndex,
    uint256 _lastClaimTime
  ) external onlyOwner {
    require(
      _lastClaimTime > _users[_account].deposits[_depositIndex].creationTime,
      "Last claim time cannot be before creation time"
    );
    _users[_account].deposits[_depositIndex].lastClaimTime = _lastClaimTime;
  }

  // 4.3 - Related to airdrops

  function airdropDeposit(
    address _account,
    uint256 _depositType,
    uint256 _depositSize
  ) external onlyOwner {
    _createDeposit(_account, _depositType, _depositSize);
  }

  // Directly create deposits in batch for "_accounts", all with the same type and size for interests
  function airdropDeposits(
    address[] memory _accounts,
    uint256 _depositType,
    uint256 _depositSize
  ) external onlyOwner {
    for (uint256 i = 0; i < _accounts.length; i++) {
      _createDeposit(_accounts[i], _depositType, _depositSize);
    }
  }

  function airdropAffiliateInterest(address _account, uint256 _affiliateInterests) external onlyOwner {
    _users[_account].affiliateInterests += _affiliateInterests;
  }

  function airdropAffiliateInterests(address[] memory _accounts, uint256 _affiliateInterests)
    external
    onlyOwner
  {
    for (uint256 i = 0; i < _accounts.length; i++) {
      _users[_accounts[i]].affiliateInterests += _affiliateInterests;
    }
  }

  // 4.4 - Related to fees

  function exemptAddressFromFees(address _address, bool _bool) external onlyOwner {
    _exemptFromFees[_address] = _bool;
  }

  function setCreateDepositFee(uint256 _createDepositFee) external onlyOwner {
    createDepositFee = _createDepositFee;
  }

  function setMinimumFeeBalanceToSend(uint256 _minimumFeeBalanceToSend) external onlyOwner {
    minimumFeeBalanceToSend = _minimumFeeBalanceToSend;
  }

  function setVestingPeriodOfAffiliateInterests(uint256 _vestingPeriodOfAffiliateInterests)
    external
    onlyOwner
  {
    vestingPeriodOfAffiliateInterests = _vestingPeriodOfAffiliateInterests;
  }

  function setSponsorFee(uint256 _sponsorFee) external onlyOwner {
    sponsorFee = _sponsorFee;
  }

  function setCashoutFee(uint256 _cashoutFee) external onlyOwner {
    cashoutFee = _cashoutFee;
  }

  // 4.5 - Related to the state of the protocol

  function pauseDepositCreation(bool _bool) external onlyOwner {
    isDepositCreationPaused = _bool;
  }

  function pauseCashout(bool _bool) external onlyOwner {
    isCashoutPaused = _bool;
  }

  // 4.6 - Related to token and contract addresses

  function setSupportedToken(address _supportedTokenAddress) external onlyOwner {
    supportedToken = IERC20(_supportedTokenAddress);
  }

  function setInvestmentWallet(address payable _investmentWallet) external onlyOwner {
    investmentWallet = _investmentWallet;
  }

  function setFeesWallet(address payable _feesWallet) external onlyOwner {
    feesWallet = _feesWallet;
  }

  // 4.7 - Related to safety

  function setMaximumFirstDepositAmount(uint256 _maximumFirstDepositAmount) external onlyOwner {
    maximumFirstDepositAmount = _maximumFirstDepositAmount;
  }

  function setMaximumDepositAmount(uint256 _maximumDepositAmount) external onlyOwner {
    maximumDepositAmount = _maximumDepositAmount;
  }

  // Manually sends the deposit creation fees
  function sendFeeBalance() external onlyOwner {
    _sendFeeBalance();
  }

  function withdraw(uint256 _amount) external onlyOwner {
    payable(msg.sender).transfer(_amount);
  }

  function withdrawERC20(address _erc20, uint256 _amount) external onlyOwner {
    IERC20(_erc20).transfer(msg.sender, _amount);
  }

  function blacklist(address _address, bool _bool) external onlyOwner {
    _isBlacklisted[_address] = _bool;
  }
}
