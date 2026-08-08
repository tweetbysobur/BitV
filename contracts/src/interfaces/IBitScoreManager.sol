// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Boundary between BitVLendingManager and BitScoreManager. Kept
 * as a narrow interface so BitVLendingManager can hold an optional
 * (possibly zero) reference and fail safe to base parameters if
 * BitScore is unset or its calls fail — see
 * docs/bitscore-specification.md §12 and
 * docs/bitscore-implementation.md.
 */
interface IBitScoreManager {
    /// @notice Score on BitV's 0-100 scale (docs/bitscore-specification.md),
    /// not the earlier 0-1000 scale — uint8 is sufficient range.
    function getScore(address user) external view returns (uint8 score);
    function getTier(address user) external view returns (uint8 tier);

    /// @notice Returns the score-adjusted available-borrow-value ceiling
    /// for `user`, given their base (score-independent) and maximum
    /// (BitScore-ceiling) available borrow values as already computed by
    /// BitVLendingManager from BitVPoolManager's asset configuration.
    /// The result is always within [0, maxAvailableBorrowValue] —
    /// BitScore can never push it above the caller-supplied ceiling.
    function getAdjustedAvailableBorrowValue(
        address user,
        uint256 baseAvailableBorrowValue,
        uint256 maxAvailableBorrowValue,
        uint256 totalDebtValue,
        uint256 totalCollateralValue
    ) external view returns (uint256 adjustedAvailableBorrowValue);

    /// @notice Quoted (informational) base-rate discount for `user`'s
    /// current tier. NOT wired into actual interest accrual — see
    /// docs/bitscore-implementation.md's "Interest rate integration"
    /// section for why a genuinely per-user rate is incompatible with
    /// BitVPoolManager's shared borrow index, and why this is
    /// deliberately quote-only rather than silently doing nothing while
    /// claiming otherwise.
    function getBaseRateDiscountRay(address user) external view returns (uint256 discountRay);

    function recordRepayment(address user, bool wasFullClose, uint256 positionDurationSeconds) external;
    function recordLiquidation(address user, bool wasBadDebt, bool wasPartial) external;
    function recordUtilizationSnapshot(address user, uint16 utilizationBps, uint16 healthFactorBps) external;
}
