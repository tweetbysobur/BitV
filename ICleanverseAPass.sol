// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ICleanverseAPass
/// @notice On-chain read interface for a Cleanverse A-Pass identity record.
///
/// @dev IMPORTANT — provenance of this interface.
///      Cleanverse publishes A-Pass data through its off-chain Cooperate REST
///      API (`POST /query_apass`, consumed by this repo's frontend at
///      `src/lib/cleanverse/identity.ts`); that document does not publish a
///      Solidity ABI for an on-chain A-Pass registry. Every A-Token pair
///      returned by `/query_deposit_atoken_list` DOES carry an on-chain
///      `apass_address` field, confirming an on-chain registry exists and is
///      addressable — this interface is BitV's best-effort mirror of the
///      REST record's fields (see the table below), shaped as a read-only
///      view function so it can be called atomically inside a transaction
///      rather than trusting an off-chain check that could be stale by the
///      time the transaction lands.
///
///      This MUST be confirmed against the actual deployed A-Pass contract's
///      ABI before mainnet deployment. If the deployed shape differs, only
///      `CleanverseAPassAdapter.sol` needs to change — every protocol
///      contract calls the stable `IIdentityOracle` interface, never this one
///      directly. See `docs/contracts-architecture.md` §Cleanverse adapter.
///
///      REST field correspondence (`lib/cleanverse/types.ts` on the frontend):
///        tier            → REST `tier` (string in JSON; numeric on-chain)
///        subTier         → REST `subTier`
///        status          → REST `status` (1 = active, 2 = frozen)
///        expirationTime  → REST `expirationTime`, Unix SECONDS
///        group/subGroup  → REST `group` / `subGroup`, packed bytes2 on-chain
interface ICleanverseAPass {
    /// @notice Raw A-Pass record, mirroring the REST response shape.
    struct APassRecord {
        uint256 cvRecordId;
        uint16 tier;
        uint16 subTier;
        uint8 status; // 1 = active, 2 = frozen; 0 = no record
        uint64 expirationTime; // unix seconds
        bytes2 group;
        bytes2 subGroup;
    }

    /// @notice Returns the A-Pass record for `account`. A zero `status`
    ///         means no record exists — callers must not treat that as
    ///         "tier 0, active".
    function getAPass(address account) external view returns (APassRecord memory);

    /// @notice Whether `account` currently holds ANY country in `countries`.
    /// @dev Exposed as a separate call because jurisdictional data on the
    ///      REST side is a variable-length array (`countries: ["SG","US"]`)
    ///      that does not map cleanly onto a single view return value shared
    ///      with `getAPass`; pool rules only ever need a membership test
    ///      against their own configured allow/deny list, not the full set.
    function hasAnyCountry(address account, bytes2[] calldata countries)
        external
        view
        returns (bool);
}
