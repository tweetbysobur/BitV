// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Clean interest-rate-model boundary. BitV-original interface,
/// not a Cleanverse primitive.
interface IInterestRateModel {
    /// @param totalSupplied Total underlying supplied to the pool.
    /// @param totalBorrowed Total underlying currently borrowed.
    /// @return borrowRateRay Annualized borrow rate, ray-scaled (1e27 = 100%).
    function getBorrowRateRay(uint256 totalSupplied, uint256 totalBorrowed)
        external
        view
        returns (uint256 borrowRateRay);
}
