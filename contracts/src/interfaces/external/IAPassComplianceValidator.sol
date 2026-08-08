// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAPassComplianceValidator
 * @notice Interface to Cleanverse's compliance validator — the compliance
 * authority BitV's protocol contracts consult before allowing protected
 * actions.
 *
 * SOURCE STATUS: this session was not able to directly fetch
 * docs.cleanverse.com (blocked by this environment's network egress
 * policy). The shapes below reflect only what was explicitly given in this
 * milestone's task as coming from the "Cleanverse Compliance Protocol
 * Integration Guide V2" — the `complianceVerify` signature and the
 * `RuleV2` field names. Concrete Solidity types for the `RuleV2` fields
 * were NOT specified in that description; the types chosen here
 * (`uint256` for tiers/groups, `uint256` bitmap for country flags) are an
 * ENGINEERING ASSUMPTION for compileability, not a confirmed doc value —
 * see docs/cleanverse-integration.md "UNCONFIRMED" section. Do not deploy
 * against a real Cleanverse validator until these types (and any
 * additional rule-management / view functions the real interface exposes)
 * are confirmed against the primary documentation.
 */
interface IAPassComplianceValidator {
    /**
     * @notice A single compliance rule. Fields within one RuleV2 combine
     * with AND logic; multiple RuleV2 entries governing the same pool
     * combine with OR logic (a user need only satisfy one rule).
     * @dev Field types are an engineering assumption — see file header.
     */
    struct RuleV2 {
        uint256 allowedGroup;
        uint256 allowedSubGroup;
        uint256 minTier;
        uint256 minSubTier;
        uint256 poolCountryBitmap;
    }

    /**
     * @notice Returns whether `userAddress` is compliant to interact with
     * `poolAddress` under whatever RuleV2 set Cleanverse has registered
     * for that pool.
     * @param poolAddress The BitV contract the user is trying to act on.
     * @param userAddress The user whose compliance status is being checked.
     * @return isCompliant True if the user satisfies at least one RuleV2
     * registered for `poolAddress` (OR across rules, AND within a rule).
     */
    function complianceVerify(address poolAddress, address userAddress) external view returns (bool isCompliant);

    // Rule-management / rule-lookup functions (e.g. registering a RuleV2
    // set for a pool, or reading the rules currently in effect) almost
    // certainly exist on the real validator, since BitV will need at least
    // a way to register its pools' rules and likely a way to read them for
    // UI display. Their exact signatures were not given in this
    // milestone's source material, so they are intentionally NOT declared
    // here rather than guessed — see docs/cleanverse-integration.md.
}
