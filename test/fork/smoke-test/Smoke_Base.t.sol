// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

// to-upgrade contract
import { HLP } from "@hmx/contracts/HLP.sol";
import { Calculator } from "@hmx/contracts/Calculator.sol";

import { BotHandler } from "@hmx/handlers/BotHandler.sol";
import { Ext01Handler } from "@hmx/handlers/Ext01Handler.sol";
import { LimitTradeHandler } from "@hmx/handlers/LimitTradeHandler.sol";

import { TradeService } from "@hmx/services/TradeService.sol";
import { CrossMarginService } from "@hmx/services/CrossMarginService.sol";

import { TradeHelper } from "@hmx/helpers/TradeHelper.sol";
import { OrderReader } from "@hmx/readers/OrderReader.sol";

import { ConfigStorage } from "@hmx/storages/ConfigStorage.sol";
import { TraderLoyaltyCredit } from "@hmx/tokens/TraderLoyaltyCredit.sol";

// interfaces
import { ICalculator } from "@hmx/contracts/interfaces/ICalculator.sol";
import { IEcoPythCalldataBuilder } from "@hmx/oracles/interfaces/IEcoPythCalldataBuilder.sol";
import { IEcoPyth } from "@hmx/oracles/interfaces/IEcoPyth.sol";
import { PythStructs } from "pyth-sdk-solidity/IPyth.sol";
import { IHLP } from "@hmx/contracts/interfaces/IHLP.sol";
import { ITradeHelper } from "@hmx/helpers/interfaces/ITradeHelper.sol";
import { IOracleMiddleware } from "@hmx/oracles/interfaces/IOracleMiddleware.sol";

// Storage
import { IPerpStorage } from "@hmx/storages/interfaces/IPerpStorage.sol";
import { IConfigStorage } from "@hmx/storages/interfaces/IConfigStorage.sol";
import { IVaultStorage } from "@hmx/storages/interfaces/IVaultStorage.sol";

// Service
import { ILiquidationService } from "@hmx/services/interfaces/ILiquidationService.sol";
import { ITradeService } from "@hmx/services/interfaces/ITradeService.sol";
import { ICrossMarginService } from "@hmx/services/interfaces/ICrossMarginService.sol";

// Reader
import { IOrderReader } from "@hmx/readers/interfaces/IOrderReader.sol";
import { ILiquidationReader } from "@hmx/readers/interfaces/ILiquidationReader.sol";
import { IPositionReader } from "@hmx/readers/interfaces/IPositionReader.sol";

// Handler
import { IBotHandler } from "@hmx/handlers/interfaces/IBotHandler.sol";
import { ILimitTradeHandler } from "@hmx/handlers/interfaces/ILimitTradeHandler.sol";

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { HMXLib } from "@hmx/libraries/HMXLib.sol";

