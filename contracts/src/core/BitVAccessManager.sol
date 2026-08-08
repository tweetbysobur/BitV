// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title BitVAccessManager
 * @notice Protocol-internal role management for BitV's own contracts
 * (governance, pausers, etc.) — distinct from Cleanverse's
 * IAPassComplianceValidator, which gates end-user access to protected
 * actions. This contract answers "who can administer BitV," not "which
 * users are compliant."
 * @dev Compliance foundation milestone: roles only, no protocol logic yet.
 */
contract BitVAccessManager is AccessControl {
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNANCE_ROLE, admin);
    }
}
