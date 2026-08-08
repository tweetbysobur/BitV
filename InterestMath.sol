// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { WadRayMath } from "./WadRayMath.sol";

/// @title InterestMath
/// @notice Per-second compounded interest accrual for liquidity and borrow
///         indices.
/// @dev Compounding is approximated with the first three terms of the
///      binomial expansion of `(1 + rate)^n` rather than computed exactly,
///      which would require a fixed-point power function:
///
///          (1+x)^n ≈ 1 + n·x + n(n-1)/2·x²
///
///      This is the same approximation used by Aave V2/V3 and Compound; it is
///      accurate to within a few wei per accrual at realistic per-second
///      rates and durations (rates below ~1000% APY, durations under a few
///      years), and is dramatically cheaper than an exact exponential —
///      material on a chain where gas is priced on the LIMIT set for the
///      call, so a cheaper, tightly-bounded computation is a direct cost
///      saving rather than just a speed one. See docs/contracts-architecture.md
///      §Interest accrual for the error-bound derivation.
library InterestMath {
    using WadRayMath for uint256;

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /// @notice Compounds `ratePerSecondRay` over `elapsedSeconds`, expressed
    ///         as a multiplier in RAY (RAY = "no change").
    /// @param ratePerSecondRay Per-second rate, RAY-scaled (annual rate / SECONDS_PER_YEAR).
    /// @param elapsedSeconds   Time since last accrual.
    /// @return The compounding multiplier in RAY.
    function calculateCompoundedInterest(uint256 ratePerSecondRay, uint256 elapsedSeconds)
        internal
        pure
        returns (uint256)
    {
        if (elapsedSeconds == 0) return WadRayMath.RAY;

        uint256 expMinusOne = elapsedSeconds - 1;
        uint256 expMinusTwo = elapsedSeconds > 2 ? elapsedSeconds - 2 : 0;

        uint256 ratePerSecondSquared = ratePerSecondRay.rayMul(ratePerSecondRay);
        uint256 ratePerSecondCubed = ratePerSecondSquared.rayMul(ratePerSecondRay);

        uint256 secondTerm = elapsedSeconds * expMinusOne * ratePerSecondSquared / 2;
        uint256 thirdTerm =
            elapsedSeconds * expMinusOne * expMinusTwo * ratePerSecondCubed / 6;

        return WadRayMath.RAY + (elapsedSeconds * ratePerSecondRay) + secondTerm + thirdTerm;
    }

    /// @notice Converts an annual rate (RAY, e.g. 0.05e27 = 5% APY) to a
    ///         per-second rate for use in `calculateCompoundedInterest`.
    function toRatePerSecond(uint256 annualRateRay) internal pure returns (uint256) {
        return annualRateRay / SECONDS_PER_YEAR;
    }

    /// @notice Applies a compounding multiplier (RAY) to an existing index (RAY).
    function accrueIndex(uint256 currentIndexRay, uint256 compoundedMultiplierRay)
        internal
        pure
        returns (uint256)
    {
        return currentIndexRay.rayMul(compoundedMultiplierRay);
    }
}
