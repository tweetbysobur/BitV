// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {ProtocolErrors} from "../libraries/ProtocolErrors.sol";

/**
 * @title KinkedInterestRateModel
 * @notice Deterministic, auditable two-slope interest rate model.
 * Separates a flat base rate from a utilization-driven component:
 *
 *   utilization <= kink:  rate = base + (utilization / kink) * slope1
 *   utilization >  kink:  rate = base + slope1
 *                              + ((utilization - kink) / (1 - kink)) * slope2
 *
 * All rate/utilization values are ray-scaled (1e27 = 100%). Parameters
 * are owner-settable (risk manager) rather than hardcoded, per the
 * "configurable protocol parameters" requirement — starting values are
 * documented at the bottom of this file rather than left unexplained.
 */
contract KinkedInterestRateModel is IInterestRateModel, Ownable {
    using WadRayMath for uint256;

    uint256 public baseRateRay;
    uint256 public slope1Ray;
    uint256 public slope2Ray;
    uint256 public kinkRay;

    event ParamsUpdated(uint256 baseRateRay, uint256 slope1Ray, uint256 slope2Ray, uint256 kinkRay);

    constructor(address owner_, uint256 baseRateRay_, uint256 slope1Ray_, uint256 slope2Ray_, uint256 kinkRay_)
        Ownable(owner_)
    {
        if (kinkRay_ == 0 || kinkRay_ > WadRayMath.RAY) revert ProtocolErrors.InvalidRiskParams();
        baseRateRay = baseRateRay_;
        slope1Ray = slope1Ray_;
        slope2Ray = slope2Ray_;
        kinkRay = kinkRay_;
    }

    function setParams(uint256 baseRateRay_, uint256 slope1Ray_, uint256 slope2Ray_, uint256 kinkRay_)
        external
        onlyOwner
    {
        if (kinkRay_ == 0 || kinkRay_ > WadRayMath.RAY) revert ProtocolErrors.InvalidRiskParams();
        baseRateRay = baseRateRay_;
        slope1Ray = slope1Ray_;
        slope2Ray = slope2Ray_;
        kinkRay = kinkRay_;
        emit ParamsUpdated(baseRateRay_, slope1Ray_, slope2Ray_, kinkRay_);
    }

    function getBorrowRateRay(uint256 totalSupplied, uint256 totalBorrowed)
        external
        view
        returns (uint256 borrowRateRay)
    {
        if (totalSupplied == 0) return baseRateRay;
        uint256 utilizationRay = totalBorrowed.rayDiv(totalSupplied);
        if (utilizationRay > WadRayMath.RAY) utilizationRay = WadRayMath.RAY;

        if (utilizationRay <= kinkRay) {
            return baseRateRay + utilizationRay.rayDiv(kinkRay).rayMul(slope1Ray);
        }

        uint256 excessUtilizationRay = utilizationRay - kinkRay;
        uint256 maxExcessRay = WadRayMath.RAY - kinkRay;
        return baseRateRay + slope1Ray + excessUtilizationRay.rayDiv(maxExcessRay).rayMul(slope2Ray);
    }
}

/*
 * Suggested starting parameters (NOT deployed, NOT financial advice — a
 * documented, changeable starting point per "do not hardcode arbitrary
 * values without documenting them"):
 *   baseRateRay = 0            (0% base)
 *   slope1Ray   = 4e25         (4% at the kink)
 *   slope2Ray   = 75e25        (steep — 75% at 100% utilization)
 *   kinkRay     = 80e25        (80% utilization)
 */
