// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAPassComplianceValidator} from "../../src/interfaces/external/IAPassComplianceValidator.sol";

/**
 * @notice Test-only mock of Cleanverse's IAPassComplianceValidator, used
 * solely inside isolated unit tests so BitV's compliance-hook wiring can
 * be verified without a real Cleanverse deployment. This must never be
 * used as, or mistaken for, a production implementation — see
 * docs/cleanverse-integration.md.
 */
contract MockComplianceValidator is IAPassComplianceValidator {
    mapping(address pool => RuleV2[] rules) private _rules;
    mapping(address user => mapping(uint256 group => uint256 subGroup)) private _userSubGroup;
    mapping(address user => uint256 tier) private _userTier;
    mapping(address user => uint256 subTier) private _userSubTier;
    mapping(address user => uint256 group) private _userGroup;
    mapping(address user => uint256 countryBit) private _userCountryBit;

    function setRules(address pool, RuleV2[] calldata rules) external {
        delete _rules[pool];
        for (uint256 i = 0; i < rules.length; i++) {
            _rules[pool].push(rules[i]);
        }
    }

    function setUser(address user, uint256 group, uint256 subGroup, uint256 tier, uint256 subTier, uint256 countryBit)
        external
    {
        _userGroup[user] = group;
        _userSubGroup[user][group] = subGroup;
        _userTier[user] = tier;
        _userSubTier[user] = subTier;
        _userCountryBit[user] = countryBit;
    }

    function complianceVerify(address poolAddress, address userAddress) external view returns (bool) {
        RuleV2[] storage rules = _rules[poolAddress];
        uint256 group = _userGroup[userAddress];
        uint256 subGroup = _userSubGroup[userAddress][group];
        uint256 tier = _userTier[userAddress];
        uint256 subTier = _userSubTier[userAddress];
        uint256 countryBit = _userCountryBit[userAddress];

        for (uint256 i = 0; i < rules.length; i++) {
            RuleV2 storage rule = rules[i];
            bool groupOk = group == rule.allowedGroup;
            bool subGroupOk = subGroup == rule.allowedSubGroup;
            bool tierOk = tier >= rule.minTier;
            bool subTierOk = subTier >= rule.minSubTier;
            bool countryOk = (rule.poolCountryBitmap & countryBit) != 0;

            if (groupOk && subGroupOk && tierOk && subTierOk && countryOk) {
                return true;
            }
        }
        return false;
    }
}
