// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { WadRayMath } from "../libraries/WadRayMath.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title KinkedInterestRateModel
/// @notice Standard two-slope utilization curve: a gentle slope below the
///         kink (encouraging borrowing while liquidity is plentiful) and a
///         steep slope above it (pricing borrowers out fast as available
///         liquidity for withdrawal shrinks, protecting supplier
///         withdrawability).
/// @dev One instance is deployed PER MARKET, not shared — `PoolManager`
///      stores a `rateModel` address per pool (`DataTypes.Pool.rateModel`).
///      This is what lets governance retune, say, USDC's curve without
///      touching every other market's risk parameters, and lets a market be
///      migrated to a materially different curve (e.g. one with a reserve
///      floor for a newly-listed volatile asset) by pointing PoolManager at
///      a new model address — no state migration required, since this
///      contract is stateless and pure.
contract KinkedInterestRateModel is IInterestRateModel {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    /// @notice Utilization at which the slope steepens, WAD-scaled.
    uint256 public immutable optimalUtilizationWad;
    /// @notice Borrow rate at 0% utilization, RAY-scaled (annualized).
    uint256 public immutable baseRateRay;
    /// @notice Rate increase per unit of utilization below the kink, RAY-scaled.
    uint256 public immutable slope1Ray;
    /// @notice Rate increase per unit of utilization above the kink, RAY-scaled.
    uint256 public immutable slope2Ray;
    /// @notice Share of borrower interest retained as protocol reserves
    ///         (routed to Treasury by PoolManager's accrual), rather than
    ///         paid out to suppliers.
    uint16 public immutable reserveFactorBps;

    constructor(
        uint256 optimalUtilizationWad_,
        uint256 baseRateRay_,
        uint256 slope1Ray_,
        uint256 slope2Ray_,
        uint16 reserveFactorBps_
    ) {
        if (optimalUtilizationWad_ == 0 || optimalUtilizationWad_ > WadRayMath.WAD) {
            revert Errors.InvalidRateModelParams();
        }
        if (reserveFactorBps_ > PercentageMath.BPS_DENOMINATOR) {
            revert Errors.InvalidBps(reserveFactorBps_);
        }

        optimalUtilizationWad = optimalUtilizationWad_;
        baseRateRay = baseRateRay_;
        slope1Ray = slope1Ray_;
        slope2Ray = slope2Ray_;
        reserveFactorBps = reserveFactorBps_;
    }

    function getUtilization(uint256 totalSupplied, uint256 totalBorrowed)
        public
        pure
        returns (uint256)
    {
        if (totalSupplied == 0) return 0;
        // `totalBorrowed` can theoretically exceed `totalSupplied` for a
        // single block during interest accrual ordering edge cases;
        // `wadDiv` does not clamp, so callers of `getRates` see utilization
        // above 100% honestly (pricing borrowing at the steep slope's
        // ceiling) rather than this function silently capping it and hiding
        // a state PoolManager's invariants should never actually allow to
        // occur.
        return totalBorrowed.wadDiv(totalSupplied);
    }

    function getRates(uint256 totalSupplied, uint256 totalBorrowed)
        external
        view
        returns (uint256 borrowRateRay, uint256 supplyRateRay)
    {
        uint256 utilizationWad = getUtilization(totalSupplied, totalBorrowed);

        if (utilizationWad <= optimalUtilizationWad) {
            // borrowRate = base + (utilization / optimal) * slope1
            uint256 utilizationRatioWad = optimalUtilizationWad == 0
                ? 0
                : utilizationWad.wadDiv(optimalUtilizationWad);
            borrowRateRay = baseRateRay + _wadRatioOfRay(utilizationRatioWad, slope1Ray);
        } else {
            // borrowRate = base + slope1 + ((utilization - optimal) / (1 - optimal)) * slope2
            uint256 excessUtilizationWad = utilizationWad - optimalUtilizationWad;
            uint256 maxExcessWad = WadRayMath.WAD - optimalUtilizationWad;
            uint256 excessRatioWad =
                maxExcessWad == 0 ? WadRayMath.WAD : excessUtilizationWad.wadDiv(maxExcessWad);

            borrowRateRay = baseRateRay + slope1Ray + _wadRatioOfRay(excessRatioWad, slope2Ray);
        }

        // supplyRate = borrowRate * utilization * (1 - reserveFactor)
        // Suppliers earn interest only on the fraction of the pool that is
        // actually borrowed, and only on the share NOT retained as protocol
        // reserve — standard money-market supply-rate derivation.
        uint256 grossSupplyRateRay = borrowRateRay.rayMul(_wadToRay(utilizationWad));
        supplyRateRay = grossSupplyRateRay.percentMul(
            PercentageMath.BPS_DENOMINATOR - reserveFactorBps
        );
    }

    /// @dev Multiplies a WAD ratio (0-1e18, or beyond if utilization exceeds
    ///      100%) by a RAY-scaled rate, returning RAY. Kept as a named helper
    ///      rather than inlined `rayMul(wadToRay(ratio), rate)` at each call
    ///      site so the unit conversion is visibly intentional, not an
    ///      accidental precision mismatch an auditor has to re-derive.
    function _wadRatioOfRay(uint256 ratioWad, uint256 rateRay) private pure returns (uint256) {
        return _wadToRay(ratioWad).rayMul(rateRay);
    }

    function _wadToRay(uint256 value) private pure returns (uint256) {
        return WadRayMath.wadToRay(value);
    }
}
