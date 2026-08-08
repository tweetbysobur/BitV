// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IReentrancyTarget {
    function deposit(address asset, uint256 amount) external;
}

/// @notice Test-only malicious ERC20: on `transferFrom`, attempts to
/// re-enter a configured target's `deposit` before completing the
/// transfer. Used to prove BitVPoolManager's `nonReentrant` guard
/// actually blocks reentrancy, not just to assert it exists.
contract MockReentrantERC20 is ERC20 {
    address public attackTarget;
    bool public attackEnabled;

    constructor() ERC20("Malicious Token", "EVIL") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function configureAttack(address target, bool enabled) external {
        attackTarget = target;
        attackEnabled = enabled;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (attackEnabled) {
            attackEnabled = false; // prevent infinite recursion in the attack itself
            IReentrancyTarget(attackTarget).deposit(address(this), amount);
        }
        return super.transferFrom(from, to, amount);
    }
}
