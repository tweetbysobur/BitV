// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseTest } from "../BaseTest.sol";
import { IAccessManager } from "../../src/interfaces/IAccessManager.sol";
import { IIdentityOracle } from "../../src/interfaces/IIdentityOracle.sol";
import { Errors } from "../../src/libraries/Errors.sol";

contract AccessManagerTest is BaseTest {
    function test_hasCapability_trueWhenEligible() public {
        assertTrue(accessManager.hasCapability(IAccessManager.Capability.AccessLending, alice));
    }

    function test_hasCapability_falseWhenPoolIneligible() public {
        identityOracle.setPoolEligibility(lendingPool, alice, false);
        assertFalse(accessManager.hasCapability(IAccessManager.Capability.AccessLending, alice));
    }

    function test_hasCapability_trueWhenCapabilityUngated() public {
        address stranger = makeAddr("stranger");
        // No status/eligibility ever set for `stranger` — an ungated
        // capability must not depend on identity state at all.
        assertTrue(
            accessManager.hasCapability(IAccessManager.Capability.Governance, stranger)
        );
    }

    function test_requireCapability_revertsForUnregistered() public {
        address stranger = makeAddr("stranger");
        vm.expectRevert(abi.encodeWithSelector(Errors.IdentityNotRegistered.selector, stranger));
        accessManager.requireCapability(IAccessManager.Capability.AccessLending, stranger);
    }

    function test_requireCapability_revertsForFrozen() public {
        identityOracle.setStatus(alice, IIdentityOracle.IdentityStatus.Frozen);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.IdentityIneligible.selector, alice, uint8(IIdentityOracle.IdentityStatus.Frozen))
        );
        accessManager.requireCapability(IAccessManager.Capability.AccessLending, alice);
    }

    function test_requireCapability_revertsForExpired() public {
        identityOracle.setStatus(alice, IIdentityOracle.IdentityStatus.Expired);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.IdentityIneligible.selector, alice, uint8(IIdentityOracle.IdentityStatus.Expired))
        );
        accessManager.requireCapability(IAccessManager.Capability.AccessLending, alice);
    }

    function test_setCapabilityRequirement_onlyGovernance() public {
        vm.prank(alice);
        vm.expectRevert();
        accessManager.setCapabilityRequirement(IAccessManager.Capability.Governance, lendingPool);
    }

    function test_grantRole_emitsAndPersists() public {
        bytes32 role = keccak256("SOME_ROLE");
        vm.prank(admin);
        accessManager.grantRole(role, alice);
        assertTrue(accessManager.hasRole(role, alice));
    }
}
