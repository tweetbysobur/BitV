// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BitVPoolManager} from "../../src/core/BitVPoolManager.sol";
import {ComplianceErrors} from "../../src/libraries/ComplianceErrors.sol";
import {IAPassComplianceValidator} from "../../src/interfaces/external/IAPassComplianceValidator.sol";
import {MockComplianceValidator} from "../mocks/MockComplianceValidator.sol";

/// @notice Unit tests for the compliance-hook wiring (BitVComplianceGuard),
/// exercised through BitVPoolManager as a representative protected
/// contract. MockComplianceValidator is a test-only stand-in — see its
/// NatSpec — not a claim about Cleanverse's real behavior.
contract BitVComplianceGuardTest is Test {
    MockComplianceValidator internal validator;
    BitVPoolManager internal pool;

    address internal owner = makeAddr("owner");
    address internal verifiedUser = makeAddr("verifiedUser");
    address internal unverifiedUser = makeAddr("unverifiedUser");

    bytes2 internal constant GROUP_RETAIL = bytes2("rt");
    bytes2 internal constant GROUP_INSTITUTIONAL = bytes2("in");
    bytes2 internal constant SUBGROUP_STANDARD = bytes2("st");
    uint8 internal constant TIER_2 = 2;
    uint8 internal constant SUBTIER_1 = 1;
    uint256 internal constant COUNTRY_US = 1 << 0;
    uint256 internal constant COUNTRY_RESTRICTED = 1 << 5;

    function setUp() public {
        validator = new MockComplianceValidator();
        pool = new BitVPoolManager(address(validator), owner);
    }

    function _baseRule() internal pure returns (IAPassComplianceValidator.RuleV2 memory) {
        return IAPassComplianceValidator.RuleV2({
            allowedGroup: GROUP_RETAIL,
            allowedSubGroup: SUBGROUP_STANDARD,
            minTier: TIER_2,
            minSubTier: SUBTIER_1,
            poolCountryBitmap: COUNTRY_US
        });
    }

    /// 1. Verified user can pass compliance.
    function test_VerifiedUserPassesCompliance() public {
        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](1);
        rules[0] = _baseRule();
        validator.setRules(address(pool), rules);
        validator.setUser(verifiedUser, GROUP_RETAIL, SUBGROUP_STANDARD, TIER_2, SUBTIER_1, COUNTRY_US);

        assertTrue(validator.complianceVerify(address(pool), verifiedUser));
    }

    /// 2. Unverified user is rejected (no CVI ever set, doesn't satisfy
    /// the restricted rule below).
    function test_UnverifiedUserIsRejected() public {
        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](1);
        rules[0] = _baseRule();
        validator.setRules(address(pool), rules);
        // unverifiedUser has all-zero CVI — never configured.

        assertFalse(validator.complianceVerify(address(pool), unverifiedUser));
    }

    /// 3. Wrong group is rejected.
    function test_WrongGroupIsRejected() public {
        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](1);
        rules[0] = _baseRule();
        validator.setRules(address(pool), rules);
        validator.setUser(verifiedUser, GROUP_INSTITUTIONAL, SUBGROUP_STANDARD, TIER_2, SUBTIER_1, COUNTRY_US);

        assertFalse(validator.complianceVerify(address(pool), verifiedUser));
    }

    /// 4. Wrong tier is rejected.
    function test_WrongTierIsRejected() public {
        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](1);
        rules[0] = _baseRule();
        validator.setRules(address(pool), rules);
        validator.setUser(verifiedUser, GROUP_RETAIL, SUBGROUP_STANDARD, TIER_2 - 1, SUBTIER_1, COUNTRY_US);

        assertFalse(validator.complianceVerify(address(pool), verifiedUser));
    }

    /// 5. Country restriction is enforced.
    function test_CountryRestrictionIsEnforced() public {
        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](1);
        rules[0] = _baseRule();
        validator.setRules(address(pool), rules);
        validator.setUser(verifiedUser, GROUP_RETAIL, SUBGROUP_STANDARD, TIER_2, SUBTIER_1, COUNTRY_RESTRICTED);

        assertFalse(validator.complianceVerify(address(pool), verifiedUser));
    }

    /// 6. Multiple conditions within one rule use AND logic — satisfying
    /// every field but one still fails.
    function test_MultipleConditionsUseAndLogic() public {
        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](1);
        rules[0] = _baseRule();
        validator.setRules(address(pool), rules);

        // Everything correct except subTier.
        validator.setUser(verifiedUser, GROUP_RETAIL, SUBGROUP_STANDARD, TIER_2, SUBTIER_1 - 1, COUNTRY_US);
        assertFalse(validator.complianceVerify(address(pool), verifiedUser));

        // Now fix subTier — all AND conditions satisfied.
        validator.setUser(verifiedUser, GROUP_RETAIL, SUBGROUP_STANDARD, TIER_2, SUBTIER_1, COUNTRY_US);
        assertTrue(validator.complianceVerify(address(pool), verifiedUser));
    }

    /// 7. Multiple rules use OR logic — failing rule A but satisfying
    /// rule B still passes.
    function test_MultipleRulesUseOrLogic() public {
        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](2);
        rules[0] = _baseRule(); // requires GROUP_RETAIL / TIER_2 / COUNTRY_US
        rules[1] = IAPassComplianceValidator.RuleV2({
            allowedGroup: GROUP_INSTITUTIONAL,
            allowedSubGroup: SUBGROUP_STANDARD,
            minTier: 1,
            minSubTier: 0,
            poolCountryBitmap: COUNTRY_RESTRICTED
        });
        validator.setRules(address(pool), rules);

        // Satisfies rule[1] only.
        validator.setUser(verifiedUser, GROUP_INSTITUTIONAL, SUBGROUP_STANDARD, 1, 0, COUNTRY_RESTRICTED);
        assertTrue(validator.complianceVerify(address(pool), verifiedUser));
    }

    /// 8. Protected functions cannot bypass compliance — calling a
    /// protected action as a non-compliant user reverts with the
    /// compliance error, not with NotImplemented (i.e. the check runs
    /// first and actually blocks execution).
    function test_ProtectedFunctionCannotBypassCompliance() public {
        // No rules registered for `pool` at all — unverifiedUser cannot pass.
        vm.prank(unverifiedUser);
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceErrors.ComplianceCheckFailed.selector, address(pool), unverifiedUser)
        );
        pool.addLiquidity(address(0xBEEF), 1 ether);
    }

    /// A compliant user reaches the NotImplemented stub, proving the
    /// compliance check is not what's blocking them.
    function test_CompliantUserReachesNotImplementedStub() public {
        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](1);
        rules[0] = _baseRule();
        validator.setRules(address(pool), rules);
        validator.setUser(verifiedUser, GROUP_RETAIL, SUBGROUP_STANDARD, TIER_2, SUBTIER_1, COUNTRY_US);

        vm.prank(verifiedUser);
        vm.expectRevert(ComplianceErrors.NotImplemented.selector);
        pool.addLiquidity(address(0xBEEF), 1 ether);
    }

    /// 9. Validator address cannot be arbitrarily changed: it's set once
    /// in the constructor as `immutable`, there is no setter, and a zero
    /// address is rejected at construction.
    function test_ValidatorAddressIsImmutableAndCannotBeZero() public {
        assertEq(address(pool.COMPLIANCE_VALIDATOR()), address(validator));

        vm.expectRevert(ComplianceErrors.ZeroValidatorAddress.selector);
        new BitVPoolManager(address(0), owner);
    }

    /// Rule-management wrappers (guide §5.2/§6) are owner-gated.
    function test_RuleManagementIsOwnerGated() public {
        IAPassComplianceValidator.RuleV2 memory rule = _baseRule();

        vm.expectRevert();
        vm.prank(unverifiedUser);
        pool.setRuleV2FromContract(rule);

        vm.prank(owner);
        pool.setRuleV2FromContract(rule);

        IAPassComplianceValidator.RuleV2[] memory stored = pool.getRulesV2();
        assertEq(stored.length, 1);
        assertEq(stored[0].allowedGroup, GROUP_RETAIL);
    }
}
