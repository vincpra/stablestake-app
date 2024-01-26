// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract TOKEN is ERC20, Ownable, AccessControl {
  bytes32 public constant DAO = keccak256("DAO");

  IUniswapV2Router02 public pancakeRouter;

  address public tokenDAO;
  uint256 public initialSupply = 10_000_000e18;
  address public pancakeTokenBnbPair;

  mapping(address => bool) public _automatedMarketMakerPairs;
  mapping(address => bool) private _blacklist;
  mapping(address => bool) private _exemptFromFees;

  address payable public safeWallet; // Safe that stores the BNB made from the fees
  uint256 public safeWalletBalance = 0; // TOKEN balance accumulated from safe fees
  uint256 public liquidityFeeBalance = 0; // TOKEN balance accumulated from liquidity fees
  uint256 public minimumSafeWalletBalanceToSwap = 100e18; // TOKEN balance required to perform a swap
  uint256 public minimumLiquidityFeeBalanceToSwap = 100e18; // TOKEN balance required to add liquidity
  bool public swapEnabled = true;

  // Avoid having two swaps in the same block
  bool private swapping = false;
  bool private swapLiquify = false;

  uint256 public buyingFee = 0; // (/1000)
  uint256 public sellingFee = 100; // (/1000)

  uint256 public safeFeePercentage = 9500; // (/1000) Part of the fees that will be sent to the safe fee. The rest will be sent to the liquidity fee

  event SwappedSafeWalletBalance(uint256 amount);
  event AddedLiquidity(uint256 tokenAmount, uint256 bnbAmount);

  constructor(address _pancakeRouter, address payable _safeWallet) ERC20("Test Token", "TOKEN") {
    safeWallet = _safeWallet;
    _mint(msg.sender, initialSupply);
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    grantRole(DAO, msg.sender);
    pancakeRouter = IUniswapV2Router02(_pancakeRouter);
    pancakeTokenBnbPair = IUniswapV2Factory(pancakeRouter.factory()).createPair(address(this), pancakeRouter.WETH());

    _exemptFromFees[msg.sender] = true;
    _exemptFromFees[address(this)] = true;
    _exemptFromFees[address(0)] = true;

    _setAutomatedMarketMakerPair(address(pancakeTokenBnbPair), true);
  }

  receive() external payable {}

  // Implement the blacklisting
  function _beforeTokenTransfer(
    address _from,
    address _to,
    uint256 _amount
  ) internal virtual override(ERC20) {
    require(!isBlacklisted(_from), "Token transfer refused. Sender is blacklisted");
    require(!isBlacklisted(_to), "Token transfer refused. Recipient is blacklisted");
    super._beforeTokenTransfer(_from, _to, _amount);
  }

  // Collects relevant fees and performs a swap if needed
  function _transfer(
    address _from,
    address _to,
    uint256 _amount
  ) internal override {
    require(_from != address(0), "Cannot transfer from the zero address");
    require(_amount > 0, "Cannot transfer 0 tokens");
    uint256 fees = 0;

    // Take fees on buys and sells
    if (!_exemptFromFees[_from] && !_exemptFromFees[_to]) {
      if (_automatedMarketMakerPairs[_to] && sellingFee > 0) {
        fees = (_amount * sellingFee) / 1000;
      } else if (_automatedMarketMakerPairs[_from] && buyingFee > 0) {
        fees = (_amount * buyingFee) / 1000;
      }

      // Send fees to the TOKEN contract
      if (fees > 0) {
        // Send TOKEN tokens to the contract
        super._transfer(_from, address(this), fees);

        // Keep track of the TOKEN that were sent
        uint256 safeFees = (fees * safeFeePercentage) / 1000;
        safeWalletBalance += safeFees;
        liquidityFeeBalance += fees - safeFees;
      }

      _amount -= fees;
    }

    // Swapping logic
    if (swapEnabled) {
      // If the bnb of the fee balances is above a certain amount, swap it for BNB and transfer it to the safe wallet
      // Do not do both in one transaction
      if (!swapping && !swapLiquify && safeWalletBalance > minimumSafeWalletBalanceToSwap) {
        // Forbid swapping item creation fees
        swapping = true;

        // Perform the swap
        _swapSafeWalletBalance();

        // Allow swapping
        swapping = false;
      } else if (!swapping && !swapLiquify && liquidityFeeBalance > minimumLiquidityFeeBalanceToSwap) {
        // Forbid swapping liquidity fees
        swapLiquify = true;

        // Perform the swap
        _liquify();

        // Allow swapping
        swapLiquify = false;
      }
    }

    super._transfer(_from, _to, _amount);
  }

  // Swaps liquidity fee balance for BNB and adds it to the TOKEN / BNB pool
  function _liquify() internal {
    require(
      liquidityFeeBalance > minimumLiquidityFeeBalanceToSwap,
      "Not enough TOKEN tokens to swap for adding liquidity"
    );

    uint256 oldBalance = address(this).balance;

    // Sell half of the TOKEN for BNB
    uint256 lowerHalf = liquidityFeeBalance / 2;
    uint256 upperHalf = liquidityFeeBalance - lowerHalf;

    // Swap
    _swapTokenForBnb(lowerHalf);

    // Update liquidityFeeBalance
    liquidityFeeBalance = 0;

    // Add liquidity
    _addLiquidity(upperHalf, address(this).balance - oldBalance);
  }

  // Adds liquidity to the TOKEN / BNB pair on PancakeSwap
  function _addLiquidity(uint256 _tokenAmount, uint256 _bnbAmount) internal {
    _approve(address(this), address(pancakeRouter), _tokenAmount);

    // Add the liquidity
    pancakeRouter.addLiquidityETH{value: _bnbAmount}(
      address(this),
      _tokenAmount,
      0, // Slippage will be present
      0, // Slippage will be present
      address(0),
      block.timestamp
    );

    emit AddedLiquidity(_tokenAmount, _bnbAmount);
  }

  // Swaps safe fee balance for BNB and sends it to the safe wallet
  function _swapSafeWalletBalance() internal {
    require(safeWalletBalance > minimumSafeWalletBalanceToSwap, "Not enough TOKEN tokens to swap for safe fee");

    uint256 oldBalance = address(this).balance;

    // Swap
    _swapTokenForBnb(safeWalletBalance);

    // Update itemCreationFeeBalance
    safeWalletBalance = 0;

    // Send BNB to safe wallet
    uint256 toSend = address(this).balance - oldBalance;
    safeWallet.transfer(toSend);

    emit SwappedSafeWalletBalance(toSend);
  }

  // Swaps "_tokenAmount" TOKEN for BNB
  function _swapTokenForBnb(uint256 _tokenAmount) internal {
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = pancakeRouter.WETH();

    _approve(address(this), address(pancakeRouter), _tokenAmount);

    pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
      _tokenAmount,
      0, // accept any amount of BNB
      path,
      address(this),
      block.timestamp
    );
  }

  // Set or unset an address as an automated market pair / removes
  function _setAutomatedMarketMakerPair(address _pair, bool _value) internal {
    _automatedMarketMakerPairs[_pair] = _value;
  }

  // Returns true if "_user" is blacklisted
  function isBlacklisted(address _user) public view returns (bool) {
    return _blacklist[_user];
  }

  // Mint new TOKEN tokens
  function mintDAO(address _to, uint256 _amount) public onlyRole(DAO) {
    _mint(_to, _amount);
  }

  // Burns TOKEN tokens
  function burnDAO(address _from, uint256 _amount) public onlyRole(DAO) {
    _burn(_from, _amount);
  }

  function withdrawDAO(uint256 _amount) external onlyRole(DAO) {
    payable(msg.sender).transfer(_amount);
  }

  // Withdraws an amount of TOKEN tokens stored on the contract
  function withdrawERC20DAO(address _erc20, uint256 _amount) external onlyRole(DAO) {
    IERC20(_erc20).transfer(msg.sender, _amount);
  }

  // Manually swaps the safe fees
  function manualSafeFeeSwapDAO() external onlyRole(DAO) {
    // Forbid swapping item creation fees
    swapping = true;

    // Perform the swap
    _swapSafeWalletBalance();

    // Allow swapping again
    swapping = false;
  }

  // Manually add liquidity
  function manualLiquifyDAO() external onlyRole(DAO) {
    // Forbid swapping liquidity fees
    swapLiquify = true;

    // Perform swap
    _liquify();

    // Allow swapping again
    swapLiquify = false;
  }

  function changeDAO(address _newDAO) external onlyRole(DAO) {
    revokeRole(DAO, tokenDAO);
    tokenDAO = _newDAO;
    grantRole(DAO, _newDAO);
  }

  function revokeDAO(address _DaoToRevoke) external onlyRole(DAO) {
    revokeRole(DAO, _DaoToRevoke);
  }

  function blacklistDAO(address _user, bool _state) external onlyRole(DAO) {
    _blacklist[_user] = _state;
  }

  function enableSwappingDAO() external onlyRole(DAO) {
    swapEnabled = true;
  }

  function stopSwappingDAO() external onlyRole(DAO) {
    swapEnabled = false;
  }

  function excludeFromFeesDAO(address _account, bool _state) external onlyRole(DAO) {
    _exemptFromFees[_account] = _state;
  }

  function setSafeWalletDAO(address payable _safeWallet) external onlyRole(DAO) {
    safeWallet = _safeWallet;
  }

  function setAutomatedMarketMakerPairDAO(address _pair, bool _value) external onlyRole(DAO) {
    require(_pair != pancakeTokenBnbPair, "The TOKEN / BNB pair cannot be removed from _automatedMarketMakerPairs");
    _setAutomatedMarketMakerPair(_pair, _value);
  }

  function setMinimumSafeWalletBalanceToSwapDAO(uint256 _minimumSafeWalletBalanceToSwap) external onlyRole(DAO) {
    minimumSafeWalletBalanceToSwap = _minimumSafeWalletBalanceToSwap;
  }

  function setMinimumLiquidityFeeBalanceToSwapDAO(uint256 _minimumLiquidityFeeBalanceToSwap)
    external
    onlyRole(DAO)
  {
    minimumLiquidityFeeBalanceToSwap = _minimumLiquidityFeeBalanceToSwap;
  }

  function setBuyingFeeDAO(uint256 _buyingFee) external onlyRole(DAO) {
    buyingFee = _buyingFee;
  }

  function setSellingFeeDAO(uint256 _sellingFee) external onlyRole(DAO) {
    sellingFee = _sellingFee;
  }

  function setSafeFeePercentageDAO(uint256 _safeFeePercentage) external onlyRole(DAO) {
    safeFeePercentage = _safeFeePercentage;
  }
}
