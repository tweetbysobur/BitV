// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { DataTypes } from "../libraries/DataTypes.sol";

/// @title IPoolManager
/// @notice Single-asset liquidity pools: BOTH the supply side (liquidity
///         index, custody of underlying tokens) and the pool-level debt
///         accounting (borrow index, `totalScaledDebt`) of BitV's lending
///         markets. `LendingManager` owns per-account debt positions and
///         collateral/risk parameters, but reads and writes pool-level debt
///         state exclusively through this contract — see the NatSpec on
///         `DataTypes.Pool` for why the two indices are unified here rather
///         than split across both contracts.
interface IPoolManager {
    event PoolCreated(address indexed asset, address indexed aToken, address rateModel);
    event Supplied(address indexed asset, address indexed supplier, uint256 amount, uint256 scaledAmount);
    event Withdrawn(address indexed asset, address indexed supplier, uint256 amount, uint256 scaledAmount);
    event PoolStateUpdated(address indexed asset, bool isPaused, bool isFrozen, bool isBorrowingEnabled);
    event InterestAccrued(
        address indexed asset, uint256 liquidityIndexRay, uint256 borrowIndexRay, uint256 supplyRateRay
    );
    event ValidatorPoolSet(address indexed asset, address indexed validatorPool);

    /// @notice Creates a new single-asset pool. Governance-only.
    function createPool(
        address asset,
        address rateModel,
        uint16 reserveFactorBps,
        uint128 supplyCap,
        address validatorPool
    ) external returns (address aToken);

    /// @notice Supplies `amount` of `asset` on behalf of `msg.sender`.
    ///         Reverts via `IAccessManager` if the pool has a Validator pool
    ///         configured and `msg.sender` does not satisfy it.
    function supply(address asset, uint256 amount) external;

    /// @notice Withdraws up to `amount` of `asset`. Passing
    ///         `type(uint256).max` withdraws the caller's full balance —
    ///         standard convention that avoids a caller under/over-estimating
    ///         their accrued balance between quoting and submitting a tx.
    function withdraw(address asset, uint256 amount) external returns (uint256 withdrawn);

    /// @notice Restricted to `LENDING_MANAGER_ROLE`. Accrues interest,
    ///         moves `amount` of underlying out to `LendingManager` for
    ///         disbursement to a borrower, and increases `totalScaledDebt`
    ///         by `amount` scaled at the JUST-ACCRUED `borrowIndexRay`.
    /// @return scaledAmount The scaled debt increase, at the exact index
    ///         used inside this call — the caller (`LendingManager`) applies
    ///         this SAME value to the borrower's own position, which is what
    ///         guarantees `sum(borrower.scaledDebt) == pool.totalScaledDebt`
    ///         exactly rather than approximately (both sides compute the
    ///         scaled amount from the identical index value, because it is
    ///         computed once, here, and returned rather than independently
    ///         re-derived by the caller from a possibly-stale index it read
    ///         earlier in the same transaction).
    function borrowFromPool(address asset, uint256 amount, address to)
        external
        returns (uint256 scaledAmount);

    /// @notice Restricted to `LENDING_MANAGER_ROLE`. Accrues interest, pulls
    ///         `amount` of underlying in from `msg.sender` (LendingManager,
    ///         which has already collected it from the payer), and decreases
    ///         `totalScaledDebt` by `amount` scaled at the just-accrued
    ///         `borrowIndexRay`.
    /// @return scaledAmount The scaled debt decrease at the index used — see
    ///         `borrowFromPool` for why this is returned rather than
    ///         recomputed by the caller.
    function notifyRepay(address asset, uint256 amount) external returns (uint256 scaledAmount);

    /// @notice Runs accrual for `asset`: advances `liquidityIndexRay` and
    ///         `borrowIndexRay` together, over the same elapsed window, from
    ///         one rate-model call. Safe (and cheap) to call redundantly —
    ///         a no-op if already accrued in this block.
    function accrueInterest(address asset) external;

    function getPool(address asset) external view returns (DataTypes.Pool memory);
    function getUtilization(address asset) external view returns (uint256 utilizationWad);
    function getCurrentRates(address asset)
        external
        view
        returns (uint256 borrowRateRay, uint256 supplyRateRay);

    /// @notice Current outstanding debt for `asset`, derived as
    ///         `totalScaledDebt.rayMul(borrowIndexRay)` — never separately
    ///         tracked, so it cannot drift from what the index says it is.
    function totalBorrowed(address asset) external view returns (uint256);

    /// @notice A `view`-safe projection of what `borrowIndexRay` and
    ///         `liquidityIndexRay` would be if accrued right now, WITHOUT
    ///         mutating state. `LendingManager`'s own `view` functions
    ///         (`debtOf`, `healthFactor`) use this — a `view` function
    ///         cannot call the mutating `accrueInterest`, but displaying a
    ///         stale index between accrual-triggering transactions would
    ///         understate a borrower's real-time debt.
    function previewAccruedIndices(address asset)
        external
        view
        returns (uint256 liquidityIndexRay, uint256 borrowIndexRay);

    function balanceOf(address asset, address account) external view returns (uint256);
    function totalLiquidity(address asset) external view returns (uint256);
    function availableLiquidity(address asset) external view returns (uint256);

    function setPoolState(address asset, bool isPaused, bool isFrozen, bool isBorrowingEnabled)
        external;
    function setValidatorPool(address asset, address validatorPool) external;
}
