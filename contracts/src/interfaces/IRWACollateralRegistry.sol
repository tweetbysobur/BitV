// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRWACollateralRegistry
 * @notice Boundary between BitVLendingManager and
 * BitVRWACollateralRegistry. Kept narrow, mirroring IBitScoreManager's
 * role for BitScoreManager (docs/rwa-market-specification.md §2): the
 * registry answers exactly one question — "is this specific asset's
 * collateral currently usable for NEW borrowing capacity, and against
 * which debt assets" — and BitVLendingManager treats every call as
 * optional and fail-safe (address(0) = disabled; any revert is treated
 * as "not eligible," never as "eligible," since an unavailable answer
 * must never increase borrowing capacity).
 *
 * This interface does not expose registration/admin functions —
 * those are BitVRWACollateralRegistry-specific and are not part of the
 * boundary BitVLendingManager depends on.
 */
interface IRWACollateralRegistry {
    /// @notice True if `asset` has ever been registered as RWA
    /// collateral (any status other than Unregistered), regardless of
    /// its current eligibility. Assets never registered here are
    /// entirely outside the registry's scope — BitVLendingManager
    /// treats them exactly as it did before this integration existed.
    function isRegisteredAsset(address asset) external view returns (bool);

    /// @notice True only if `asset` is registered, its status is
    /// Active, and its oracle price is currently fresh (per the
    /// registry's own staleness tracking, see
    /// docs/rwa-market-specification.md §8) and nonzero. False for
    /// Frozen, Delisted, or stale/zero-priced assets — the single
    /// choke point that keeps such assets from ever contributing to
    /// NEW borrowing capacity (existing collateral value/health-factor
    /// weighting for already-registered assets is unaffected — see
    /// docs/rwa-market-implementation.md for exactly what this
    /// controls vs. what it doesn't).
    function isEligibleForNewActivity(address asset) external view returns (bool);

    /// @notice True if `debtAsset` may be borrowed using `asset`'s
    /// collateral value, per the asset's own configured restriction.
    /// An asset with no configured restriction (the common case)
    /// allows every debt asset — this only ever narrows, never widens,
    /// what BitVLendingManager would otherwise allow.
    function isDebtAssetAllowed(address asset, address debtAsset) external view returns (bool);

    /// @notice This asset's own collateral cap (in the underlying
    /// asset's own units), independent of BitVPoolManager's supplyCap.
    /// 0 means uncapped.
    function getCollateralCap(address asset) external view returns (uint256);
}
