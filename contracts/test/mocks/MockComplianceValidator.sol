// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAPassComplianceValidator} from "../../src/interfaces/external/IAPassComplianceValidator.sol";

/**
 * @notice Test-only mock of Cleanverse's IAPassComplianceValidator
 * (CVI Integration Guide V2), used solely inside isolated unit tests so
 * BitV's compliance-hook wiring can be verified without a real Cleanverse
 * deployment. This must never be used as, or mistaken for, a production
 * implementation — see docs/cleanverse-integration.md.
 *
 * Validation semantics implemented per the guide, §3.1: within a RuleV2,
 * an empty (`bytes2(0)`) `allowedGroup`/`allowedSubGroup` or zero
 * `minTier`/`minSubTier`/`poolCountryBitmap` means "no restriction" on
 * that field; all non-restricted-or-satisfied fields combine with AND.
 * Multiple RuleV2 entries for the same pool combine with OR.
 */
contract MockComplianceValidator is IAPassComplianceValidator {
    mapping(address pool => RuleV2[] rules) private _rules;
    mapping(address pool => bool registered) private _registered;

    struct MockCvi {
        bytes2 group;
        bytes2 subGroup;
        uint8 tier;
        uint8 subTier;
        uint256 countryBit;
    }

    mapping(address user => MockCvi cvi) private _cvi;

    // ── Test helpers (not part of the real interface) ───────────────────

    function setUser(address user, bytes2 group, bytes2 subGroup, uint8 tier, uint8 subTier, uint256 countryBit)
        external
    {
        _cvi[user] = MockCvi(group, subGroup, tier, subTier, countryBit);
    }

    function setRules(address pool, RuleV2[] calldata rules) external {
        delete _rules[pool];
        for (uint256 i = 0; i < rules.length; i++) {
            _rules[pool].push(rules[i]);
        }
        _registered[pool] = true;
    }

    // ── Registration (REGISTER_ROLE in the real validator) ──────────────

    function registerV2(address poolAddress, RuleV2 calldata rule) external {
        delete _rules[poolAddress];
        _rules[poolAddress].push(rule);
        _registered[poolAddress] = true;
    }

    function registerApass(address poolAddress, address /* aTokenAddress */ ) external {
        _registered[poolAddress] = true;
    }

    function registerApass(address poolAddress, address, /* aTokenAddress */ address /* feeAddress */ ) external {
        _registered[poolAddress] = true;
    }

    function setRuleV2FromRegistrar(address poolAddress, RuleV2 calldata rule) external {
        delete _rules[poolAddress];
        _rules[poolAddress].push(rule);
    }

    function isRegistered(address poolAddress) external view returns (bool) {
        return _registered[poolAddress];
    }

    // ── Rule Management (business contract itself, keyed by msg.sender) ─

    function setRuleV2FromContract(RuleV2 calldata rule) external {
        delete _rules[msg.sender];
        _rules[msg.sender].push(rule);
        _registered[msg.sender] = true;
    }

    function addRuleV2FromContract(RuleV2 calldata rule) external {
        _rules[msg.sender].push(rule);
        _registered[msg.sender] = true;
    }

    function removeRuleV2FromContract(uint256 index) external {
        RuleV2[] storage rules = _rules[msg.sender];
        require(index < rules.length, "index out of range");
        rules[index] = rules[rules.length - 1];
        rules.pop();
    }

    function getRulesV2(address poolAddress) external view returns (RuleV2[] memory) {
        return _rules[poolAddress];
    }

    // ── Compliance Verification (no permission required) ────────────────

    function complianceVerify(address poolAddress, address userAddress) external view returns (bool) {
        RuleV2[] storage rules = _rules[poolAddress];
        MockCvi storage cvi = _cvi[userAddress];

        for (uint256 i = 0; i < rules.length; i++) {
            RuleV2 storage rule = rules[i];

            bool groupOk = rule.allowedGroup == bytes2(0) || rule.allowedGroup == cvi.group;
            bool subGroupOk = rule.allowedSubGroup == bytes2(0) || rule.allowedSubGroup == cvi.subGroup;
            bool tierOk = rule.minTier == 0 || cvi.tier >= rule.minTier;
            bool subTierOk = rule.minSubTier == 0 || cvi.subTier >= rule.minSubTier;
            bool countryOk = rule.poolCountryBitmap == 0 || (rule.poolCountryBitmap & cvi.countryBit) != 0;

            if (groupOk && subGroupOk && tierOk && subTierOk && countryOk) {
                return true;
            }
        }
        return false;
    }
}
