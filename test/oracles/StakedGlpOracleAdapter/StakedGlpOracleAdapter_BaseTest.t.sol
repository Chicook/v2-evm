// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { BaseTest } from "@hmx-test/base/BaseTest.sol";
import { StakedGlpOracleAdapter } from "@hmx/oracles/StakedGlpOracleAdapter.sol";
import { IOracleAdapter } from "@hmx/oracles/interfaces/IOracleAdapter.sol";
import { Deployer } from "@hmx-test/libs/Deployer.sol";

contract StakedGlpOracleAdapter_BaseTest is BaseTest {
  IOracleAdapter internal stakedGlpOracleAdapter;

  function setUp() public virtual {
    stakedGlpOracleAdapter = Deployer.deployStakedGlpOracleAdapter(sglp, mockGlpManager, sglpAssetId);
  }
}