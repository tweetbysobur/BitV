// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title WadRayMath
/// @notice Fixed-point arithmetic at two precisions used throughout the
///         protocol: WAD (1e18) for user-facing amounts and rates, RAY (1e27)
///         for internally-accrued indices.
/// @dev Two precisions, not one, is a deliberate choice carried over from the
///      Aave lineage this design borrows from: liquidity/borrow indices
///      compound every block-equivalent interval over a protocol's entire
///      lifetime, and RAY's extra 9 digits of precision is what keeps
///      per-second compounding from losing meaningful value to truncation
///      over years of accrual. WAD is precise enough for a single balance or
///      rate and is what every external interface (this repo's and the
///      tokens it integrates) already expects, so indices are the only
///      values that pay RAY's larger arithmetic cost.
///
///      All operations revert on overflow (Solidity 0.8 default) and round
///      to nearest via half-unit addition before division — rounding down
///      silently would bias every accrual in the protocol's favour and, more
///      importantly, in different directions for different callers depending
///      on rounding mode, which is its own subtle accounting bug.
library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant WAD_RAY_RATIO = 1e9;
    uint256 internal constant HALF_WAD = WAD / 2;
    uint256 internal constant HALF_RAY = RAY / 2;

    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        return (a * b + HALF_WAD) / WAD;
    }

    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * WAD + b / 2) / b;
    }

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        return (a * b + HALF_RAY) / RAY;
    }

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * RAY + b / 2) / b;
    }

    function rayToWad(uint256 a) internal pure returns (uint256) {
        uint256 halfRatio = WAD_RAY_RATIO / 2;
        return (a + halfRatio) / WAD_RAY_RATIO;
    }

    function wadToRay(uint256 a) internal pure returns (uint256) {
        return a * WAD_RAY_RATIO;
    }
}
