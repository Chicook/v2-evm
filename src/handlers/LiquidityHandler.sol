// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// interfaces
import { ILiquidityHandler } from "./interfaces/ILiquidityHandler.sol";
import { IConfigStorage } from "../storages/interfaces/IConfigStorage.sol";
import { IVaultStorage } from "../storages/interfaces/IVaultStorage.sol";
import { IPerpStorage } from "../storages/interfaces/IPerpStorage.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ICalculator } from "../contracts/interfaces/ICalculator.sol";
import { PLPv2 } from "../contracts/PLPv2.sol";
import { IOracleMiddleware } from "../oracle/interfaces/IOracleMiddleware.sol";
import { AddressUtils } from "../libraries/AddressUtils.sol";
import { IWNative } from "./interfaces/IWNative.sol";

/// @title LiquidityService
contract LiquidityHandler is ILiquidityHandler {
  //@todo do we need to know how platform know all order pending
  mapping(address => LiquidityOrder[]) public liquidityOrders; // user address => all liquidityOrder
  mapping(address => uint256) startOrderIndex; //user address => startOrderIndex when execute

  address configStorage;
  address public weth;

  constructor(address _configStorage, address _weth) {
    configStorage = _configStorage;
    weth = _weth;
  }

  function createAddLiquidityOrder(
    address _tokenBuy,
    uint256 _amountIn,
    uint256 _minOut,
    bool _shouldWrap
  ) external payable {
    //1. convert native to WNative (including executionFee)
    _transferInETH();

    //@todo  if (_executionFee < minExecutionFee) revert InsufficientExecutionFee();  still need?
    if (_shouldWrap) {
      if (msg.value != _amountIn + IConfigStorage(configStorage).getLiquidityConfig().executionFeeAmount) {
        revert ILiquidityHandler_InCorrectValueTransfer();
      }
    } else {
      if (msg.value != IConfigStorage(configStorage).getLiquidityConfig().executionFeeAmount)
        revert ILiquidityHandler_InCorrectValueTransfer();

      ERC20(_tokenBuy).transferFrom(msg.sender, address(this), _amountIn);
    }

    LiquidityOrder[] storage _orders = liquidityOrders[msg.sender];
    _orders.push(
      LiquidityOrder({ account: msg.sender, token: _tokenBuy, amount: _amountIn, minOut: _minOut, isAdd: true })
    );
  }

  function createRemoveLiquidityOrder(address _tokenSell, uint256 _amountIn, uint256 _minOut) external payable {
    //convert native to WNative (including executionFee)
    _transferInETH();

    if (msg.value != IConfigStorage(configStorage).getLiquidityConfig().executionFeeAmount)
      revert ILiquidityHandler_InCorrectValueTransfer();

    LiquidityOrder[] storage _orders = liquidityOrders[msg.sender];
    _orders.push(
      LiquidityOrder({ account: msg.sender, token: _tokenSell, amount: _amountIn, minOut: _minOut, isAdd: false })
    );
    // @todo events
  }

  function cancelLiquidityOrder() external {}

  function _executeOrders(LiquidityOrder memory orders) external {}

  function _getOrder(address _lpProvider, uint256 _orderIndex) internal view returns (LiquidityOrder memory) {
    return liquidityOrders[_lpProvider][_orderIndex];
  }

  function _getPendingOrders(address lpProvider) external view returns (LiquidityOrder[] memory) {
    if (liquidityOrders[lpProvider].length == 0 || liquidityOrders[lpProvider].length == startOrderIndex[lpProvider]) {
      return new LiquidityOrder[](0);
    }

    LiquidityOrder[] memory _orders = liquidityOrders[lpProvider];
    LiquidityOrder[] memory pendingOrders = new LiquidityOrder[](
      liquidityOrders[lpProvider].length - startOrderIndex[lpProvider]
    );

    for (uint256 i = startOrderIndex[lpProvider]; i < _orders.length; ) {
      pendingOrders[i] = _orders[i];
      unchecked {
        i++;
      }
    }
    return pendingOrders;
  }

  function _transferInETH() private {
    if (msg.value != 0) {
      IWNative(weth).deposit{ value: msg.value }();
    }
  }

  function _transferOutETH(uint256 _amountOut, address _receiver) private {
    IWNative(weth).withdraw(_amountOut);
    payable(_receiver).transfer(_amountOut);
  }
}
