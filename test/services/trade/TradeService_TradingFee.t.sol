// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { TradeService_Base } from "./TradeService_Base.t.sol";

import { IPerpStorage } from "../../../src/storages/interfaces/IPerpStorage.sol";
import { IConfigStorage } from "../../../src/storages/interfaces/IConfigStorage.sol";

import { AddressUtils } from "../../../src/libraries/AddressUtils.sol";

contract TradeService_TradingFee is TradeService_Base {
  using AddressUtils for address;

  function setUp() public virtual override {
    super.setUp();

    // Ignore Borrowing fee on this test
    IConfigStorage.AssetClassConfig memory _cryptoConfig = IConfigStorage.AssetClassConfig({ baseBorrowingRate: 0 });
    configStorage.setAssetClassConfigByIndex(0, _cryptoConfig);

    // Ignore Developer fee on this test
    configStorage.setTradingConfig(
      IConfigStorage.TradingConfig({ fundingInterval: 1, devFeeRate: 0, minProfitDuration: 0, maxPosition: 5 })
    );

    // Set increase/decrease position fee rate to 0.0001%
    IConfigStorage.MarketConfig memory _marketConfig = configStorage.getMarketConfigByIndex(ethMarketIndex);
    _marketConfig.increasePositionFeeRate = 0.0001 * 1e18;
    _marketConfig.decreasePositionFeeRate = 0.0001 * 1e18;
    configStorage.setMarketConfig(ethMarketIndex, _marketConfig);
  }

  function testCorrectness_tradingFee_usedOneCollateral() external {
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setPLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(10_000 * 1e30);

    // ETH price 1600 USD
    mockOracle.setPrice(address(weth).toBytes32(), 1500 * 1e30);
    // USDT price 1 USD
    mockOracle.setPrice(address(usdt).toBytes32(), 1 * 1e30);

    address aliceAddress = getSubAccount(ALICE, 0);
    vaultStorage.setTraderBalance(aliceAddress, address(weth), 10 * 1e18);
    vaultStorage.setTraderBalance(aliceAddress, address(usdt), 100 * 1e6);

    vm.warp(100);
    {
      // Before ALICE start increases LONG position
      {
        assertEq(vaultStorage.fees(address(weth)), 0);
        assertEq(vaultStorage.traderBalances(aliceAddress, address(weth)), 10 * 1e18);
        assertEq(vaultStorage.traderBalances(aliceAddress, address(usdt)), 100 * 1e6);
      }

      tradeService.increasePosition(ALICE, 0, ethMarketIndex, 1_000_000 * 1e30);

      // After ALICE increased LONG position
      {
        // trading Fee = size * increase position fee = 1_000_000 * 0.0001 = 100 USDC
        // trading Fee in WETH amount =  100/1500 = 0.06666666666666667 WETH
        assertEq(vaultStorage.fees(address(weth)), 66666666666666666);
        // Alice WETH's balance after pay trading Fee = 10 - 0.06666666666666667 = 9.933333333333334 WETH;
        assertEq(vaultStorage.traderBalances(aliceAddress, address(weth)), 9933333333333333334);
        assertEq(vaultStorage.traderBalances(aliceAddress, address(usdt)), 100 * 1e6);

        // Ignore Borrowing, Funding, and Dev Fees
        assertEq(vaultStorage.marginFee(address(weth)), 0);
        assertEq(vaultStorage.devFees(address(weth)), 0);
      }
    }

    vm.warp(110);
    {
      tradeService.increasePosition(ALICE, 0, ethMarketIndex, 600_000 * 1e30);

      // After ALICE increased LONG position
      {
        // Alice already paid last trading fee, so Alice has no fee remaining
        assertEq(perpStorage.getSubAccountFee(aliceAddress), 0);

        // trading Fee = size * increase position fee = 600_000 * 0.0001 = 60 USDC
        // trading Fee in WETH amount =  60/1500 = 0.04 WETH
        assertEq(vaultStorage.fees(address(weth)), 66666666666666666 + 40000000000000000); // 0.066 + 0.04 WETH
        // Alice WETH's balance after pay trading Fee = 9.933333333333334 - 0.04 = 9.893333333333334 WETH;
        assertEq(vaultStorage.traderBalances(aliceAddress, address(weth)), 9893333333333333334);
        assertEq(vaultStorage.traderBalances(aliceAddress, address(usdt)), 100 * 1e6);

        // Ignore Borrowing, Funding, and Dev Fees
        assertEq(vaultStorage.marginFee(address(weth)), 0);
        assertEq(vaultStorage.devFees(address(weth)), 0);
      }
    }
  }

  function testCorrectness_tradingFee_usedManyCollaterals() external {
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setPLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(10_000 * 1e30);

    // ETH price 1600 USD
    mockOracle.setPrice(address(weth).toBytes32(), 1500 * 1e30);
    // USDT price 1 USD
    mockOracle.setPrice(address(usdt).toBytes32(), 1 * 1e30);

    address aliceAddress = getSubAccount(ALICE, 0);
    vaultStorage.setTraderBalance(aliceAddress, address(weth), 0.01 * 1e18);
    vaultStorage.setTraderBalance(aliceAddress, address(usdt), 100_000 * 1e6);

    vm.warp(100);
    {
      // Before ALICE start increases LONG position
      {
        assertEq(vaultStorage.fees(address(weth)), 0);
        assertEq(vaultStorage.traderBalances(aliceAddress, address(weth)), 0.01 * 1e18);
        assertEq(vaultStorage.traderBalances(aliceAddress, address(usdt)), 100_000 * 1e6);
      }

      tradeService.increasePosition(ALICE, 0, ethMarketIndex, 600_000 * 1e30);

      // After ALICE increased LONG position
      {
        // trading Fee = size * increase position fee = 600_000 * 0.0001 = 60 USDC
        // trading Fee in WETH amount =  60/1500 = 0.04 WETH
        // Alice WETH's balance after pay trading fee = 0.01 - 0.04 = 0 WETH;
        assertEq(vaultStorage.traderBalances(aliceAddress, address(weth)), 0);
        assertEq(vaultStorage.fees(address(weth)), 10000000000000000); // 0.01 WETH
        // ALICE USDC's balance after pay trading fee = USDC token - remaining Debt amount  = 100_000 USDC - (0.06666666666666667 - 0.01)*1500 = 100 - 85 = 99955 USDC
        assertEq(vaultStorage.traderBalances(aliceAddress, address(usdt)), (100_000 - 45) * 1e6);

        // Ignore Borrowing, Funding, and Dev Fees
        assertEq(vaultStorage.marginFee(address(weth)), 0);
        assertEq(vaultStorage.devFees(address(weth)), 0);
      }
    }
  }

  function testCorrectness_tradingFee_WhenDecreasePosition() external {
    // TVL
    // 1000000 USDT -> 1000000 USD
    mockCalculator.setPLPValue(1_000_000 * 1e30);
    // ALICE add collateral
    // 10000 USDT -> free collateral -> 10000 USD
    mockCalculator.setFreeCollateral(10_000 * 1e30);

    // ETH price 1600 USD
    mockOracle.setPrice(address(weth).toBytes32(), 1600 * 1e30);
    // USDT price 1 USD
    mockOracle.setPrice(address(usdt).toBytes32(), 1 * 1e30);

    address aliceAddress = getSubAccount(ALICE, 0);

    vaultStorage.setTraderBalance(aliceAddress, address(usdt), 100_000 * 1e6);

    vm.warp(100);
    {
      tradeService.increasePosition(ALICE, 0, ethMarketIndex, 1_000_000 * 1e30);

      // trading Fee = size * increase position fee = 1_000_000 * 0.0001 = 100 USDC
      // Alice USDT's balance after pay trading fee = 100_000 - 100 = 99_900  USDC;
      assertEq(vaultStorage.traderBalances(aliceAddress, address(usdt)), 99_900 * 1e6);

      // Ignore Borrowing, Funding, and Dev Fees
      assertEq(vaultStorage.marginFee(address(weth)), 0);
      assertEq(vaultStorage.devFees(address(weth)), 0);
    }

    vm.warp(110);
    {
      tradeService.decreasePosition(ALICE, 0, ethMarketIndex, 500_000 * 1e30, address(0));

      // trading Fee = size * decrease position fee = 500_000 * 0.0001 = 50 USDC
      // Alice USDT's balance after pay trading fee = 99_900 - 50 = 99850  USDC;
      assertEq(vaultStorage.traderBalances(aliceAddress, address(usdt)), 99850 * 1e6);

      // Ignore Borrowing, Funding, and Dev Fees
      assertEq(perpStorage.getSubAccountFee(aliceAddress), 0);
      assertEq(vaultStorage.marginFee(address(usdt)), 0);
      assertEq(vaultStorage.devFees(address(usdt)), 0);
    }

    vm.warp(120);
    {
      // Close position
      tradeService.decreasePosition(ALICE, 0, ethMarketIndex, 500_000 * 1e30, address(0));

      // trading Fee = size * decrease position fee = 500_000 * 0.0001 = 50 USDC
      // Alice USDT's balance after pay trading fee = 99850 - 50 = 99800  USDC;
      assertEq(vaultStorage.traderBalances(aliceAddress, address(usdt)), 99800 * 1e6);

      // Ignore Borrowing, Funding, and Dev Fees
      assertEq(perpStorage.getSubAccountFee(aliceAddress), 0);
      assertEq(vaultStorage.marginFee(address(usdt)), 0);
      assertEq(vaultStorage.devFees(address(usdt)), 0);
    }
  }
}
