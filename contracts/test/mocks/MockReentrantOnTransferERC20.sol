// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test-only malicious ERC20: on the *outgoing* `transfer` (as
/// opposed to MockReentrantERC20's `transferFrom` hook), attempts to
/// re-enter an arbitrary call against a configured target before
/// completing the transfer. Used to prove `claimReserve`'s
/// `nonReentrant` guard blocks reentrancy triggered by the token
/// transfer BitVPoolManager makes to the treasury.
contract MockReentrantOnTransferERC20 is ERC20 {
    address public attackTarget;
    bytes public attackCalldata;
    bool public attackEnabled;

    constructor() ERC20("Malicious Outgoing Token", "EVIL2") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function configureAttack(address target, bytes calldata callData, bool enabled) external {
        attackTarget = target;
        attackCalldata = callData;
        attackEnabled = enabled;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (attackEnabled) {
            attackEnabled = false; // prevent infinite recursion in the attack itself
            // A plain call, not a swallowed low-level `.call` — a revert
            // here (e.g. the target's `nonReentrant` guard tripping) must
            // propagate up through this transfer and fail the whole
            // outer transaction, exactly like a real reentrancy attempt.
            (bool ok, bytes memory returndata) = attackTarget.call(attackCalldata);
            if (!ok) {
                assembly {
                    revert(add(returndata, 32), mload(returndata))
                }
            }
        }
        return super.transfer(to, amount);
    }
}