contract Smoke_Base is Test {
  ITradeHelper public tradeHelper;
  IEcoPyth public ecoPyth;

  IHLP public hlp;

  // services
  ICrossMarginService public crossMarginService;
  ITradeService public tradeService;
  ILiquidationService public liquidationService;

  // handlers
  IBotHandler public botHandler;
  ILimitTradeHandler public limitHandler;

  // readers
  ILiquidationReader public liquidationReader;
  IPositionReader public positionReader;
  IOrderReader public orderReader;

  // storages
  IConfigStorage public configStorage;
  IPerpStorage public perpStorage;
  IVaultStorage public vaultStorage;
  ICalculator public calculator;

  IEcoPythCalldataBuilder public ecoPythBuilder;

  ProxyAdmin public proxyAdmin;

  IOracleMiddleware public oracleMiddleware = IOracleMiddleware(0x9c83e1046dA4727F05C6764c017C6E1757596592);

  address public constant OWNER = 0x6409ba830719cd0fE27ccB3051DF1b399C90df4a;
  address public constant POS_MANAGER = 0xF1235511e36f2F4D578555218c41fe1B1B5dcc1E; // set market status;
  address public ALICE;
  address public BOB;

  uint256 private constant _fixedBlock = 18133917;

  function setUp() public virtual {
    ALICE = makeAddr("Alice");
    BOB = makeAddr("BOB");

    vm.createSelectFork(vm.envString("ARBITRUM_ONE_FORK"));
    /// NOTE Current tests work with block: `_fixedBlock`.
    ///      However, due to unknown reason,
    ///      When rollFork/assign block.number, it'll be reverted.

    // -- UPGRADE -- //
    vm.startPrank(proxyAdmin.owner());
    Calculator newCalculator = new Calculator();
    proxyAdmin.upgrade(
      TransparentUpgradeableProxy(payable(0x0FdE910552977041Dc8c7ef652b5a07B40B9e006)),
      address(newCalculator)
    );

    HLP newHlp = new HLP();
    proxyAdmin.upgrade(
      TransparentUpgradeableProxy(payable(0x4307fbDCD9Ec7AEA5a1c2958deCaa6f316952bAb)),
      address(newHlp)
    );

    BotHandler newBotHandler = new BotHandler();
    proxyAdmin.upgrade(
      TransparentUpgradeableProxy(payable(0xD4CcbDEbE59E84546fd3c4B91fEA86753Aa3B671)),
      address(newBotHandler)
    );

    LimitTradeHandler newLimitHandler = new LimitTradeHandler();
    proxyAdmin.upgrade(
      TransparentUpgradeableProxy(payable(0xeE116128b9AAAdBcd1f7C18608C5114f594cf5D6)),
      address(newLimitHandler)
    );

    TraderService newTradeService = new TradeService();
    proxyAdmin.upgrade(
      TransparentUpgradeableProxy(payable(0xcf533D0eEFB072D1BB68e201EAFc5368764daA0E)),
      address(newTradeService)
    );

    CrossMarginService newCrossMarginService = new CrossMarginService();
    proxyAdmin.upgrade(
      TransparentUpgradeableProxy(payable(0x0a8D9c0A4a039dDe3Cb825fF4c2f063f8B54313A)),
      address(newCrossMarginService)
    );

    TradeHelper newTradeHelper = new TradeHelper();
    proxyAdmin.upgrade(
      TransparentUpgradeableProxy(payable(0x963Cbe4cFcDC58795869be74b80A328b022DE00C)),
      address(newTradeHelper)
    );

    ConfigStorage newConfigStorage = new ConfigStorage();
    proxyAdmin.upgrade(
      TransparentUpgradeableProxy(payable(0xF4F7123fFe42c4C90A4bCDD2317D397E0B7d7cc0)),
      address(newConfigStorage)
    );

    TraderLoyaltyCredit newTradeLoyaltyCredit = new TraderLoyaltyCredit();
    proxyAdmin.upgrade(
      TransparentUpgradeableProxy(payable(0x1fDcB022daECA9326a37A318f143A0feD61abba6)),
      address(newTradeLoyaltyCredit)
    );

    // load contract
    configStorage = IConfigStorage(0xF4F7123fFe42c4C90A4bCDD2317D397E0B7d7cc0);
    perpStorage = IPerpStorage(0x97e94BdA44a2Df784Ab6535aaE2D62EFC6D2e303);
    vaultStorage = IVaultStorage(0x56CC5A9c0788e674f17F7555dC8D3e2F1C0313C0);
    limitHandler = ILimitTradeHandler(0xeE116128b9AAAdBcd1f7C18608C5114f594cf5D6);

    OrderReader newOrderReader = new OrderReader(
      address(configStorage),
      address(perpStorage),
      address(oracleMiddleware),
      address(limitHandler)
    );

    proxyAdmin.upgrade(
      TransparentUpgradeableProxy(payable(0x963Cbe4cFcDC58795869be74b80A328b022DE00C)),
      address(newOrderReader)
    );

    // Has not been deployed yet
    // Ext01Handler newExt01Handler = new Ext01Handler();
    // proxyAdmin.upgrade(
    //   TransparentUpgradeableProxy(payable(xxx)),
    //   address(newExt01Handler)
    // );

    vm.stopPrank();

    // -- LOAD FORK & UPGRADED -- //
    vm.startPrank(OWNER); // in case of setting something..
    calculator = ICalculator(0x0FdE910552977041Dc8c7ef652b5a07B40B9e006);
    hlp = IHLP(0x4307fbDCD9Ec7AEA5a1c2958deCaa6f316952bAb);

    // services
    crossMarginService = ICrossMarginService(0x0a8D9c0A4a039dDe3Cb825fF4c2f063f8B54313A);
    tradeService = ITradeService(0xcf533D0eEFB072D1BB68e201EAFc5368764daA0E);
    liquidationService = ILiquidationService(0x34E89DEd96340A177856fD822366AfC584438750);

    // handler
    botHandler = IBotHandler(0xD4CcbDEbE59E84546fd3c4B91fEA86753Aa3B671);

    // readers
    liquidationReader = ILiquidationReader(0x9f13335e769208a2545047aCb0ea386Cce7F5f8F);
    positionReader = IPositionReader(0x64706D5f177B892b1cEebe49cd9F02B90BB6FF03);
    orderReader = IOrderReader(0x0E6be5E7891f0835bb9E2a4F5410698E2aa02614);

    ecoPyth = IEcoPyth(0x8dc6A40465128B20DC712C6B765a5171EF30bB7B);
    tradeHelper = ITradeHelper(0x963Cbe4cFcDC58795869be74b80A328b022DE00C);
    proxyAdmin = ProxyAdmin(0x2E7983f9A1D08c57989eEA20adC9242321dA6589);
    ecoPythBuilder = IEcoPythCalldataBuilder(0x4c3eC30d33c6CfC8B0806Bf049eA907FE4a0AB4F); // UnsafeEcoPythCalldataBuilder

    vm.stopPrank();
  }

  function _getSubAccount(address primary, uint8 subAccountId) internal pure returns (address) {
    return address(uint160(primary) ^ uint160(subAccountId));
  }

  function _getPositionId(address _account, uint8 _subAccountId, uint256 _marketIndex) internal pure returns (bytes32) {
    address _subAccount = _getSubAccount(_account, _subAccountId);
    return keccak256(abi.encodePacked(_subAccount, _marketIndex));
  }

  function _setTickPriceZero()
    internal
    view
    returns (bytes32[] memory priceUpdateData, bytes32[] memory publishTimeUpdateData)
  {
    int24[] memory tickPrices = new int24[](34);
    uint24[] memory publishTimeDiffs = new uint24[](34);
    for (uint i = 0; i < 34; i++) {
      tickPrices[i] = 0;
      publishTimeDiffs[i] = 0;
    }

    priceUpdateData = ecoPyth.buildPriceUpdateData(tickPrices);
    publishTimeUpdateData = ecoPyth.buildPublishTimeUpdateData(publishTimeDiffs);
  }

  function _setPriceData(
    uint64 _priceE8
  ) internal view returns (bytes32[] memory assetIds, uint64[] memory prices, bool[] memory shouldInverts) {
    bytes32[] memory pythRes = ecoPyth.getAssetIds();
    uint256 len = pythRes.length; // 35 - 1(index 0) = 34
    assetIds = new bytes32[](len - 1);
    prices = new uint64[](len - 1);
    shouldInverts = new bool[](len - 1);

    for (uint i = 1; i < len; i++) {
      assetIds[i - 1] = pythRes[i];
      prices[i - 1] = _priceE8 * 1e8;
      if (i == 4) {
        shouldInverts[i - 1] = true; // JPY
      } else {
        shouldInverts[i - 1] = false;
      }
    }
  }

  function _buildDataForPrice() internal view returns (IEcoPythCalldataBuilder.BuildData[] memory data) {
    bytes32[] memory pythRes = ecoPyth.getAssetIds();

    uint256 len = pythRes.length; // 35 - 1(index 0) = 34

    data = new IEcoPythCalldataBuilder.BuildData[](len - 1);

    for (uint i = 1; i < len; i++) {
      PythStructs.Price memory _ecoPythPrice = ecoPyth.getPriceUnsafe(pythRes[i]);
      data[i - 1].assetId = pythRes[i];
      data[i - 1].priceE8 = _ecoPythPrice.price;
      data[i - 1].publishTime = uint160(block.timestamp);
      data[i - 1].maxDiffBps = 15_000;
    }
  }

  function _validateClosedPosition(bytes32 _id) internal {
    IPerpStorage.Position memory _position = perpStorage.getPositionById(_id);
    // As the position has been closed, the gotten one should be empty stuct
    assertEq(_position.primaryAccount, address(0));
    assertEq(_position.marketIndex, 0);
    assertEq(_position.avgEntryPriceE30, 0);
    assertEq(_position.entryBorrowingRate, 0);
    assertEq(_position.reserveValueE30, 0);
    assertEq(_position.lastIncreaseTimestamp, 0);
    assertEq(_position.positionSizeE30, 0);
    assertEq(_position.realizedPnl, 0);
    assertEq(_position.lastFundingAccrued, 0);
    assertEq(_position.subAccountId, 0);
  }

  function _checkIsUnderMMR(
    address _primaryAccount,
    uint8 _subAccountId,
    uint256 _marketIndex,
    uint256 _limitPriceE30
  ) internal view returns (bool) {
    address _subAccount = HMXLib.getSubAccount(_primaryAccount, _subAccountId);
    IConfigStorage.MarketConfig memory config = configStorage.getMarketConfigByIndex(_marketIndex);

    int256 _subAccountEquity = calculator.getEquity(_subAccount, _limitPriceE30, config.assetId);
    uint256 _mmr = calculator.getMMR(_subAccount);
    if (_subAccountEquity < 0 || uint256(_subAccountEquity) < _mmr) return true;
    return false;
  }
}