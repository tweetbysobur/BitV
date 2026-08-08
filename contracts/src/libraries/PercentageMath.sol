// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Basis-point (1e4 = 100%) percentage math for risk parameters
/// (LTV, liquidation threshold/bonus, reserve factor). BitV-original
/// utility, not a Cleanverse primitive.
library PercentageMath {
    uint256 internal constant PERCENTAGE_FACTOR = 1e4;
    uint256 internal constant HALF_PERCENT = PERCENTAGE_FACTOR / 2;

    function percentMul(uint256 value, uint256 bps) internal pure returns (uint256) {
        if (value == 0 || bps == 0) return 0;
        return (value * bps + HALF_PERCENT) / PERCENTAGE_FACTOR;
    }

    function percentDiv(uint256 value, uint256 bps) internal pure returns (uint256) {
        require(bps != 0, "PercentageMath: division by zero");
        return (value * PERCENTAGE_FACTOR + bps / 2) / bps;
    }
}
