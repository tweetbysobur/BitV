// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IVaultReentrancyTarget {
    function deposit(uint256 assets, address receiver) external returns (uint256);
}

/// @notice Test-only malicious ERC20: on `transferFrom`, attempts to
/// re-enter a configured target's `deposit` before completing the
/// transfer. Used to prove BitVYieldVault's `nonReentrant` guard
/// actually blocks reentrancy, mirroring MockReentrantERC20's role for
/// BitVPoolManager.
contract MockReentrantVaultERC20 is ERC20 {
    address public attackTarget;
    bool public attackEnabled;

    constructor() ERC20("Malicious Vault Token", "EVILV") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function configureAttack(address target, bool enabled) external {
        attackTarget = target;
        attackEnabled = enabled;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (attackEnabled) {
            attackEnabled = false;
            IVaultReentrancyTarget(attackTarget).deposit(amount, address(this));
        }
        return super.transferFrom(from, to, amount);
    }
}
