// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAPassComplianceValidator} from "../interfaces/external/IAPassComplianceValidator.sol";
import {ComplianceErrors} from "../libraries/ComplianceErrors.sol";

/**
 * @title BitVComplianceGuard
 * @notice Shared base for every BitV protocol contract integrating
 * Cleanverse's IAPassComplianceValidator in Single-Contract Mode (per
 * the CVI Integration Guide V2, §5 "Pattern 2: Single-Contract Mode" —
 * "does not require Factory authorization. Deploy the contract and
 * register it via the API to start using the validator").
 *
 * Mirrors the guide's `CompliantLending` template: stores the validator
 * address as `immutable`, exposes `complianceVerify`-gated checks for
 * protected actions, and exposes owner-gated RuleV2 rule-management
 * wrappers (`setRuleV2FromContract` / `addRuleV2FromContract` /
 * `removeRuleV2FromContract` / `getRulesV2`) since — per §5.3 step 3 —
 * "the operator sets rules via setRuleV2FromContract" on the business
 * contract itself in Single-Contract Mode, not via a Factory.
 *
 * Off-chain, this contract's address must still be registered with
 * Cleanverse (POST /api/cooperate/validator/register, §5.4) before
 * `complianceVerify` will return true for anyone — that registration call
 * is outside this contract's scope.
 */
abstract contract BitVComplianceGuard is Ownable {
    /// @notice The Cleanverse compliance validator this contract trusts.
    IAPassComplianceValidator public immutable COMPLIANCE_VALIDATOR;

    constructor(address complianceValidator, address owner_) Ownable(owner_) {
        if (complianceValidator == address(0)) revert ComplianceErrors.ZeroValidatorAddress();
        COMPLIANCE_VALIDATOR = IAPassComplianceValidator(complianceValidator);
    }

    /**
     * @notice Reverts unless `user` passes Cleanverse compliance for this
     * contract (used as the `poolAddress` in complianceVerify).
     */
    function _requireCompliance(address user) internal view {
        if (!COMPLIANCE_VALIDATOR.complianceVerify(address(this), user)) {
            revert ComplianceErrors.ComplianceCheckFailed(address(this), user);
        }
    }

    // ── V2 Rule Management (guide §5.2 / §6) ────────────────────────────
    // "Access Control: The business contract should enforce onlyOwner or
    // AccessControl on rule management methods." (guide, "Compliance Rule
    // Management" section).

    /// @notice Replace all RuleV2 rules for this contract.
    function setRuleV2FromContract(IAPassComplianceValidator.RuleV2 calldata rule) external onlyOwner {
        COMPLIANCE_VALIDATOR.setRuleV2FromContract(rule);
    }

    /// @notice Append a RuleV2 rule (OR logic against existing rules).
    function addRuleV2FromContract(IAPassComplianceValidator.RuleV2 calldata rule) external onlyOwner {
        COMPLIANCE_VALIDATOR.addRuleV2FromContract(rule);
    }

    /// @notice Remove a RuleV2 rule by index.
    function removeRuleV2FromContract(uint256 index) external onlyOwner {
        COMPLIANCE_VALIDATOR.removeRuleV2FromContract(index);
    }

    /// @notice Read the current RuleV2 rules registered for this contract.
    function getRulesV2() external view returns (IAPassComplianceValidator.RuleV2[] memory) {
        return COMPLIANCE_VALIDATOR.getRulesV2(address(this));
    }
}
