// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ICleanverseValidator
/// @notice On-chain interface to a Cleanverse Validator compliance pool.
///
/// @dev Grounded directly in the documented REST semantics
///      (`lib/cleanverse/validator.ts`, `POST /validator/verify|rules|is_paused`),
///      which the off-chain integration explicitly notes correspond to an
///      on-chain pool contract: pools are "registered via `POST
///      /validator/register` (an Issue Member operation requiring an owner
///      signature)" against a `CLEANVERSE_VALIDATOR_POOL_ADDRESS`. That
///      confirms the Validator pool is itself a deployed, addressable
///      contract — this interface mirrors its read surface.
///
///      Write operations (`grant`, `register`, `set_rule`, `set_paused`) are
///      intentionally NOT included here, mirroring the frontend's decision
///      not to wrap them (see docs/cleanverse-integration.md §3, "Write
///      endpoints are deliberately not wrapped"): they require Issue Member
///      role plus an EIP-191 signature from the pool's `owner()`, and belong
///      in a separate operator tool, never in a contract a borrower's
///      transaction path calls into.
///
///      As with `ICleanverseAPass`, this MUST be confirmed against the
///      deployed Validator ABI before mainnet; only `CleanverseValidatorAdapter.sol`
///      needs to change if it differs.
interface ICleanverseValidator {
    /// @notice A pool's configured eligibility rule, mirroring the REST
    ///         `/validator/rules` response.
    struct Rule {
        bytes2 allowedGroup; // 0x0000 = no restriction
        bytes2 allowedSubGroup; // 0x0000 = no restriction
        uint16 minTier; // 0 = no restriction (NOT "tier zero required")
        uint16 minSubTier;
        bool isBlackList; // true inverts `countries` into a deny-list
        bytes2[] countries;
    }

    /// @notice Evaluates whether `account` satisfies `pool`'s configured
    ///         rule right now. Returns false rather than reverting for a
    ///         negative outcome — REST parity: "`/validator/verify` returns
    ///         HTTP 200 + valid:false when a user is not eligible. That is a
    ///         successful call with a negative outcome, not an error."
    function verify(address pool, address account) external view returns (bool valid);

    /// @notice The pool's currently configured rule.
    function rules(address pool) external view returns (Rule memory);

    /// @notice Whether the pool is paused. A paused pool must be treated as
    ///         "no one is eligible", not "check skipped".
    function isPaused(address pool) external view returns (bool);

    /// @notice Whether `pool` has completed Cleanverse registration at all.
    ///         An unregistered pool must fail closed — see
    ///         `Errors.ValidatorPoolNotConfigured`.
    function isRegistered(address pool) external view returns (bool);
}
