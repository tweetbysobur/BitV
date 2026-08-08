// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BitVAccessManager} from "../core/BitVAccessManager.sol";
import {ProtocolErrors} from "../libraries/ProtocolErrors.sol";

/**
 * @title BitVRoleConsumer
 * @notice Shared base for BitV protocol contracts that check roles
 * against a central BitVAccessManager, instead of each contract holding
 * its own separate AccessControl role set. Kept deliberately separate
 * from BitVComplianceGuard: that contract's `Ownable` is specifically for
 * Cleanverse's documented RuleV2 rule-management pattern (see its
 * NatSpec); this is BitV's own protocol-admin/risk-manager/pool-manager/
 * pauser separation and has nothing to do with Cleanverse.
 */
abstract contract BitVRoleConsumer {
    BitVAccessManager public immutable ACCESS_MANAGER;

    constructor(address accessManager) {
        if (accessManager == address(0)) revert ProtocolErrors.ZeroAddress();
        ACCESS_MANAGER = BitVAccessManager(accessManager);
    }

    modifier onlyRole(bytes32 role) {
        if (!ACCESS_MANAGER.hasRole(role, msg.sender)) {
            revert ProtocolErrors.Unauthorized(msg.sender, role);
        }
        _;
    }
}
