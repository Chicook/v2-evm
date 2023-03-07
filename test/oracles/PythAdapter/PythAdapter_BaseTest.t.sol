// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { BaseTest } from "../../base/BaseTest.sol";
import { PythAdapter } from "../../../src/oracles/PythAdapter.sol";
import { AddressUtils } from "../../../src/libraries/AddressUtils.sol";

contract PythAdapter_BaseTest is BaseTest {
  using AddressUtils for address;

  PythAdapter pythAdapter;

  function setUp() public virtual {
    DeployCoreReturnVars memory deployed = deployPerp88v2();
    pythAdapter = deployed.pythAdapter;
  }
}