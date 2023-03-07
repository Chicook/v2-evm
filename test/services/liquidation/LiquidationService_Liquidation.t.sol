// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { LiquidationService_Base } from "./LiquidationService_Base.t.sol";

import { IPerpStorage } from "../../../src/storages/interfaces/IPerpStorage.sol";

import { AddressUtils } from "../../../src/libraries/AddressUtils.sol";

import { PositionTester02 } from "../../testers/PositionTester02.sol";

import { console } from "forge-std/console.sol";

// What is this test DONE
// - success
//   - liquidate
// - revert
//   - account healthy
contract LiquidationService_Liquidation is LiquidationService_Base {
  using AddressUtils for address;

  function setUp() public virtual override {
    super.setUp();
  }

  function testRevert_liquidate_WhenAccountHealthy() external {
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setPLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(15_000 * 1e30);

    // ETH price 1600 USD
    mockOracle.setPrice(address(weth).toBytes32(), 1_600 * 1e30);

    // BTC price 25000 USD
    mockOracle.setPrice(address(wbtc).toBytes32(), 25_000 * 1e30);

    // USDT price 1600 USD
    mockOracle.setPrice(address(usdt).toBytes32(), 1 * 1e30);

    address aliceAddress = getSubAccount(ALICE, 0);

    vaultStorage.setTraderBalance(aliceAddress, address(usdt), 10_000 * 1e6);
    vaultStorage.setTraderBalance(aliceAddress, address(wbtc), 0.3 * 1e8);

    tradeService.increasePosition(ALICE, 0, ethMarketIndex, 1_000_000 * 1e30, 0);
    tradeService.increasePosition(ALICE, 0, btcMarketIndex, 500_000 * 1e30, 0);

    // BTC price 24600 USD
    mockOracle.setPrice(address(wbtc).toBytes32(), 24_500 * 1e30);

    mockCalculator.setEquity(aliceAddress, 16_000 * 1e30);
    mockCalculator.setMMR(aliceAddress, 7_500 * 1e30);
    mockCalculator.setUnrealizedPnl(aliceAddress, 0);

    vm.expectRevert(abi.encodeWithSignature("ILiquidationService_AccountHealthy()"));
    liquidationService.liquidate(aliceAddress);
  }

  function testCorrectness_liquidate_WhenBadDebt() external {
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setPLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(15_000 * 1e30);

    // ETH price 1600 USD
    mockOracle.setPrice(address(weth).toBytes32(), 1_600 * 1e30);

    // BTC price 25000 USD
    mockOracle.setPrice(address(wbtc).toBytes32(), 25_000 * 1e30);

    // USDT price 1600 USD
    mockOracle.setPrice(address(usdt).toBytes32(), 1 * 1e30);

    address aliceAddress = getSubAccount(ALICE, 0);

    vaultStorage.setTraderBalance(aliceAddress, address(usdt), 10_000 * 1e6);
    vaultStorage.setTraderBalance(aliceAddress, address(wbtc), 0.3 * 1e8);

    bytes32 _wethPositionId = getPositionId(ALICE, 0, ethMarketIndex);
    bytes32 _wbtcPositionId = getPositionId(ALICE, 0, ethMarketIndex);

    tradeService.increasePosition(ALICE, 0, ethMarketIndex, 1_000_000 * 1e30, 0);
    tradeService.increasePosition(ALICE, 0, btcMarketIndex, 500_000 * 1e30, 0);

    // BTC price 24000 USD
    mockOracle.setPrice(address(wbtc).toBytes32(), 24_000 * 1e30);

    mockCalculator.setEquity(aliceAddress, -4_240 * 1e30);
    mockCalculator.setMMR(aliceAddress, 7_500 * 1e30);
    mockCalculator.setUnrealizedPnl(aliceAddress, -20_000 * 1e30);

    liquidationService.liquidate(aliceAddress);

    PositionTester02.PositionAssertionData memory assertData = PositionTester02.PositionAssertionData({
      size: 0,
      avgPrice: 0,
      reserveValue: 0,
      lastIncreaseTimestamp: 0,
      openInterest: 0
    });
    // reset position
    positionTester02.assertPosition(_wethPositionId, assertData);
    positionTester02.assertPosition(_wbtcPositionId, assertData);

    // 0.3 * 24,000 = 7,200
    // 20,005 - 7,200 = 12,805
    // 12,805 / 1 = 12,805
    // 10,000 - 12,805 = -2,805
    assertEq(vaultStorage.plpLiquidity(address(wbtc)), 0.3 * 1e8);
    assertEq(vaultStorage.plpLiquidity(address(usdt)), 10_000 * 1e6);
    assertEq(vaultStorage.traderBalances(aliceAddress, address(wbtc)), 0);
    assertEq(vaultStorage.traderBalances(aliceAddress, address(usdt)), 0);

    assertEq(perpStorage.getBadDebt(aliceAddress), 2_805 * 1e30);
  }

  function testCorrectness_liquidate() external {
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setPLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(15_000 * 1e30);

    // ETH price 1600 USD
    mockOracle.setPrice(address(weth).toBytes32(), 1_600 * 1e30);

    // BTC price 25000 USD
    mockOracle.setPrice(address(wbtc).toBytes32(), 25_000 * 1e30);

    // USDT price 1600 USD
    mockOracle.setPrice(address(usdt).toBytes32(), 1 * 1e30);

    address aliceAddress = getSubAccount(ALICE, 0);

    vaultStorage.setTraderBalance(aliceAddress, address(usdt), 10_000 * 1e6);
    vaultStorage.setTraderBalance(aliceAddress, address(wbtc), 0.3 * 1e8);

    bytes32 _wethPositionId = getPositionId(ALICE, 0, ethMarketIndex);
    bytes32 _wbtcPositionId = getPositionId(ALICE, 0, ethMarketIndex);

    tradeService.increasePosition(ALICE, 0, ethMarketIndex, 1_000_000 * 1e30, 0);
    tradeService.increasePosition(ALICE, 0, btcMarketIndex, 500_000 * 1e30, 0);

    // BTC price 24500 USD
    mockOracle.setPrice(address(wbtc).toBytes32(), 24_500 * 1e30);

    mockCalculator.setEquity(aliceAddress, 5_880 * 1e30);
    mockCalculator.setMMR(aliceAddress, 7_500 * 1e30);
    mockCalculator.setUnrealizedPnl(aliceAddress, -10_000 * 1e30);

    liquidationService.liquidate(aliceAddress);

    PositionTester02.PositionAssertionData memory assertData = PositionTester02.PositionAssertionData({
      size: 0,
      avgPrice: 0,
      reserveValue: 0,
      lastIncreaseTimestamp: 0,
      openInterest: 0
    });
    // reset position
    positionTester02.assertPosition(_wethPositionId, assertData);
    positionTester02.assertPosition(_wbtcPositionId, assertData);

    // 0.3 * 24,500 = 7,350
    // 10,005 - 7,350 = 2,655
    // 2,655 / 1 = 2,655
    // 10,000 - 2,655 = 7,345
    assertEq(vaultStorage.plpLiquidity(address(wbtc)), 0.3 * 1e8);
    assertEq(vaultStorage.plpLiquidity(address(usdt)), 2_655 * 1e6);
    assertEq(vaultStorage.traderBalances(aliceAddress, address(wbtc)), 0);
    assertEq(vaultStorage.traderBalances(aliceAddress, address(usdt)), 7_345 * 1e6);

    assertEq(perpStorage.getBadDebt(aliceAddress), 0);
  }
}