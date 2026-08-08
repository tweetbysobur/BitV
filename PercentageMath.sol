// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title PercentageMath
/// @notice Basis-point arithmetic. 1 bps = 0.01%, so 10_000 bps = 100%.
/// @dev A separate, smaller unit from WAD is used for every protocol
///      *parameter* (LTV, liquidation threshold, close factor, reserve
///      factor, fee shares) rather than reusing WAD for them. Two reasons:
///      first, governance-set parameters are round numbers a human chooses
///      ("75.00% LTV"), and bps expresses that exactly with a uint16-range
///      value instead of an 18-digit WAD literal that is easy to mistype by
///      an order of magnitude; second, keeping "rate index space" (WAD/RAY)
///      and "policy parameter space" (bps) visually and type-distinct makes
///      it obvious at a glance which arithmetic a given multiplication is
///      doing.
library PercentageMath {
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant HALF_BPS = BPS_DENOMINATOR / 2;

    /// @notice `value * bps / 10_000`, rounded to nearest.
    function percentMul(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (value == 0 || bps == 0) return 0;
        return (value * bps + HALF_BPS) / BPS_DENOMINATOR;
    }

    /// @notice `value * 10_000 / bps`, rounded to nearest.
    function percentDiv(uint256 value, uint256 bps) internal pure returns (uint256) {
        return (value * BPS_DENOMINATOR + bps / 2) / bps;
    }
}
