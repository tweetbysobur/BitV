// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ProtocolErrors} from "../libraries/ProtocolErrors.sol";

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
 * Build 05.1 adds two roles for the permissioned yield vault
 * (docs/yield-vault-specification.md §8), reusing PROTOCOL_ADMIN_ROLE/
 * RISK_MANAGER_ROLE/PAUSER_ROLE where the spec found them sufficient:
 * - VAULT_MANAGER_ROLE: day-to-day vault operations — deposit/
 *   withdrawal limits, vault cap, minimum liquidity reserve. Mirrors
 *   POOL_MANAGER_ROLE's scope for pools.
 * - STRATEGY_MANAGER_ROLE: setting/replacing a vault's active
 *   strategy, strategy allocation cap, emergency strategy exit. Kept
 *   separate from VAULT_MANAGER_ROLE because "which external code this
 *   vault trusts" is a materially different decision from liquidity/
 *   limit management.
 *
 * Build 06.1 adds two roles for the RWA collateral registry
 * (docs/rwa-market-specification.md §13), reusing RISK_MANAGER_ROLE/
 * PAUSER_ROLE directly rather than creating RWA-specific duplicates:
 * - RWA_ADMIN_ROLE: registers/updates RWA assets, sets status
 *   (Active/Frozen/Delisted), sets collateral caps and allowed debt
 *   assets.
 * - ORACLE_MANAGER_ROLE: wires/replaces an RWA asset's oracle and
 *   staleness threshold, and attests price freshness. Kept separate
 *   from RWA_ADMIN_ROLE for the same reason STRATEGY_MANAGER_ROLE is
 *   kept separate from VAULT_MANAGER_ROLE above.
 *
 * Users are never granted any of these roles.
 */
contract BitVAccessManager is AccessControl {
    bytes32 public constant PROTOCOL_ADMIN_ROLE = keccak256("PROTOCOL_ADMIN_ROLE");
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");
    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 public constant RWA_ADMIN_ROLE = keccak256("RWA_ADMIN_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    constructor(address admin) {
        if (admin == address(0)) revert ProtocolErrors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PROTOCOL_ADMIN_ROLE, admin);
        _grantRole(RISK_MANAGER_ROLE, admin);
        _grantRole(POOL_MANAGER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(VAULT_MANAGER_ROLE, admin);
        _grantRole(STRATEGY_MANAGER_ROLE, admin);
        _grantRole(RWA_ADMIN_ROLE, admin);
        _grantRole(ORACLE_MANAGER_ROLE, admin);
    }
}
