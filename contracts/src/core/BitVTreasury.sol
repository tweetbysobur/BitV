// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BitVRoleConsumer} from "../access/BitVRoleConsumer.sol";
import {ProtocolErrors} from "../libraries/ProtocolErrors.sol";

/**
 * @title BitVTreasury
 * @notice Protocol treasury — receives liquidation and reserve-factor
 * interest fees from BitVPoolManager / BitVLendingManager, and lets
 * PROTOCOL_ADMIN_ROLE withdraw them. Not compliance-gated: this is an
 * internal protocol contract, not a user-facing pool/lending/vault
 * surface, so it isn't in the compliance-hook list. No governance
 * (multisig/DAO voting) yet, per this milestone's scope — just role-gated
 * withdrawal.
 */
contract BitVTreasury is BitVRoleConsumer {
    using SafeERC20 for IERC20;

    event FeeReceived(address indexed asset, address indexed from, uint256 amount);
    event Withdrawn(address indexed asset, address indexed to, uint256 amount);

    constructor(address accessManager) BitVRoleConsumer(accessManager) {}

    /// @notice Pulls `amount` of `asset` from the caller (a BitV protocol
    /// contract that has already approved this treasury, or is
    /// forwarding a transfer it already received). Any caller may credit
    /// the treasury — there's no reason to restrict deposits.
    function receiveFee(address asset, uint256 amount) external {
        if (amount == 0) revert ProtocolErrors.ZeroAmount();
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        emit FeeReceived(asset, msg.sender, amount);
    }

    function withdraw(address asset, uint256 amount, address to) external onlyRole(ACCESS_MANAGER.PROTOCOL_ADMIN_ROLE()) {
        if (to == address(0)) revert ProtocolErrors.ZeroAddress();
        if (amount == 0) revert ProtocolErrors.ZeroAmount();
        IERC20(asset).safeTransfer(to, amount);
        emit Withdrawn(asset, to, amount);
    }
}
