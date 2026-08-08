// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Ray (1e27) fixed-point math for interest-index accounting.
/// @dev BitV-original utility, not a Cleanverse primitive — standard
/// Aave-style ray math, included for deterministic, auditable interest
/// accrual (protocol-architecture requirement, not a compliance claim).
library WadRayMath {
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = RAY / 2;

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        return (a * b + HALF_RAY) / RAY;
    }

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "WadRayMath: division by zero");
        uint256 halfB = b / 2;
        return (a * RAY + halfB) / b;
    }
}
