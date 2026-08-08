// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title BitVAccessManager
 * @notice Protocol-internal role management for BitV's own contracts —
 * distinct from Cleanverse's IAPassComplianceValidator, which gates
 * end-user access to protected actions. This contract answers "who can
 * administer BitV," not "which users are compliant."
 *
 * Four roles, per the Build 03 architecture requirement to separate:
 * - PROTOCOL_ADMIN_ROLE: highest privilege — creates pools, sets the
 *   BitVLendingManager address on BitVPoolManager, treasury changes.
 * - RISK_MANAGER_ROLE: tunes risk parameters (LTV, liquidation
 *   threshold/bonus, interest rate model params, supply/borrow caps).
 * - POOL_MANAGER_ROLE: day-to-day pool operations (enabling/disabling
 *   borrowing or collateral use on an existing pool).
 * - PAUSER_ROLE: emergency pause only — deliberately narrower than
 *   PROTOCOL_ADMIN_ROLE so an incident responder doesn't also need
 *   risk-parameter or pool-creation power.
 *
 * Users are never granted any of these roles.
 */
contract BitVAccessManager is AccessControl {
    bytes32 public constant PROTOCOL_ADMIN_ROLE = keccak256("PROTOCOL_ADMIN_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");
    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PROTOCOL_ADMIN_ROLE, admin);
        _grantRole(RISK_MANAGER_ROLE, admin);
        _grantRole(POOL_MANAGER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }
}
