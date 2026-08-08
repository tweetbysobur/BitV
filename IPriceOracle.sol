// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IPriceOracle
/// @notice Asset pricing for collateral valuation and liquidation math.
/// @dev Deliberately separate from `IIdentityOracle` — pricing and identity
///      are orthogonal concerns with different trust models (a price feed
///      needs freshness/deviation guarantees; identity needs a Cleanverse
///      round trip) and different upgrade cadences. Bundling them would force
///      every price-only caller to also depend on Cleanverse's interface.
interface IPriceOracle {
    /// @notice USD price of one whole unit of `asset`, WAD-scaled (1e18 = $1).
    /// @dev Reverts rather than returning a stale/zero price — an
    ///      LendingManager that receives 0 for a price and proceeds to value
    ///      collateral at zero would incorrectly treat every position as
    ///      undercollateralized, and one that receives a stale-but-nonzero
    ///      price silently misprices liquidations. Both are worse than a
    ///      revert a caller can catch and surface as "market unavailable".
    function getPriceUsd(address asset) external view returns (uint256 priceWad);

    /// @notice Whether `asset` currently has a live, non-stale price.
    function isPriceAvailable(address asset) external view returns (bool);
}
