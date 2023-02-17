// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { ICalculator } from "../../src/contracts/interfaces/ICalculator.sol";
import { IConfigStorage } from "../../src/storages/interfaces/IConfigStorage.sol";
import { IVaultStorage } from "../../src/storages/interfaces/IVaultStorage.sol";

contract MockCalculator is ICalculator {
  uint256 equity;
  uint256 mmr;

  address public oracle;

  constructor(address _oracle) {
    oracle = _oracle;
  }

  function setEquity(uint256 _mockEquity) external {
    equity = _mockEquity;
  }

  function setMMR(uint256 _mockMmr) external {
    mmr = _mockMmr;
  }

  function getEquity(
    address /* _subAccount */
  ) external view returns (uint256) {
    return equity;
  }

  function getMMR(address /* _subAccount */) external view returns (uint256) {
    return mmr;
  }

  function getAUM(bool /* isMaxPrice */) external pure returns (uint256) {
    return 0;
  }

  function getAUME30(bool /* isMaxPrice */) external pure returns (uint256) {
    return 0;
  }

  function getPLPPrice(
    uint256 /* aum */,
    uint256 /* supply */
  ) external pure returns (uint256) {
    // 1$
    return 1e30;
  }

  function getMintAmount(
    uint256 _aum,
    uint256 _totalSupply,
    uint256 _amount
  ) external pure returns (uint256) {
    return
      _aum == 0 || _totalSupply == 0
        ? _amount
        : (_amount * _totalSupply) / _aum;
  }

  function convertTokenDecimals(
    uint256 /* _fromTokenDecimals */,
    uint256 /* _toTokenDecimals */,
    uint256 /* _amount */
  ) external pure returns (uint256) {
    return 0;
  }

  function getAddLiquidityFeeRate(
    address /*_token*/,
    uint256 /*_tokenValue*/,
    IConfigStorage /*_configStorage*/,
    IVaultStorage /*_vaultStorage*/
  ) external pure returns (uint256) {
    return 0;
  }

  function getRemoveLiquidityFeeRate(
    address /*_token*/,
    uint256 /*_tokenValueE30*/,
    IConfigStorage /*_configStorage*/,
    IVaultStorage /*_vaultStorage*/
  ) external pure returns (uint256) {
    return 1e18;
  }
}
