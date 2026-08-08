// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Errors specific to BitVRWACollateralRegistry — distinct from
/// ProtocolErrors (lending/pool), ComplianceErrors (Cleanverse), and
/// VaultErrors (yield vault), per the codebase's existing per-domain
/// error library convention.
library RWAErrors {
    error ZeroAddress();
    error AssetAlreadyRegistered(address asset);
    error AssetNotRegistered(address asset);
    error AssetDelisted(address asset);
    error UnderlyingPoolNotActive(address asset);
    error UnderlyingPoolCollateralDisabled(address asset);
    error RiskParamsExceedPoolLimits(address asset);
    error InvalidRiskParams();
    error InvalidStatusTransition(uint8 fromStatus, uint8 toStatus);
    error InvalidOraclePrice(address asset);
    error InvalidBps(uint256 bps);

    /// @notice Thrown by BitVLendingManager when a registered RWA
    /// asset is not currently eligible for a new collateral deposit
    /// (status not Active, or oracle price stale/unavailable).
    error AssetNotEligibleForDeposit(address asset);

    /// @notice Thrown by BitVLendingManager when a new collateral
    /// deposit would push a registered RWA asset's aggregate collateral
    /// above its registry-configured cap.
    error CollateralCapExceeded(address asset, uint256 newTotal, uint256 cap);
}
