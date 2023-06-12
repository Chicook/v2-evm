// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { ReentrancyGuardUpgradeable } from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

// Interfaces
import { IHLP } from "./interfaces/IHLP.sol";

contract HLP is ReentrancyGuardUpgradeable, OwnableUpgradeable, ERC20Upgradeable {
  mapping(address => bool) public minters;

  event SetMinter(address indexed minter, bool isMinter);

  /**
   * Modifiers
   */

  modifier onlyMinter() {
    if (!minters[msg.sender]) {
      revert IHLP.IHLP_onlyMinter();
    }
    _;
  }

  function initialize() external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    ERC20Upgradeable.__ERC20_init("HLP", "Perp88 LP v2");
  }

  function setMinter(address minter, bool isMinter) external onlyOwner nonReentrant {
    minters[minter] = isMinter;
    emit SetMinter(minter, isMinter);
  }

  function mint(address to, uint256 amount) external onlyMinter nonReentrant {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external onlyMinter nonReentrant {
    _burn(from, amount);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}