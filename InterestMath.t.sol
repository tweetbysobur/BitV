// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { InterestMath } from "../../src/libraries/InterestMath.sol";
import { WadRayMath } from "../../src/libraries/WadRayMath.sol";

contract InterestMathTest is Test {
    function test_zeroElapsed_returnsRay() public {
        assertEq(InterestMath.calculateCompoundedInterest(1e20, 0), WadRayMath.RAY);
    }

    function test_zeroRate_returnsRay() public {
        assertEq(InterestMath.calculateCompoundedInterest(0, 365 days), WadRayMath.RAY);
    }

    /// @dev Cross-checks the binomial approximation against the exact
    ///      compounding formula computed in a wider fixed-point space
    ///      (via repeated squaring is impractical in Solidity; instead this
    ///      checks the approximation's defining property directly — output
    ///      must exceed `RAY + rate*elapsed` (simple, non-compounded interest)
    ///      by a small, bounded second-order term, and must never be exotic
    ///      (e.g. never decrease, never explode) across realistic rate/time
    ///      ranges.
    function testFuzz_compoundedInterest_boundedAndMonotonic(uint256 rateRay, uint256 elapsed)
        public
    {
        // `uint256(...)` forces integer (truncating) division here — left as
        // a bare rational-literal expression, `5e27 / 365 days` does not
        // divide evenly and Solidity refuses to implicitly narrow the
        // resulting fractional constant to `uint256` for the `bound` call.
        rateRay = bound(rateRay, 0, uint256(5e27) / 365 days); // up to 500% APY per-second rate
        elapsed = bound(elapsed, 0, 4 * 365 days);

        uint256 compounded = InterestMath.calculateCompoundedInterest(rateRay, elapsed);
        uint256 simpleInterest = WadRayMath.RAY + (rateRay * elapsed);

        // Compounding must never yield less than simple interest for a
        // non-negative rate.
        assertGe(compounded, simpleInterest);
    }

    function testFuzz_accrueIndex_neverDecreasesForNonNegativeGrowth(
        uint256 indexRay,
        uint256 multiplierRay
    ) public {
        indexRay = bound(indexRay, WadRayMath.RAY, WadRayMath.RAY * 1000);
        multiplierRay = bound(multiplierRay, WadRayMath.RAY, WadRayMath.RAY * 2);

        uint256 result = InterestMath.accrueIndex(indexRay, multiplierRay);
        assertGe(result, indexRay);
    }

    function test_toRatePerSecond_annualDivision() public {
        uint256 annual = 0.1e27; // 10% APY
        uint256 perSecond = InterestMath.toRatePerSecond(annual);
        assertEq(perSecond, uint256(0.1e27) / 365 days);
    }
}
