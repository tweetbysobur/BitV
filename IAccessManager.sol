// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IAccessManager
/// @notice Protocol-wide role management and Cleanverse-gated capability
///         checks. Every other manager contract calls `requireCapability`
///         (or the non-reverting `hasCapability`) before performing a
///         verification-gated action, rather than each reimplementing "call
///         the identity oracle, check the result, revert with the right
///         error" independently in six places.
interface IAccessManager {
    /// @notice Capability identifiers, matching the frontend's permission
    ///         engine 1:1 (`src/lib/cleanverse/permissions.ts`) — a capability
    ///         denied here must show the same user-facing capability the
    ///         dashboard already gated on, not a differently-named one.
    enum Capability {
        AccessLending,
        AccessBorrowing,
        JoinLiquidityPools,
        AccessYieldVaults,
        Governance
    }

    event CapabilityRequirementSet(Capability indexed capability, address indexed validatorPool);

    // `RoleGranted`/`RoleRevoked` are deliberately NOT redeclared here: the
    // implementation (`AccessManager`) already inherits `IAccessControl` via
    // `AccessControlUpgradeable`, which declares events with this exact name
    // and parameter set. Redeclaring an identically-shaped event in a second
    // interface the same contract implements is a compile error (Solidity
    // treats it as a duplicate definition, not a compatible override) — the
    // single inherited event already covers role-change notifications for
    // any indexer watching this contract's ABI.

    /// @notice Reverts with a specific `Errors.Identity*` error describing
    ///         WHY access is denied (unregistered / frozen / expired /
    ///         ineligible / pool not configured / pool paused) rather than a
    ///         generic `Unauthorized` — this is what lets the frontend map a
    ///         revert reason directly to the same remediation copy the
    ///         dashboard already shows for that condition
    ///         (`docs/cleanverse-integration.md` §identity states table).
    function requireCapability(Capability capability, address account) external view;

    /// @notice Non-reverting form, for read paths (e.g. rendering "eligible
    ///         pools" in a view function) that need a boolean, not a revert.
    function hasCapability(Capability capability, address account) external view returns (bool);

    /// @notice Governance: binds a capability to a Cleanverse Validator pool.
    ///         Passing `address(0)` removes the identity gate for that
    ///         capability entirely — used deliberately, not accidentally, and
    ///         only by `DEFAULT_ADMIN_ROLE`.
    function setCapabilityRequirement(Capability capability, address validatorPool) external;

    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
}
