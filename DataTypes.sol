// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title DataTypes
/// @notice Shared structs used across manager interfaces and their
///         implementations. Centralised so `IPoolManager` and
///         `PoolManager.sol` (etc.) reference the exact same struct layout —
///         redeclaring an identical struct in an interface and its
///         implementation is how the two silently drift apart over time.
library DataTypes {
    /// @notice A single-asset liquidity pool (PoolManager's unit of state).
    /// @dev Both `liquidityIndexRay` and `borrowIndexRay` live here, on ONE
    ///      struct, updated by ONE function (`PoolManager._accrue`), against
    ///      ONE shared `lastUpdateTimestamp` — deliberately, not an
    ///      arbitrary grouping. An earlier design split the borrow index
    ///      into `LendingManager`'s own `BorrowConfig`, each side
    ///      independently calling the rate model and compounding on its own
    ///      schedule (whichever contract happened to be touched first in a
    ///      given block). That let the two indices integrate two different
    ///      rate PATHS over time — not rounding noise, a real, usage-scaling
    ///      solvency gap, caught by the invariant suite (see
    ///      `docs/contracts-architecture.md` §Known issues for the full
    ///      diagnosis before this fix). `totalScaledDebt` moved here for the
    ///      same reason: `totalBorrowed` must be *derived*
    ///      (`totalScaledDebt.rayMul(borrowIndexRay)`), never separately
    ///      mirrored, so there is no reconciliation step that can drift.
    struct Pool {
        address asset;
        address aToken; // scaled-balance receipt token for this pool, see IPoolManager
        uint128 liquidityIndexRay;
        uint128 borrowIndexRay;
        uint128 totalScaledSupply;
        uint128 totalScaledDebt;
        uint128 supplyCap; // underlying units, 0 = unlimited
        uint40 lastUpdateTimestamp;
        uint16 reserveFactorBps; // share of interest routed to Treasury
        address rateModel;
        bool isPaused; // blocks all user-facing actions
        bool isFrozen; // blocks new supply/borrow, allows withdraw/repay
        bool isBorrowingEnabled;
        address validatorPool; // Cleanverse Validator pool gating this market, 0 = ungated
    }

    /// @notice Per-asset borrow-side RISK PARAMETERS, owned by LendingManager.
    ///         Debt accounting itself (`totalScaledDebt`, `borrowIndexRay`)
    ///         lives on `Pool` above — LendingManager reads it from
    ///         PoolManager rather than maintaining its own copy.
    struct BorrowConfig {
        bool isListed;
        uint128 borrowCap; // underlying units, 0 = unlimited
        uint16 collateralFactorBps; // max LTV when used as collateral
        uint16 liquidationThresholdBps;
        uint16 liquidationBonusBps;
        uint16 closeFactorBps; // max fraction of debt repayable in one liquidation
        bool isCollateralEligible;
    }

    /// @notice A user's scaled debt in a single asset.
    struct DebtPosition {
        uint128 scaledDebt;
        uint40 lastBorrowTimestamp;
    }

    /// @notice A permissioned yield vault (VaultManager's unit of state).
    struct Vault {
        address asset;
        address shareToken;
        uint128 totalAssets;
        uint128 totalShares;
        uint128 depositCap; // 0 = unlimited
        uint16 performanceFeeBps;
        uint16 minIdentityTier; // 0 = no identity requirement beyond wallet auth
        address validatorPool; // 0 = ungated beyond minIdentityTier
        address strategyOrRewardsDistributor;
        bool isPaused;
        uint64 withdrawalLockSeconds; // 0 = no lock
    }
}
