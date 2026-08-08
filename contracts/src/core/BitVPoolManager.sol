// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BitVComplianceGuard} from "../compliance/BitVComplianceGuard.sol";
import {ComplianceErrors} from "../libraries/ComplianceErrors.sol";

/**
 * @title BitVPoolManager
 * @notice Identity-gated liquidity pool boundary. Compliance foundation
 * milestone: every protected action checks Cleanverse compliance first
 * and then reverts NotImplemented — no accounting/economics yet.
 */
contract BitVPoolManager is BitVComplianceGuard {
    constructor(address complianceValidator) BitVComplianceGuard(complianceValidator) {}

    function addLiquidity(address asset, uint256 amount) external {
        _requireCompliance(msg.sender);
        (asset, amount);
        revert ComplianceErrors.NotImplemented();
    }

    function removeLiquidity(address asset, uint256 amount) external {
        _requireCompliance(msg.sender);
        (asset, amount);
        revert ComplianceErrors.NotImplemented();
    }

    function swap(address assetIn, address assetOut, uint256 amountIn) external {
        _requireCompliance(msg.sender);
        (assetIn, assetOut, amountIn);
        revert ComplianceErrors.NotImplemented();
    }
}
