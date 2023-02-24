// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ITradeService {
  /**
   * Errors
   */
  error ITradeService_MarketIsDelisted();
  error ITradeService_MarketIsClosed();
  error ITradeService_PositionAlreadyClosed();
  error ITradeService_DecreaseTooHighPositionSize();
  error ITradeService_SubAccountEquityIsUnderMMR();
  error ITradeService_TooTinyPosition();
  error ITradeService_BadSubAccountId();
  error ITradeService_BadSizeDelta();
  error ITradeService_NotAllowIncrease();
  error ITradeService_BadNumberOfPosition();
  error ITradeService_BadExposure();
  error ITradeService_InvalidAveragePrice();
  error ITradeService_BadPositionSize();
  error ITradeService_InsufficientLiquidity();
  error ITradeService_InsufficientFreeCollateral();

  /**
   * STRUCTS
   */
  struct SettleFeeVar {
    int256 feeUsd;
    uint256 absFeeUsd;
    address[] plpUnderlyingTokens;
    address underlyingToken;
    uint256 underlyingTokenDecimal;
    uint256 traderBalance;
    uint256 tradingFee;
    uint256 price;
    uint256 feeTokenAmount;
    uint256 balanceValue;
    uint256 repayFeeTokenAmount;
    uint256 devFeeTokenAmount;
  }

  function configStorage() external view returns (address);

  function perpStorage() external view returns (address);

  function increasePosition(
    address _primaryAccount,
    uint256 _subAccountId,
    uint256 _marketIndex,
    int256 _sizeDelta
  ) external;

  function decreasePosition(
    address _account,
    uint256 _subAccountId,
    uint256 _marketIndex,
    uint256 _positionSizeE30ToDecrease
  ) external;
}
