// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { DataTypes } from "../libraries/DataTypes.sol";

/// @title ILendingManager
/// @notice The debt side of BitV's lending markets: borrowing, repayment,
///         collateral, health factor, and liquidation. Reads liquidity from
///         `IPoolManager` (the only contract that actually custodies
///         underlying tokens) and reads credit terms from `IBitScoreManager`
///         for identity-based under-collateralized borrowing.
interface ILendingManager {
    event AssetListedAsCollateral(
        address indexed asset, uint16 collateralFactorBps, uint16 liquidationThresholdBps
    );
    event BorrowConfigUpdated(address indexed asset, DataTypes.BorrowConfig config);
    event CollateralDeposited(address indexed account, address indexed asset, uint256 amount);
    event CollateralWithdrawn(address indexed account, address indexed asset, uint256 amount);
    event Borrowed(address indexed account, address indexed asset, uint256 amount, bool underCollateralized);
    event Repaid(address indexed account, address indexed asset, uint256 amount, address indexed payer);
    event Liquidated(
        address indexed borrower,
        address indexed liquidator,
        address indexed debtAsset,
        address collateralAsset,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    /// @notice Governance: enables `asset` as borrowable and/or as
    ///         collateral with the given risk parameters.
    function setBorrowConfig(address asset, DataTypes.BorrowConfig calldata config) external;

    function depositCollateral(address asset, uint256 amount) external;
    function withdrawCollateral(address asset, uint256 amount) external;

    /// @notice Borrows `amount` of `asset` against posted collateral. If the
    ///         account's collateral alone is insufficient but its BitScore-
    ///         derived credit line covers the shortfall, the excess is
    ///         issued as identity-based under-collateralized credit — this
    ///         is BitV's core differentiator from a standard over-
    ///         collateralized money market, so it lives in the primary
    ///         borrow path rather than as a separate function a caller has
    ///         to know to opt into.
    function borrow(address asset, uint256 amount) external;

    function repay(address asset, uint256 amount, address onBehalfOf)
        external
        returns (uint256 repaid);

    /// @notice Liquidates an unhealthy position. `debtToCover` is denoted in
    ///         `debtAsset`; capped internally at `closeFactorBps` of the
    ///         borrower's outstanding debt in that asset — a liquidator
    ///         requesting more than the cap has the excess silently
    ///         rejected via a revert, not silently truncated, so a
    ///         liquidator's slippage/output expectations are never silently
    ///         violated.
    function liquidate(
        address borrower,
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover
    ) external returns (uint256 collateralSeized);

    /// @notice Health factor, WAD-scaled. >= 1e18 is healthy; below 1e18 is
    ///         eligible for liquidation. Returns `type(uint256).max` for an
    ///         account with collateral but zero debt (see
    ///         `lib/format/number.ts`'s `formatHealthFactor` on the frontend,
    ///         which already expects and displays this sentinel as "∞").
    function healthFactor(address account) external view returns (uint256);

    function debtOf(address account, address asset) external view returns (uint256);
    function collateralOf(address account, address asset) external view returns (uint256);
    function getBorrowConfig(address asset) external view returns (DataTypes.BorrowConfig memory);

    /// @notice Total borrowing power in USD (WAD): collateral value scaled
    ///         by collateral factors, PLUS the account's current BitScore
    ///         credit limit.
    function borrowingPowerUsd(address account) external view returns (uint256);
}
