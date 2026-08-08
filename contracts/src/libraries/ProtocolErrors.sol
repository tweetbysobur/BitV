// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Protocol-level (economic) errors — distinct from
/// ComplianceErrors, which is Cleanverse-integration-specific.
library ProtocolErrors {
    error PoolAlreadyExists(address asset);
    error PoolNotActive(address asset);
    error PoolIsPaused(address asset);
    error BorrowingDisabled(address asset);
    error CollateralDisabled(address asset);
    error ZeroAmount();
    error AmountExceedsBalance(uint256 requested, uint256 available);
    error AmountExceedsAvailableLiquidity(uint256 requested, uint256 available);
    error SupplyCapExceeded(uint256 newTotal, uint256 cap);
    error BorrowCapExceeded(uint256 newTotal, uint256 cap);
    error InsufficientCollateral(uint256 requiredValue, uint256 availableValue);
    error NoOutstandingDebt(address asset);
    error PositionIsHealthy(uint256 healthFactorRay);
    error PriceOracleNotSet(address asset);
    error ZeroAddress();
    error CallerNotLendingManager();
    error InvalidRiskParams();
    error Unauthorized(address caller, bytes32 role);
}
