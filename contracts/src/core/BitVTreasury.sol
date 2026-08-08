// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ComplianceErrors} from "../libraries/ComplianceErrors.sol";

/**
 * @title BitVTreasury
 * @notice Protocol treasury — holds protocol-owned funds (reserves,
 * fees). Access-controlled by BitVAccessManager-style roles rather than
 * Cleanverse compliance: this is an internal protocol contract, not a
 * user-facing pool/lending/vault surface, so it isn't in this milestone's
 * compliance-hook list. Compliance foundation milestone: no fund logic yet.
 */
contract BitVTreasury is AccessControl {
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNANCE_ROLE, admin);
    }

    function withdraw(address asset, uint256 amount, address to) external onlyRole(GOVERNANCE_ROLE) {
        (asset, amount, to);
        revert ComplianceErrors.NotImplemented();
    }
}
