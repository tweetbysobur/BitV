// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BitVComplianceGuard} from "../compliance/BitVComplianceGuard.sol";
import {ComplianceErrors} from "../libraries/ComplianceErrors.sol";

/**
 * @title BitVLendingManager
 * @notice Identity-gated (and, later, RWA-backed) lending boundary.
 * Compliance foundation milestone: every protected action checks
 * Cleanverse compliance first and then reverts NotImplemented — no
 * interest/liquidation economics yet.
 */
contract BitVLendingManager is BitVComplianceGuard {
    constructor(address complianceValidator, address owner_) BitVComplianceGuard(complianceValidator, owner_) {}

    function supply(address asset, uint256 amount) external {
        _requireCompliance(msg.sender);
        (asset, amount);
        revert ComplianceErrors.NotImplemented();
    }

    function borrow(address asset, uint256 amount) external {
        _requireCompliance(msg.sender);
        (asset, amount);
        revert ComplianceErrors.NotImplemented();
    }

    function repay(address asset, uint256 amount) external {
        _requireCompliance(msg.sender);
        (asset, amount);
        revert ComplianceErrors.NotImplemented();
    }

    function withdraw(address asset, uint256 amount) external {
        _requireCompliance(msg.sender);
        (asset, amount);
        revert ComplianceErrors.NotImplemented();
    }

    /// @notice Liquidator compliance is checked, not the liquidated user's —
    /// they are already an existing borrower, and the party taking custody
    /// of collateral is the one Cleanverse needs to authorize.
    function liquidate(address borrower, address asset, uint256 repayAmount) external {
        _requireCompliance(msg.sender);
        (borrower, asset, repayAmount);
        revert ComplianceErrors.NotImplemented();
    }

    // ── RWA-backed lending (compliance boundary only) ──────────────────

    function depositCollateral(address rwaAsset, uint256 amount) external {
        _requireCompliance(msg.sender);
        (rwaAsset, amount);
        revert ComplianceErrors.NotImplemented();
    }

    function withdrawCollateral(address rwaAsset, uint256 amount) external {
        _requireCompliance(msg.sender);
        (rwaAsset, amount);
        revert ComplianceErrors.NotImplemented();
    }
}
