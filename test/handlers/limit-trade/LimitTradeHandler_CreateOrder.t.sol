// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { LimitTradeHandler_Base, IPerpStorage } from "./LimitTradeHandler_Base.t.sol";
import { ILimitTradeHandler } from "../../../src/handlers/interfaces/ILimitTradeHandler.sol";

contract LimitTradeHandler_CreateOrder is LimitTradeHandler_Base {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_createOrder_InsufficientExecutionFee() external {
    vm.expectRevert(abi.encodeWithSignature("ILimitTradeHandler_InsufficientExecutionFee()"));
    limitTradeHandler.createOrder({
      _orderType: ILimitTradeHandler.OrderType.INCREASE,
      _subAccountId: 0,
      _marketIndex: 0,
      _sizeDelta: 100,
      _triggerPrice: 1000,
      _triggerAboveThreshold: true,
      _executionFee: 0 ether
    });
  }

  function testRevert_createOrder_IncorrectValueTransfer() external {
    vm.expectRevert(abi.encodeWithSignature("ILimitTradeHandler_IncorrectValueTransfer()"));
    limitTradeHandler.createOrder({
      _orderType: ILimitTradeHandler.OrderType.INCREASE,
      _subAccountId: 3,
      _marketIndex: 0,
      _sizeDelta: 100,
      _triggerPrice: 1000,
      _triggerAboveThreshold: true,
      _executionFee: 0.1 ether
    });
  }

  function testRevert_createOrder_BadSubAccountId() external {
    vm.expectRevert(abi.encodeWithSignature("ILimitTradeHandler_BadSubAccountId()"));
    limitTradeHandler.createOrder{ value: 0.1 ether }({
      _orderType: ILimitTradeHandler.OrderType.INCREASE,
      _subAccountId: 1000,
      _marketIndex: 0,
      _sizeDelta: 100,
      _triggerPrice: 1000,
      _triggerAboveThreshold: true,
      _executionFee: 0.1 ether
    });
  }

  function testCorrectness_createOrder_IncreaseOrder() external {
    uint256 balanceBefore = address(this).balance;

    limitTradeHandler.createOrder{ value: 0.1 ether }({
      _orderType: ILimitTradeHandler.OrderType.INCREASE,
      _subAccountId: 0,
      _marketIndex: 1,
      _sizeDelta: 1000 * 1e30,
      _triggerPrice: 1000 * 1e30,
      _triggerAboveThreshold: true,
      _executionFee: 0.1 ether
    });

    uint256 balanceDiff = balanceBefore - address(this).balance;
    assertEq(balanceDiff, 0.1 ether, "Execution fee is correctly collected from user.");
    assertEq(limitTradeHandler.increaseOrdersIndex(address(this)), 1, "increaseOrdersIndex should increase by one.");

    ILimitTradeHandler.IncreaseOrder memory increaseOrder;
    (
      increaseOrder.account,
      increaseOrder.subAccountId,
      increaseOrder.marketIndex,
      increaseOrder.sizeDelta,
      increaseOrder.isLong,
      increaseOrder.triggerPrice,
      increaseOrder.triggerAboveThreshold,
      increaseOrder.executionFee
    ) = limitTradeHandler.increaseOrders(address(this), 0);
    assertEq(increaseOrder.account, address(this));
    assertEq(increaseOrder.subAccountId, 0);
    assertEq(increaseOrder.marketIndex, 1);
    assertEq(increaseOrder.sizeDelta, 1000 * 1e30);
    assertEq(increaseOrder.isLong, true);
    assertEq(increaseOrder.triggerPrice, 1000 * 1e30);
    assertEq(increaseOrder.triggerAboveThreshold, true);
    assertEq(increaseOrder.executionFee, 0.1 ether);

    // Open another Long order with the same sub account
    limitTradeHandler.createOrder{ value: 0.2 ether }({
      _orderType: ILimitTradeHandler.OrderType.INCREASE,
      _subAccountId: 0,
      _marketIndex: 2,
      _sizeDelta: 2000 * 1e30,
      _triggerPrice: 2000 * 1e30,
      _triggerAboveThreshold: true,
      _executionFee: 0.2 ether
    });
    assertEq(limitTradeHandler.increaseOrdersIndex(address(this)), 2, "increaseOrdersIndex should increase by one.");
    (
      increaseOrder.account,
      increaseOrder.subAccountId,
      increaseOrder.marketIndex,
      increaseOrder.sizeDelta,
      increaseOrder.isLong,
      increaseOrder.triggerPrice,
      increaseOrder.triggerAboveThreshold,
      increaseOrder.executionFee
    ) = limitTradeHandler.increaseOrders(address(this), 1);
    assertEq(increaseOrder.account, address(this));
    assertEq(increaseOrder.subAccountId, 0);
    assertEq(increaseOrder.marketIndex, 2);
    assertEq(increaseOrder.sizeDelta, 2000 * 1e30);
    assertEq(increaseOrder.isLong, true);
    assertEq(increaseOrder.triggerPrice, 2000 * 1e30);
    assertEq(increaseOrder.triggerAboveThreshold, true);
    assertEq(increaseOrder.executionFee, 0.2 ether);

    // Open another Long order with another sub account
    limitTradeHandler.createOrder{ value: 0.1 ether }({
      _orderType: ILimitTradeHandler.OrderType.INCREASE,
      _subAccountId: 7,
      _marketIndex: 3,
      _sizeDelta: 3000 * 1e30,
      _triggerPrice: 3000 * 1e30,
      _triggerAboveThreshold: false,
      _executionFee: 0.1 ether
    });
    assertEq(
      limitTradeHandler.increaseOrdersIndex(_getSubAccount(address(this), 7)),
      1,
      "increaseOrdersIndex should increase by one."
    );
    (
      increaseOrder.account,
      increaseOrder.subAccountId,
      increaseOrder.marketIndex,
      increaseOrder.sizeDelta,
      increaseOrder.isLong,
      increaseOrder.triggerPrice,
      increaseOrder.triggerAboveThreshold,
      increaseOrder.executionFee
    ) = limitTradeHandler.increaseOrders(_getSubAccount(address(this), 7), 0);
    assertEq(increaseOrder.account, address(this));
    assertEq(increaseOrder.subAccountId, 7);
    assertEq(increaseOrder.marketIndex, 3);
    assertEq(increaseOrder.sizeDelta, 3000 * 1e30);
    assertEq(increaseOrder.isLong, true);
    assertEq(increaseOrder.triggerPrice, 3000 * 1e30);
    assertEq(increaseOrder.triggerAboveThreshold, false);
    assertEq(increaseOrder.executionFee, 0.1 ether);

    // Open another Short order with 7th sub account
    limitTradeHandler.createOrder{ value: 0.1 ether }({
      _orderType: ILimitTradeHandler.OrderType.INCREASE,
      _subAccountId: 7,
      _marketIndex: 4,
      _sizeDelta: -4000 * 1e30,
      _triggerPrice: 4000 * 1e30,
      _triggerAboveThreshold: false,
      _executionFee: 0.1 ether
    });
    assertEq(
      limitTradeHandler.increaseOrdersIndex(_getSubAccount(address(this), 7)),
      2,
      "increaseOrdersIndex should increase by one."
    );
    (
      increaseOrder.account,
      increaseOrder.subAccountId,
      increaseOrder.marketIndex,
      increaseOrder.sizeDelta,
      increaseOrder.isLong,
      increaseOrder.triggerPrice,
      increaseOrder.triggerAboveThreshold,
      increaseOrder.executionFee
    ) = limitTradeHandler.increaseOrders(_getSubAccount(address(this), 7), 1);
    assertEq(increaseOrder.account, address(this));
    assertEq(increaseOrder.subAccountId, 7);
    assertEq(increaseOrder.marketIndex, 4);
    assertEq(increaseOrder.sizeDelta, -4000 * 1e30);
    assertEq(increaseOrder.isLong, false);
    assertEq(increaseOrder.triggerPrice, 4000 * 1e30);
    assertEq(increaseOrder.triggerAboveThreshold, false);
    assertEq(increaseOrder.executionFee, 0.1 ether);
  }

  function testCorrectness_createOrder_DecreaseOrder() external {
    uint256 balanceBefore = address(this).balance;

    mockPerpStorage.setPositionBySubAccount(
      address(this),
      IPerpStorage.Position({
        primaryAccount: address(this),
        subAccountId: 0,
        marketIndex: 1,
        positionSizeE30: 100_000 * 1e30,
        avgEntryPriceE30: 20_000 * 1e30,
        entryBorrowingRate: 0,
        entryFundingRate: 0,
        reserveValueE30: 9_000 * 1e30,
        lastIncreaseTimestamp: block.timestamp,
        realizedPnl: 0,
        openInterest: 0
      })
    );

    limitTradeHandler.createOrder{ value: 0.1 ether }({
      _orderType: ILimitTradeHandler.OrderType.DECREASE,
      _subAccountId: 0,
      _marketIndex: 1,
      _sizeDelta: 1000 * 1e30,
      _triggerPrice: 1000 * 1e30,
      _triggerAboveThreshold: true,
      _executionFee: 0.1 ether
    });

    uint256 balanceDiff = balanceBefore - address(this).balance;
    assertEq(balanceDiff, 0.1 ether, "Execution fee is correctly collected from user.");
    assertEq(limitTradeHandler.decreaseOrdersIndex(address(this)), 1, "decreaseOrdersIndex should increase by one.");

    ILimitTradeHandler.DecreaseOrder memory decreaseOrder;
    (
      decreaseOrder.account,
      decreaseOrder.subAccountId,
      decreaseOrder.marketIndex,
      decreaseOrder.sizeDelta,
      decreaseOrder.isLong,
      decreaseOrder.triggerPrice,
      decreaseOrder.triggerAboveThreshold,
      decreaseOrder.executionFee
    ) = limitTradeHandler.decreaseOrders(address(this), 0);
    assertEq(decreaseOrder.account, address(this));
    assertEq(decreaseOrder.subAccountId, 0);
    assertEq(decreaseOrder.marketIndex, 1);
    assertEq(decreaseOrder.sizeDelta, 1000 * 1e30);
    assertEq(decreaseOrder.isLong, true, "isLong");
    assertEq(decreaseOrder.triggerPrice, 1000 * 1e30);
    assertEq(decreaseOrder.triggerAboveThreshold, true);
    assertEq(decreaseOrder.executionFee, 0.1 ether);

    // Open another Long order with the same sub account
    mockPerpStorage.setPositionBySubAccount(
      address(this),
      IPerpStorage.Position({
        primaryAccount: address(this),
        subAccountId: 0,
        marketIndex: 2,
        positionSizeE30: 100_000 * 1e30,
        avgEntryPriceE30: 20_000 * 1e30,
        entryBorrowingRate: 0,
        entryFundingRate: 0,
        reserveValueE30: 9_000 * 1e30,
        lastIncreaseTimestamp: block.timestamp,
        realizedPnl: 0,
        openInterest: 0
      })
    );
    limitTradeHandler.createOrder{ value: 0.2 ether }({
      _orderType: ILimitTradeHandler.OrderType.DECREASE,
      _subAccountId: 0,
      _marketIndex: 2,
      _sizeDelta: 2000 * 1e30,
      _triggerPrice: 2000 * 1e30,
      _triggerAboveThreshold: true,
      _executionFee: 0.2 ether
    });
    assertEq(limitTradeHandler.decreaseOrdersIndex(address(this)), 2, "decreaseOrdersIndex should increase by one.");
    (
      decreaseOrder.account,
      decreaseOrder.subAccountId,
      decreaseOrder.marketIndex,
      decreaseOrder.sizeDelta,
      decreaseOrder.isLong,
      decreaseOrder.triggerPrice,
      decreaseOrder.triggerAboveThreshold,
      decreaseOrder.executionFee
    ) = limitTradeHandler.decreaseOrders(address(this), 1);
    assertEq(decreaseOrder.account, address(this));
    assertEq(decreaseOrder.subAccountId, 0);
    assertEq(decreaseOrder.marketIndex, 2);
    assertEq(decreaseOrder.sizeDelta, 2000 * 1e30);
    assertEq(decreaseOrder.isLong, true);
    assertEq(decreaseOrder.triggerPrice, 2000 * 1e30);
    assertEq(decreaseOrder.triggerAboveThreshold, true);
    assertEq(decreaseOrder.executionFee, 0.2 ether);

    // Open another Short order with another sub account
    mockPerpStorage.setPositionBySubAccount(
      _getSubAccount(address(this), 7),
      IPerpStorage.Position({
        primaryAccount: address(this),
        subAccountId: 7,
        marketIndex: 3,
        positionSizeE30: -100_000 * 1e30,
        avgEntryPriceE30: 20_000 * 1e30,
        entryBorrowingRate: 0,
        entryFundingRate: 0,
        reserveValueE30: 9_000 * 1e30,
        lastIncreaseTimestamp: block.timestamp,
        realizedPnl: 0,
        openInterest: 0
      })
    );
    limitTradeHandler.createOrder{ value: 0.1 ether }({
      _orderType: ILimitTradeHandler.OrderType.DECREASE,
      _subAccountId: 7,
      _marketIndex: 3,
      _sizeDelta: 3000 * 1e30,
      _triggerPrice: 3000 * 1e30,
      _triggerAboveThreshold: false,
      _executionFee: 0.1 ether
    });
    assertEq(
      limitTradeHandler.decreaseOrdersIndex(_getSubAccount(address(this), 7)),
      1,
      "decreaseOrdersIndex should increase by one."
    );
    (
      decreaseOrder.account,
      decreaseOrder.subAccountId,
      decreaseOrder.marketIndex,
      decreaseOrder.sizeDelta,
      decreaseOrder.isLong,
      decreaseOrder.triggerPrice,
      decreaseOrder.triggerAboveThreshold,
      decreaseOrder.executionFee
    ) = limitTradeHandler.decreaseOrders(_getSubAccount(address(this), 7), 0);
    assertEq(decreaseOrder.account, address(this));
    assertEq(decreaseOrder.subAccountId, 7);
    assertEq(decreaseOrder.marketIndex, 3);
    assertEq(decreaseOrder.sizeDelta, 3000 * 1e30);
    assertEq(decreaseOrder.isLong, false);
    assertEq(decreaseOrder.triggerPrice, 3000 * 1e30);
    assertEq(decreaseOrder.triggerAboveThreshold, false);
    assertEq(decreaseOrder.executionFee, 0.1 ether);
  }
}
