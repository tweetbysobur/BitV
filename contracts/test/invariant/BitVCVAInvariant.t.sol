// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseRWATest} from "../BaseRWATest.sol";
import {CVAHandler} from "./CVAHandler.sol";
import {BitVRWACollateralRegistry} from "../../src/core/BitVRWACollateralRegistry.sol";
import {MockEmptyContract} from "../mocks/MockCVAPolicy.sol";

/**
 * @title BitVCVAInvariantTest
 * @notice Handler-based invariant tests for the CVA adapter + registry
 * extension (Build 07.1), covering the task's six required properties:
 * unverified CVA status cannot become verified through user actions,
 * CVA restrictions cannot increase borrowing capacity, CVI cannot be
 * bypassed through CVA, RWA eligibility cannot be bypassed through
 * CVA, unauthorized users cannot modify CVA status, and adapter failure
 * cannot create additional permissions.
 */
contract BitVCVAInvariantTest is BaseRWATest {
    CVAHandler internal handler;

    function setUp() public override {
        super.setUp();

        address[] memory actors = new address[](3);
        actors[0] = supplier;
        actors[1] = borrower;
        actors[2] = liquidator;

        handler = new CVAHandler(registry, cvaAdapter, lendingManager, collateralAsset, debtAsset, admin, actors);

        vm.startPrank(supplier);
        debtAsset.mint(supplier, 10_000_000e18);
        debtAsset.approve(address(poolManager), 10_000_000e18);
        poolManager.deposit(address(debtAsset), 10_000_000e18);
        vm.stopPrank();

        targetContract(address(handler));
    }

    /// 1. Unverified CVA status cannot become verified through user
    /// actions — only the handler's own admin-role action
    /// (`configurePolicyAndVerify`) can set `isCVAInterfaceVerified`
    /// true; a direct scenario probe confirms a non-admin can never
    /// achieve this regardless of accumulated fuzz state.
    function invariant_UnverifiedCVACannotBecomeVerifiedThroughUserActions() public {
        vm.prank(borrower); // a real, compliant actor — still not RWA_ADMIN_ROLE
        vm.expectRevert();
        cvaAdapter.verifyInterface(address(collateralAsset));

        vm.prank(borrower);
        vm.expectRevert();
        cvaAdapter.setPolicyContract(address(collateralAsset), address(0xBEEF));
    }

    /// 2. CVA restrictions (or CVA recognition) cannot increase
    /// borrowing capacity: whenever the asset is ineligible per the
    /// registry's existing gate, available borrow value from it is
    /// zero — regardless of what CVA attestation/verification state the
    /// fuzzer has produced.
    function invariant_CVARestrictionsCannotIncreaseBorrowCapacity() public view {
        if (registry.isEligibleForNewActivity(address(collateralAsset))) return;

        address[3] memory actors = [supplier, borrower, liquidator];
        for (uint256 i = 0; i < actors.length; i++) {
            assertEq(lendingManager.getUserAccountDataForBorrow(actors[i], address(debtAsset)).availableBorrowValue, 0);
        }
    }

    /// 3. CVI cannot be bypassed through CVA — a never-compliant wallet
    /// is rejected on deposit regardless of how "fully recognized" the
    /// CVA status is.
    function invariant_CVICannotBeBypassedThroughCVA() public {
        address neverCompliant = makeAddr("neverCompliantCVAFuzz");
        collateralAsset.mint(neverCompliant, 1e18);

        vm.startPrank(neverCompliant);
        collateralAsset.approve(address(lendingManager), 1e18);
        vm.expectRevert();
        lendingManager.depositCollateral(address(collateralAsset), 1e18);
        vm.stopPrank();
    }

    /// 4. RWA eligibility cannot be bypassed through CVA: forcing full
    /// CVA recognition (both flags true) never changes
    /// `isEligibleForNewActivity`'s answer relative to what the
    /// asset's actual status/oracle state would otherwise produce.
    function invariant_RWAEligibilityCannotBeBypassedThroughCVA() public {
        bool eligibleBefore = registry.isEligibleForNewActivity(address(collateralAsset));
        bool attestationBefore = registry.isCVAAdminAttested(address(collateralAsset));

        vm.prank(admin);
        registry.setCVAAttestation(address(collateralAsset), true);
        // Interface verification may already be true or false depending
        // on fuzzed state — either way, eligibility must be unaffected.

        assertEq(registry.isEligibleForNewActivity(address(collateralAsset)), eligibleBefore);

        // Restore exactly the pre-probe attestation value (not a
        // hardcoded false) so this probe doesn't itself desync the
        // handler's ghost-tracked attestation state used by
        // invariant_CVAAttestationOnlyChangedByAuthorizedPath.
        vm.prank(admin);
        registry.setCVAAttestation(address(collateralAsset), attestationBefore);
    }

    /// 5. Unauthorized users cannot modify CVA status — checked
    /// directly, not just via the handler's fuzzed attempt actions.
    function invariant_UnauthorizedUsersCannotModifyCVAStatus() public {
        vm.prank(liquidator); // a real, compliant actor — still not RWA_ADMIN_ROLE
        vm.expectRevert();
        registry.setCVAAttestation(address(collateralAsset), true);

        vm.prank(liquidator);
        vm.expectRevert();
        registry.setCVAAdapter(address(0xBEEF));
    }

    /// 5b. The registry's CVA-adapter reference and admin-attestation
    /// state only ever move via the handler's own tracked, authorized
    /// paths.
    function invariant_CVAAttestationOnlyChangedByAuthorizedPath() public view {
        assertEq(registry.isCVAAdminAttested(address(collateralAsset)), handler.ghostLastAttestation());
    }

    /// 6. Adapter failure cannot create additional permissions: pointing
    /// the registry at a broken/non-conforming adapter reference must
    /// never make `isCVAInterfaceVerified`/`isCVAFullyRecognized`
    /// report `true`, and must never affect the actual, existing
    /// eligibility gate.
    function invariant_AdapterFailureCannotCreateAdditionalPermissions() public {
        MockEmptyContract brokenAdapter = new MockEmptyContract();
        bool eligibleBefore = registry.isEligibleForNewActivity(address(collateralAsset));

        vm.prank(admin);
        registry.setCVAAdapter(address(brokenAdapter));

        assertFalse(registry.isCVAInterfaceVerified(address(collateralAsset)));
        assertFalse(registry.isCVAFullyRecognized(address(collateralAsset)));
        assertEq(registry.isEligibleForNewActivity(address(collateralAsset)), eligibleBefore);

        // Restore the real adapter so subsequent fuzzed calls / other
        // invariant checks in the same run aren't affected.
        vm.prank(admin);
        registry.setCVAAdapter(address(cvaAdapter));
    }
}
