// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Shared protocol data structures. BitV-original, not Cleanverse
/// types — do not confuse with the Cleanverse `RuleV2` mirror in
/// contracts/src/interfaces/external/IAPassComplianceValidator.sol.
library DataTypes {
    /// @notice Per-asset market configuration and accounting, owned by
    /// BitVPoolManager. One asset = one pool = one set of risk
    /// parameters (an asset used as collateral and an asset that's
    /// borrowable are configured the same way — an asset can be either,
    /// both, or neither, depending on `isCollateralEnabled` /
    /// `isBorrowingEnabled`).
    struct Pool {
        bool isActive; // asset has been created as a pool
        bool isPaused; // emergency-paused: deposits/withdrawals/borrows blocked
        bool isBorrowingEnabled;
        bool isCollateralEnabled;
        uint16 ltvBps; // max loan-to-value when used as collateral (base, score-independent)
        uint16 maxLtvWithScoreBps; // absolute LTV ceiling BitScore may ever raise a user to for
            // this asset (Build 04) — must satisfy ltvBps <= maxLtvWithScoreBps <=
            // liquidationThresholdBps; equals ltvBps (i.e. no BitScore bonus possible) unless
            // RISK_MANAGER_ROLE explicitly configures headroom above it. This is BitV's own
            // configured ceiling, not a Cleanverse value.
        uint16 liquidationThresholdBps; // health-factor-1.0 boundary
        uint16 liquidationBonusBps; // extra collateral seized by liquidators, on top of 100%
        uint16 reserveFactorBps; // share of accrued interest routed to BitVTreasury
        uint256 supplyCap; // underlying units; 0 = uncapped
        uint256 borrowCap; // underlying units; 0 = uncapped
        uint256 totalScaledSupply; // ray-scaled, see WadRayMath
        uint256 totalScaledDebt; // ray-scaled
        uint256 liquidityIndexRay;
        uint256 borrowIndexRay;
        uint40 lastUpdateTimestamp;
        address interestRateModel; // IInterestRateModel
        address priceOracle; // IPriceOracle, address(0) if asset isn't priced
    }

    /// @notice Snapshot of a user's cross-asset position, used for health
    /// factor and borrow-capacity checks in BitVLendingManager.
    struct AccountData {
        uint256 totalCollateralValue; // in the oracle's shared price unit
        uint256 totalDebtValue;
        uint256 availableBorrowValue; // base, ltvBps-weighted — the hard-limit fallback BitScore may never exceed
        uint256 weightedMaxLtvValue; // maxLtvWithScoreBps-weighted collateral value — the absolute BitScore ceiling (Build 04)
        uint256 currentLiquidationThresholdBps; // collateral-value-weighted average
        uint256 healthFactorRay; // type(uint256).max if no debt
    }
}
