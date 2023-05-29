// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// base
import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

// interfaces
import { ICrossMarginHandler } from "@hmx/handlers/interfaces/ICrossMarginHandler.sol";
import { CrossMarginService } from "@hmx/services/CrossMarginService.sol";
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";
import { IWNative } from "../interfaces/IWNative.sol";

import { VaultStorage } from "@hmx/storages/VaultStorage.sol";
import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { IGmxRewardRouterV2 } from "@hmx/interfaces/gmx/IGmxRewardRouterV2.sol";
import { ConvertedGlpStrategy } from "@hmx/strategies/ConvertedGlpStrategy.sol";

/// @title CrossMarginHandler
/// @notice This contract handles the deposit and withdrawal of collateral tokens for the Cross Margin Trading module.
contract CrossMarginHandler is OwnableUpgradeable, ReentrancyGuardUpgradeable, ICrossMarginHandler {
  using SafeERC20Upgradeable for ERC20Upgradeable;

  /**
   * Events
   */
  event LogDepositCollateral(
    address indexed primaryAccount,
    uint256 indexed subAccountId,
    address token,
    uint256 amount
  );
  event LogWithdrawCollateral(
    address indexed primaryAccount,
    uint256 indexed subAccountId,
    address token,
    uint256 amount
  );
  event LogSetCrossMarginService(address indexed oldCrossMarginService, address newCrossMarginService);
  event LogSetPyth(address indexed oldPyth, address newPyth);
  event LogSetOrderExecutor(address executor, bool isAllow);
  event LogSetMinExecutionFee(uint256 oldValue, uint256 newValue);
  event LogCreateWithdrawOrder(
    address indexed account,
    uint8 indexed subAccountId,
    uint256 indexed orderId,
    address token,
    uint256 amount,
    uint256 executionFee,
    bool shouldUnwrap
  );
  event LogCancelWithdrawOrder(
    address indexed account,
    uint8 indexed subAccountId,
    uint256 indexed orderId,
    address token,
    uint256 amount,
    uint256 executionFee,
    bool shouldUnwrap
  );
  event LogExecuteWithdrawOrder(
    address indexed account,
    uint8 indexed subAccountId,
    uint256 indexed orderId,
    address token,
    uint256 amount,
    bool shouldUnwrap,
    bool isSuccess
  );

  /**
   * Constants
   */
  uint64 internal constant RATE_PRECISION = 1e18;

  /**
   * States
   */
  address public crossMarginService;
  address public pyth;
  uint256 public nextExecutionOrderIndex; // the index of the next withdraw order that should be executed
  uint256 public minExecutionOrderFee; // minimum execution order fee in native token amount

  WithdrawOrder[] public withdrawOrders; // all withdrawOrder
  mapping(address => WithdrawOrder[]) public subAccountExecutedWithdrawOrders; // subAccount -> executed orders
  mapping(address => bool) public orderExecutors; //address -> flag to execute
  address public gmxRewardRouter;

  /// @notice Initializes the CrossMarginHandler contract with the provided configuration parameters.
  /// @param _crossMarginService Address of the CrossMarginService contract.
  /// @param _pyth Address of the Pyth contract.
  /// @param _minExecutionOrderFee Minimum execution fee for a withdrawal order.
  function initialize(
    address _crossMarginService,
    address _pyth,
    uint256 _minExecutionOrderFee,
    address _gmxRewardRouter
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    // Sanity check
    CrossMarginService(_crossMarginService).vaultStorage();
    IEcoPyth(_pyth).getAssetIds();

    crossMarginService = _crossMarginService;
    pyth = _pyth;
    minExecutionOrderFee = _minExecutionOrderFee;
    gmxRewardRouter = _gmxRewardRouter;
  }

  function getActiveWithdrawOrders(
    uint256 _limit,
    uint256 _offset
  ) external view returns (WithdrawOrder[] memory _withdrawOrder) {
    // Find the _returnCount
    uint256 _returnCount;
    {
      uint256 _activeOrderCount = withdrawOrders.length - nextExecutionOrderIndex;

      uint256 _afterOffsetCount = _activeOrderCount > _offset ? (_activeOrderCount - _offset) : 0;
      _returnCount = _afterOffsetCount > _limit ? _limit : _afterOffsetCount;

      if (_returnCount == 0) return _withdrawOrder;
    }

    // Initialize order array
    _withdrawOrder = new WithdrawOrder[](_returnCount);

    // Build the array
    {
      for (uint i = 0; i < _returnCount; ) {
        _withdrawOrder[i] = withdrawOrders[nextExecutionOrderIndex + _offset + i];
        unchecked {
          ++i;
        }
      }

      return _withdrawOrder;
    }
  }

  function getExecutedWithdrawOrders(
    address _subAccount,
    uint256 _limit,
    uint256 _offset
  ) external view returns (WithdrawOrder[] memory _withdrawOrder) {
    // Find the _returnCount and
    uint256 _returnCount;
    {
      uint256 _exeuctedOrderCount = subAccountExecutedWithdrawOrders[_subAccount].length;
      uint256 _afterOffsetCount = _exeuctedOrderCount > _offset ? (_exeuctedOrderCount - _offset) : 0;
      _returnCount = _afterOffsetCount > _limit ? _limit : _afterOffsetCount;

      if (_returnCount == 0) return _withdrawOrder;
    }

    // Initialize order array
    _withdrawOrder = new WithdrawOrder[](_returnCount);

    // Build the array
    {
      for (uint i = 0; i < _returnCount; ) {
        _withdrawOrder[i] = subAccountExecutedWithdrawOrders[_subAccount][_offset + i];
        unchecked {
          ++i;
        }
      }
      return _withdrawOrder;
    }
  }

  /**
   * Modifiers
   */

  /// @notice Validate only accepted collateral tokens to be deposited or withdrawn
  modifier onlyAcceptedToken(address _token) {
    ConfigStorage(CrossMarginService(crossMarginService).configStorage()).validateAcceptedCollateral(_token);
    _;
  }

  /// @notice Validate only whitelisted executors to call function
  modifier onlyOrderExecutor() {
    if (!orderExecutors[msg.sender]) revert ICrossMarginHandler_NotWhitelisted();
    _;
  }

  /**
   * CALCULATION
   */

  /// @notice Deposits the specified amount of collateral token into the user's sub-account.
  /// @param _subAccountId ID of the user's sub-account.
  /// @param _token Address of the collateral token to deposit.
  /// @param _amount Amount of collateral token to deposit.
  /// @param _shouldWrap Whether to wrap native ETH into WETH before depositing.
  function depositCollateral(
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    bool _shouldWrap
  ) external payable nonReentrant onlyAcceptedToken(_token) {
    // SLOAD
    CrossMarginService _crossMarginService = CrossMarginService(crossMarginService);

    if (_shouldWrap) {
      // Prevent mismatch msgValue and the input amount
      if (msg.value != _amount) {
        revert ICrossMarginHandler_MismatchMsgValue();
      }

      // Wrap the native to wNative. The _token must be wNative.
      // If not, it would revert transfer amount exceed on the next line.
      // slither-disable-next-line arbitrary-send-eth
      IWNative(_token).deposit{ value: _amount }();
      // Transfer those wNative token from this contract to VaultStorage
      ERC20Upgradeable(_token).safeTransfer(_crossMarginService.vaultStorage(), _amount);
    } else {
      // Transfer depositing token from trader's wallet to VaultStorage
      ERC20Upgradeable(_token).safeTransferFrom(msg.sender, _crossMarginService.vaultStorage(), _amount);
    }

    // Call service to deposit collateral
    _crossMarginService.depositCollateral(msg.sender, _subAccountId, _token, _amount);

    emit LogDepositCollateral(msg.sender, _subAccountId, _token, _amount);
  }

  /// @notice Creates a new withdraw order to withdraw the specified amount of collateral token from the user's sub-account.
  /// @param _subAccountId ID of the user's sub-account.
  /// @param _token Address of the collateral token to withdraw.
  /// @param _amount Amount of collateral token to withdraw.
  /// @param _executionFee Execution fee to pay for this order.
  /// @param _shouldUnwrap Whether to unwrap WETH into native ETH after withdrawing.
  /// @return _orderId The ID of the newly created withdraw order.
  function createWithdrawCollateralOrder(
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    uint256 _executionFee,
    bool _shouldUnwrap
  ) external payable nonReentrant onlyAcceptedToken(_token) returns (uint256 _orderId) {
    if (_executionFee < minExecutionOrderFee) revert ICrossMarginHandler_InsufficientExecutionFee();
    if (msg.value != _executionFee) revert ICrossMarginHandler_InCorrectValueTransfer();

    // convert native to WNative (including executionFee)
    _transferInETH();

    _orderId = withdrawOrders.length;

    withdrawOrders.push(
      WithdrawOrder({
        account: payable(msg.sender),
        orderId: _orderId,
        token: _token,
        amount: _amount,
        executionFee: _executionFee,
        shouldUnwrap: _shouldUnwrap,
        subAccountId: _subAccountId,
        crossMarginService: CrossMarginService(crossMarginService),
        createdTimestamp: uint48(block.timestamp),
        executedTimestamp: 0,
        status: 0 // pending
      })
    );

    emit LogCreateWithdrawOrder(msg.sender, _subAccountId, _orderId, _token, _amount, _executionFee, _shouldUnwrap);
    return _orderId;
  }

  /// @notice Executes a batch of pending withdraw orders.
  /// @param _endIndex The index of the last withdraw order to execute.
  /// @param _feeReceiver The address to receive the total execution fee.
  /// @param _priceData Price data from the Pyth oracle.
  /// @param _publishTimeData Publish time data from the Pyth oracle.
  /// @param _minPublishTime Minimum publish time for the Pyth oracle data.
  /// @param _encodedVaas Encoded VaaS data for the Pyth oracle.
  // slither-disable-next-line reentrancy-eth
  function executeOrder(
    uint256 _endIndex,
    address payable _feeReceiver,
    bytes32[] memory _priceData,
    bytes32[] memory _publishTimeData,
    uint256 _minPublishTime,
    bytes32 _encodedVaas
  ) external nonReentrant onlyOrderExecutor {
    // Get the number of withdraw orders
    uint256 _orderLength = withdrawOrders.length;

    // Ensure there are orders to execute
    if (nextExecutionOrderIndex == _orderLength) revert ICrossMarginHandler_NoOrder();

    // Set the end index to the latest order index if it exceeds the number of orders
    uint256 _latestOrderIndex = _orderLength - 1;
    if (_endIndex > _latestOrderIndex) {
      _endIndex = _latestOrderIndex;
    }

    // Update the price and publish time data using the Pyth oracle
    // slither-disable-next-line arbitrary-send-eth
    IEcoPyth(pyth).updatePriceFeeds(_priceData, _publishTimeData, _minPublishTime, _encodedVaas);

    // Initialize variables for the execution loop
    WithdrawOrder memory _order;
    uint256 _totalFeeReceiver;
    uint256 _executionFee;

    for (uint256 i = nextExecutionOrderIndex; i <= _endIndex; ) {
      _order = withdrawOrders[i];
      _executionFee = _order.executionFee;

      try this.executeWithdrawOrder(_order) {
        emit LogExecuteWithdrawOrder(
          _order.account,
          _order.subAccountId,
          _order.orderId,
          _order.token,
          _order.amount,
          _order.shouldUnwrap,
          true
        );

        // update order status
        _order.status = 1; // success
      } catch Error(string memory) {
        // Do nothing
      } catch (bytes memory) {
        emit LogExecuteWithdrawOrder(
          _order.account,
          _order.subAccountId,
          _order.orderId,
          _order.token,
          _order.amount,
          _order.shouldUnwrap,
          false
        );

        // update order status
        _order.status = 2; // fail
      }

      // assign exec time
      _order.executedTimestamp = uint48(block.timestamp);

      _totalFeeReceiver += _executionFee;

      // save to executed order first
      subAccountExecutedWithdrawOrders[_getSubAccount(_order.account, _order.subAccountId)].push(_order);
      // clear executed withdraw order
      delete withdrawOrders[i];

      unchecked {
        ++i;
      }
    }

    nextExecutionOrderIndex = _endIndex + 1;
    // Pay total collected fees to the executor
    _transferOutETH(_totalFeeReceiver, _feeReceiver);
  }

  /// @notice Executes a single withdraw order by transferring the specified amount of collateral token to the user's wallet.
  /// @param _order WithdrawOrder struct representing the order to execute.
  function executeWithdrawOrder(WithdrawOrder memory _order) external {
    // if not in executing state, then revert
    if (msg.sender != address(this)) revert ICrossMarginHandler_NotExecutionState();

    // Call service to withdraw collateral
    if (_order.shouldUnwrap) {
      // Withdraw wNative straight to this contract first.
      _order.crossMarginService.withdrawCollateral(
        _order.account,
        _order.subAccountId,
        _order.token,
        _order.amount,
        address(this)
      );
      // Then we unwrap the wNative token. The receiving amount should be the exact same as _amount. (No fee deducted when withdraw)
      IWNative(_order.token).withdraw(_order.amount);

      // slither-disable-next-line arbitrary-send-eth
      payable(_order.account).transfer(_order.amount);
    } else {
      // Withdraw _token straight to the user
      _order.crossMarginService.withdrawCollateral(
        _order.account,
        _order.subAccountId,
        _order.token,
        _order.amount,
        _order.account
      );
    }

    emit LogWithdrawCollateral(_order.account, _order.subAccountId, _order.token, _order.amount);
  }

  /// @notice Cancels the specified withdraw order.
  /// @param _orderIndex Index of the order to cancel.
  function cancelWithdrawOrder(uint256 _orderIndex) external nonReentrant {
    // if order index >= liquidity order's length, then out of bound
    // if order index < next execute index, means order index outdate
    if (_orderIndex >= withdrawOrders.length || _orderIndex < nextExecutionOrderIndex) {
      revert ICrossMarginHandler_NoOrder();
    }

    // SLOAD
    WithdrawOrder memory _order = withdrawOrders[_orderIndex];

    // validate if msg.sender is not owned the order, then revert
    if (msg.sender != _order.account) revert ICrossMarginHandler_NotOrderOwner();

    delete withdrawOrders[_orderIndex];

    emit LogCancelWithdrawOrder(
      payable(msg.sender),
      _order.subAccountId,
      _order.orderId,
      _order.token,
      _order.amount,
      _order.executionFee,
      _order.shouldUnwrap
    );
  }

  /**
   * GETTER
   */

  /// @notice Returns all pending withdraw orders.
  /// @return _withdrawOrders An array of WithdrawOrder structs representing all pending withdraw orders.
  function getWithdrawOrders() external view returns (WithdrawOrder[] memory _withdrawOrders) {
    return withdrawOrders;
  }

  /// @notice get withdraw orders length
  function getWithdrawOrderLength() external view returns (uint256) {
    return withdrawOrders.length;
  }

  /**
   * Setters
   */

  /// @notice Sets a new CrossMarginService contract address.
  /// @param _crossMarginService The new CrossMarginService contract address.
  function setCrossMarginService(address _crossMarginService) external nonReentrant onlyOwner {
    if (_crossMarginService == address(0)) revert ICrossMarginHandler_InvalidAddress();
    emit LogSetCrossMarginService(crossMarginService, _crossMarginService);
    crossMarginService = _crossMarginService;

    // Sanity check
    CrossMarginService(_crossMarginService).vaultStorage();
  }

  /// @notice Sets a new Pyth contract address.
  /// @param _pyth The new Pyth contract address.
  function setPyth(address _pyth) external nonReentrant onlyOwner {
    if (_pyth == address(0)) revert ICrossMarginHandler_InvalidAddress();
    emit LogSetPyth(pyth, _pyth);
    pyth = _pyth;

    // Sanity check
    IEcoPyth(_pyth).getAssetIds();
  }

  /// @notice setMinExecutionFee
  /// @param _newMinExecutionFee minExecutionFee in ethers
  function setMinExecutionFee(uint256 _newMinExecutionFee) external nonReentrant onlyOwner {
    emit LogSetMinExecutionFee(minExecutionOrderFee, _newMinExecutionFee);
    minExecutionOrderFee = _newMinExecutionFee;
  }

  /// @notice setOrderExecutor
  /// @param _executor address who will be executor
  /// @param _isAllow flag to allow to execute
  function setOrderExecutor(address _executor, bool _isAllow) external nonReentrant onlyOwner {
    orderExecutors[_executor] = _isAllow;
    emit LogSetOrderExecutor(_executor, _isAllow);
  }

  /// @notice convert collateral
  function convertSGlpCollateral(
    uint8 _subAccountId,
    address _tokenOut,
    uint256 _amountIn
  ) external nonReentrant onlyAcceptedToken(_tokenOut) returns (uint256 _amountOut) {
    return
      CrossMarginService(crossMarginService).convertSGlpCollateral(msg.sender, _subAccountId, _tokenOut, _amountIn);
  }

  function depositCollateralAndConvertToGLP(
    uint8 _subAccountId,
    address _token,
    uint256 _amount,
    bool _shouldWrap,
    uint256 _minGlp
  ) external payable nonReentrant {
    // SLOAD
    CrossMarginService _crossMarginService = CrossMarginService(crossMarginService);
    IGmxRewardRouterV2 rewardRouter = IGmxRewardRouterV2(gmxRewardRouter);

    uint256 glpAmount;
    if (!_shouldWrap) {
      // Convert _token into GLP
      glpAmount = rewardRouter.mintAndStakeGlp(_token, _amount, 0, _minGlp);
    } else {
      // Convert ETH into GLP
      glpAmount = rewardRouter.mintAndStakeGlpETH(0, _minGlp);
    }

    // Transfer GLP to VaultStorage
    ERC20Upgradeable(address(ConvertedGlpStrategy(_crossMarginService.convertedSglpStrategy()).sglp())).safeTransfer(
      _crossMarginService.vaultStorage(),
      _amount
    );

    // Call service to deposit collateral
    _crossMarginService.depositCollateral(msg.sender, _subAccountId, _token, _amount);
  }

  /**
   * Private Functions
   */

  /// @notice Transfer in ETH from user to be used as execution fee
  /// @dev The received ETH will be wrapped into WETH and store in this contract for later use.
  function _transferInETH() private {
    IWNative(ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth()).deposit{
      value: msg.value
    }();
  }

  /// @notice Transfer out ETH to the receiver
  /// @dev The stored WETH will be unwrapped and transfer as native token
  /// @param _amountOut Amount of ETH to be transferred
  /// @param _receiver The receiver of ETH in its native form. The receiver must be able to accept native token.
  function _transferOutETH(uint256 _amountOut, address _receiver) private {
    IWNative(ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth()).withdraw(_amountOut);
    // slither-disable-next-line arbitrary-send-eth
    payable(_receiver).transfer(_amountOut);
  }

  function _getSubAccount(address _primary, uint8 _subAccountId) private pure returns (address) {
    if (_subAccountId > 255) revert();
    return address(uint160(_primary) ^ uint160(_subAccountId));
  }

  receive() external payable {
    // @dev Cannot enable this check due to Solidity Fallback Function Gas Limit introduced in 0.8.17.
    // ref - https://stackoverflow.com/questions/74930609/solidity-fallback-function-gas-limit
    // require(msg.sender == ConfigStorage(CrossMarginService(crossMarginService).configStorage()).weth());
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}
