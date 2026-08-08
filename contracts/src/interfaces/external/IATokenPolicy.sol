// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IATokenPolicy
 * @notice Cleanverse's CVA (Cleanverse Verified Asset) policy interface
 * — also referred to as `IComplianceRule` in the CVA guide. Source:
 * "Cleanverse Compliance Protocol (CCP) CVA Integration Guide" (see
 * docs/cleanverse-integration.md §3, docs/cva-integration-specification.md
 * §3). This is intentionally a partial transcription — only what the
 * approved specification confirms is declared as a callable function
 * here. Do not add functions or types beyond what's confirmed; do not
 * guess at unconfirmed signatures (per Build 07.1's explicit "do not
 * guess" instruction).
 *
 * CONFIRMED: the CVA policy interface exists, gates every CVA transfer
 * via `canTransfer`, and uses the *same* `RuleV2` struct as the CVI
 * validator (`IAPassComplianceValidator.RuleV2`), with its own
 * function names (`canTransfer`, `setRuleV2`/`addRuleV2`/`removeRuleV2`,
 * `setRuleV2FromToken`/`addRuleV2FromToken`/`removeRuleV2FromToken`,
 * `getRulesV2`).
 *
 * NOT CONFIRMED and therefore NOT declared below: `canTransfer`'s
 * return type, visibility, and mutability; whether a rejected transfer
 * reverts or returns a boolean; the rule-management functions' full
 * parameter/return signatures. See BitVCVAAdapter's NatSpec for exactly
 * which of these this codebase calls, and which it deliberately does
 * not.
 */
interface IATokenPolicy {
    /**
     * @notice Identical field set to `IAPassComplianceValidator.RuleV2`
     * — the CVA guide states the CVA policy interface "uses the same
     * RuleV2 struct" as the CVI validator. Confirmed,
     * docs/cva-integration-specification.md §4.
     */
    struct RuleV2 {
        bytes2 allowedGroup;
        bytes2 allowedSubGroup;
        uint8 minTier;
        uint8 minSubTier;
        uint256 poolCountryBitmap;
    }

    /**
     * @notice Read the current RuleV2 set a CVA policy contract applies
     * to `token`.
     * @dev Function *name* and its role (reading a token's registered
     * RuleV2 set) are confirmed by the CVA guide. This specific
     * signature (one `address token` parameter, `external view`,
     * `RuleV2[] memory` return) is a **disclosed inference by analogy**
     * to `IAPassComplianceValidator.getRulesV2(address poolAddress)
     * external view returns (RuleV2[] memory)`, whose signature *is*
     * fully confirmed — reasonable because the CVA guide states the two
     * interfaces share the identical `RuleV2` struct, but this
     * particular function signature is not independently confirmed by
     * the CVA guide's own text. `BitVCVAAdapter.verifyInterface` uses
     * this call, via `staticcall`, purely as a read-only probe of
     * "does the configured contract respond the way a CVA policy
     * contract would be expected to" — not as proof of Cleanverse
     * approval. See docs/cva-integration-implementation.md for the full
     * disclosure of this inference.
     */
    function getRulesV2(address token) external view returns (RuleV2[] memory);

    // canTransfer(token, from, to, amount) is NOT declared here.
    // Its argument list is confirmed by the CVA guide
    // (docs/cva-integration-specification.md §3/§5), but its return
    // type, visibility, and mutability are not, and the CVA guide does
    // not state whether a rejected transfer reverts or returns a
    // boolean. Declaring a Solidity function signature here would
    // require guessing at least one of those — which Build 07.1's
    // instructions explicitly forbid. See
    // BitVCVAAdapter.previewTransfer's NatSpec for the interface
    // boundary this is preserved behind instead.

    // setRuleV2 / addRuleV2 / removeRuleV2 / setRuleV2FromToken /
    // addRuleV2FromToken / removeRuleV2FromToken are NOT declared here
    // either — their names are confirmed (CVA guide,
    // docs/cleanverse-integration.md §3) but full parameter/return
    // signatures are not, and BitV never calls them: these are the
    // *issuer's* rule-management functions (docs/cva-integration-
    // specification.md §13, "Unauthorized policy changes"), entirely
    // outside BitV's authority or intent to call.
}
