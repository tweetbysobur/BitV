// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BitVComplianceGuard} from "../compliance/BitVComplianceGuard.sol";
import {ComplianceErrors} from "../libraries/ComplianceErrors.sol";

/**
 * @title BitVVaultManager
 * @notice Permissioned yield vault boundary. Compliance foundation
 * milestone: every protected action checks Cleanverse compliance first
 * and then reverts NotImplemented — no yield strategy logic yet.
 */
contract BitVVaultManager is BitVComplianceGuard {
    constructor(address complianceValidator, address owner_) BitVComplianceGuard(complianceValidator, owner_) {}

    function deposit(address vault, uint256 amount) external {
        _requireCompliance(msg.sender);
        (vault, amount);
        revert ComplianceErrors.NotImplemented();
    }

    function withdraw(address vault, uint256 amount) external {
        _requireCompliance(msg.sender);
        (vault, amount);
        revert ComplianceErrors.NotImplemented();
    }

    function claimRewards(address vault) external {
        _requireCompliance(msg.sender);
        (vault);
        revert ComplianceErrors.NotImplemented();
    }
}
