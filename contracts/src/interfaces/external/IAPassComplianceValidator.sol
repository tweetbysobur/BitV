// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAPassComplianceValidator
 * @notice Cleanverse's CVI (Cleanverse Verified Identity) compliance
 * validator — the compliance authority BitV's protocol contracts consult
 * before allowing protected actions.
 *
 * Source: "Cleanverse Compliance Protocol (CCP) Integration Guide (For CVI
 * Compliance Validator) V2" — official PDF provided directly by the user
 * (not a search summary or task-relayed paraphrase). Section 3 (Core
 * Interface Specification) is transcribed verbatim below. This supersedes
 * the earlier version of this file, which had guessed `RuleV2` field
 * types (`uint256` for everything) before this document was available —
 * see docs/cleanverse-integration.md for the correction note.
 */
interface IAPassComplianceValidator {
    /**
     * @notice A single compliance rule. Fields within one RuleV2 combine
     * with AND logic; multiple RuleV2 entries registered for the same pool
     * combine with OR logic. Country bitmaps are checked via bitwise AND.
     * @dev Verbatim from the CVI Integration Guide V2, §3.1.
     */
    struct RuleV2 {
        bytes2 allowedGroup; // Allowed CVI group (empty = no restriction)
        bytes2 allowedSubGroup; // Allowed CVI sub-group (empty = no restriction)
        uint8 minTier; // Minimum CVI tier (0 = no restriction)
        uint8 minSubTier; // Minimum CVI sub-tier (0 = no restriction)
        uint256 poolCountryBitmap; // Country bitmap (0 = no restriction)
    }

    // ── Registration (REGISTER_ROLE) ────────────────────────────────────
    // Called by whatever holds REGISTER_ROLE on the validator — in
    // Single-Contract Mode that's granted per-contract via Cleanverse's
    // off-chain registration API (POST /api/cooperate/validator/register),
    // not by BitV itself. BitV's contracts declare these for completeness
    // of the interface but do not call them from Single-Contract Mode.

    function registerV2(address poolAddress, RuleV2 calldata rule) external;
    function registerApass(address poolAddress, address aTokenAddress) external;
    function registerApass(address poolAddress, address aTokenAddress, address feeAddress) external;
    function setRuleV2FromRegistrar(address poolAddress, RuleV2 calldata rule) external;
    function isRegistered(address poolAddress) external view returns (bool);

    // ── Rule Management (called by the business contract itself) ───────
    // These are the ones BitV's protocol contracts actually call, gated
    // behind their own Ownable/AccessControl — see BitVComplianceGuard.

    function setRuleV2FromContract(RuleV2 calldata rule) external;
    function addRuleV2FromContract(RuleV2 calldata rule) external;
    function removeRuleV2FromContract(uint256 index) external;
    function getRulesV2(address poolAddress) external view returns (RuleV2[] memory);

    // ── Compliance Verification (no permission required) ───────────────

    function complianceVerify(address poolAddress, address userAddress) external view returns (bool);
}
