// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ICleanverseAccessCore
/// @notice On-chain interface to the per-A-Token AccessCore contract that
///         enforces transfer compliance for a Cleanverse Verified Asset.
///
/// @dev Every entry in `POST /query_deposit_atoken_list` (`lib/cleanverse/assets.ts`
///      → `listVerifiedAssets`) carries an `accesscore_address` alongside the
///      `atoken` address — the REST docs describe it plainly as the contract
///      that "enforces transfer compliance on-chain". BitV never needs to
///      call `transfer`/`transferFrom` through this interface: the A-Token
///      itself is a standard `IERC20` whose own transfer path already routes
///      through its AccessCore internally, so any `IERC20.transferFrom`
///      BitV's markets perform is compliance-checked by the token itself.
///
///      What BitV DOES need is a pre-flight, revert-free check — mirroring
///      `POST /verify_apass`'s `data.code` semantics exactly — so a market
///      can reject an ineligible deposit/borrow/settlement with a clear
///      reason BEFORE attempting the token transfer, rather than letting the
///      transfer itself revert with an opaque AccessCore error deep in an
///      external call.
///
///      Confirm against the deployed AccessCore ABI before mainnet; only
///      `CleanverseAccessCoreAdapter.sol` needs to change if it differs.
interface ICleanverseAccessCore {
    /// @notice Mirrors `verify_apass`'s `data.code`: 1 = A-Token not found,
    ///         2 = no A-Pass, 3 = A-Pass expired/frozen, 4 = eligible.
    ///         Any other value must be treated as unavailable (fail closed).
    function checkEligibility(address account) external view returns (uint8 code);

    /// @notice The origin (unwrapped) token this AccessCore's A-Token wraps.
    function originToken() external view returns (address);

    /// @notice The A-Token this AccessCore governs transfers for.
    function aToken() external view returns (address);
}
