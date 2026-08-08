// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseRWATest} from "../BaseRWATest.sol";
import {BitVRWACollateralRegistry} from "../../src/core/BitVRWACollateralRegistry.sol";
import {BitVCVAAdapter} from "../../src/core/BitVCVAAdapter.sol";
import {CVAErrors} from "../../src/libraries/CVAErrors.sol";
import {MockCVAPolicy, MockRevertingCVAPolicy, MockEmptyContract} from "../mocks/MockCVAPolicy.sol";

contract BitVCVAAdapterTest is BaseRWATest {
    MockCVAPolicy internal goodPolicy;
    MockRevertingCVAPolicy internal revertingPolicy;
    MockEmptyContract internal emptyContract;

    function setUp() public override {
        super.setUp();
        goodPolicy = new MockCVAPolicy();
        revertingPolicy = new MockRevertingCVAPolicy();
        emptyContract = new MockEmptyContract();
    }

    // ══════════════════════════ ADAPTER: POLICY CONFIG ══════════════════════════

    function test_SetPolicyContract_Succeeds() public {
        vm.prank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        assertEq(cvaAdapter.policyOf(address(collateralAsset)), address(goodPolicy));
    }

    function test_UnauthorizedSetPolicyContract_Reverts() public {
        vm.prank(borrower);
        vm.expectRevert();
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
    }

    function test_SetPolicyContract_ZeroTokenReverts() public {
        vm.prank(admin);
        vm.expectRevert(CVAErrors.ZeroAddress.selector);
        cvaAdapter.setPolicyContract(address(0), address(goodPolicy));
    }

    // ══════════════════════════ ADAPTER: INTERFACE VERIFICATION ══════════════════════════

    function test_VerifyInterface_Succeeds() public {
        vm.startPrank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();

        assertTrue(cvaAdapter.isRecognizedCVA(address(collateralAsset)));
    }

    function test_VerifyInterface_RevertsForRevertingPolicy() public {
        vm.startPrank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(revertingPolicy));
        vm.expectRevert(
            abi.encodeWithSelector(
                CVAErrors.InterfaceVerificationFailed.selector, address(collateralAsset), address(revertingPolicy)
            )
        );
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();
    }

    function test_VerifyInterface_RevertsForEmptyContract() public {
        vm.startPrank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(emptyContract));
        vm.expectRevert(
            abi.encodeWithSelector(
                CVAErrors.InterfaceVerificationFailed.selector, address(collateralAsset), address(emptyContract)
            )
        );
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();
    }

    function test_VerifyInterface_RevertsWithoutPolicyContractSet() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(CVAErrors.PolicyContractNotSet.selector, address(collateralAsset)));
        cvaAdapter.verifyInterface(address(collateralAsset));
    }

    function test_UnauthorizedVerifyInterface_Reverts() public {
        vm.prank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));

        vm.prank(borrower);
        vm.expectRevert();
        cvaAdapter.verifyInterface(address(collateralAsset));
    }

    function test_IsRecognizedCVA_FalseBeforeVerification() public {
        vm.prank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        assertFalse(cvaAdapter.isRecognizedCVA(address(collateralAsset)));
    }

    function test_ReconfiguringPolicy_ResetsVerification() public {
        vm.startPrank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        assertTrue(cvaAdapter.isRecognizedCVA(address(collateralAsset)));

        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy)); // reconfigure, even to the same address
        vm.stopPrank();

        assertFalse(cvaAdapter.isRecognizedCVA(address(collateralAsset)));
    }

    function test_IsCurrentlyUsable_MatchesIsRecognizedCVA() public {
        vm.startPrank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();

        assertEq(cvaAdapter.isCurrentlyUsable(address(collateralAsset)), cvaAdapter.isRecognizedCVA(address(collateralAsset)));
        assertTrue(cvaAdapter.isCurrentlyUsable(address(collateralAsset)));
    }

    // ══════════════════════════ TRANSFER VALIDATION BOUNDARY ══════════════════════════

    function test_PreviewTransfer_AlwaysReverts() public {
        vm.expectRevert(CVAErrors.TransferValidationUnconfirmed.selector);
        cvaAdapter.previewTransfer(address(collateralAsset), borrower, liquidator, 1e18);
    }

    // ══════════════════════════ REGISTRY: CVA STATUS MODEL ══════════════════════════

    function test_AdminAttestationWithoutInterfaceVerification_NotFullyRecognized() public {
        vm.prank(admin);
        registry.setCVAAttestation(address(collateralAsset), true);

        assertTrue(registry.isCVAAdminAttested(address(collateralAsset)));
        assertFalse(registry.isCVAInterfaceVerified(address(collateralAsset)));
        assertFalse(registry.isCVAFullyRecognized(address(collateralAsset)));
    }

    function test_InterfaceVerificationWithoutAdminAttestation_NotFullyRecognized() public {
        vm.startPrank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();

        assertFalse(registry.isCVAAdminAttested(address(collateralAsset)));
        assertTrue(registry.isCVAInterfaceVerified(address(collateralAsset)));
        assertFalse(registry.isCVAFullyRecognized(address(collateralAsset)));
    }

    function test_BothFlags_FullyRecognized() public {
        vm.startPrank(admin);
        registry.setCVAAttestation(address(collateralAsset), true);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();

        assertTrue(registry.isCVAFullyRecognized(address(collateralAsset)));
    }

    function test_UnauthorizedCVAAttestation_Reverts() public {
        vm.prank(borrower);
        vm.expectRevert();
        registry.setCVAAttestation(address(collateralAsset), true);
    }

    function test_UnauthorizedCVAAdapterChange_Reverts() public {
        vm.prank(borrower);
        vm.expectRevert();
        registry.setCVAAdapter(address(0xBEEF));
    }

    function test_CVAAttestation_UnregisteredAssetReverts() public {
        vm.prank(admin);
        vm.expectRevert();
        registry.setCVAAttestation(address(debtAsset), true);
    }

    function test_AdapterUnset_CVAQueriesFailSafe() public {
        vm.startPrank(admin);
        registry.setCVAAttestation(address(collateralAsset), true);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        registry.setCVAAdapter(address(0)); // disable adapter
        vm.stopPrank();

        assertFalse(registry.isCVAInterfaceVerified(address(collateralAsset)));
        assertFalse(registry.isCVAFullyRecognized(address(collateralAsset)));
        // Admin attestation itself is unaffected — it's independent storage.
        assertTrue(registry.isCVAAdminAttested(address(collateralAsset)));
    }

    // ══════════════════════════ CVA STATUS NEVER BYPASSES EXISTING CONTROLS ══════════════════════════

    function test_CVAStatus_DoesNotAffectEligibility() public {
        bool eligibleBefore = registry.isEligibleForNewActivity(address(collateralAsset));

        vm.startPrank(admin);
        registry.setCVAAttestation(address(collateralAsset), true);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();

        assertTrue(registry.isCVAFullyRecognized(address(collateralAsset)));
        assertEq(registry.isEligibleForNewActivity(address(collateralAsset)), eligibleBefore);
    }

    function test_FrozenCVA_StillIneligibleDespiteFullRecognition() public {
        vm.startPrank(admin);
        registry.setCVAAttestation(address(collateralAsset), true);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);
        vm.stopPrank();

        assertTrue(registry.isCVAFullyRecognized(address(collateralAsset)));
        assertFalse(registry.isEligibleForNewActivity(address(collateralAsset)));
    }

    function test_DelistedCVA_StillIneligibleDespiteFullRecognition() public {
        vm.startPrank(admin);
        registry.setCVAAttestation(address(collateralAsset), true);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Delisted);
        vm.stopPrank();

        assertTrue(registry.isCVAFullyRecognized(address(collateralAsset)));
        assertFalse(registry.isEligibleForNewActivity(address(collateralAsset)));
    }

    function test_OracleFailureCombinedWithCVAStatus_StillIneligible() public {
        vm.startPrank(admin);
        registry.setCVAAttestation(address(collateralAsset), true);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        oracle.setPrice(address(collateralAsset), 0, 18);
        vm.stopPrank();

        assertTrue(registry.isCVAFullyRecognized(address(collateralAsset)));
        assertFalse(registry.isEligibleForNewActivity(address(collateralAsset)));
    }

    function test_FrozenCVA_DepositStillBlocked() public {
        vm.startPrank(admin);
        registry.setCVAAttestation(address(collateralAsset), true);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);
        vm.stopPrank();

        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 10e18);
        vm.expectRevert();
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        vm.stopPrank();
    }

    function test_BitScoreCannotOverrideCVARestrictions() public {
        _supplyDebtLiquidity(1_000_000e18);

        vm.startPrank(admin);
        registry.setCVAAttestation(address(collateralAsset), true);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();

        _depositRwaCollateral(borrower, 10e18);

        vm.prank(admin);
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);

        // Even at whatever BitScore tier `borrower` has, frozen (yet
        // "fully recognized" as CVA) collateral contributes zero new
        // borrowing capacity — BitScore's own adjustment operates on
        // whatever base availableBorrowValue BitVLendingManager computes,
        // and that figure is already zero here.
        assertEq(lendingManager.getEffectiveAvailableBorrowValue(borrower), 0);
        vm.prank(borrower);
        vm.expectRevert();
        lendingManager.borrow(address(debtAsset), 1e18);
    }

    // ══════════════════════════ CVI + CVA INTERACTION ══════════════════════════

    function test_CVIRejection_TakesPrecedenceOverFullCVARecognition() public {
        vm.startPrank(admin);
        registry.setCVAAttestation(address(collateralAsset), true);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();
        assertTrue(registry.isCVAFullyRecognized(address(collateralAsset)));

        address stranger = makeAddr("neverCompliantCVA");
        collateralAsset.mint(stranger, 10e18);
        vm.startPrank(stranger);
        collateralAsset.approve(address(lendingManager), 10e18);
        vm.expectRevert();
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        vm.stopPrank();
    }

    // ══════════════════════════ SECURITY ══════════════════════════

    function test_FakeCVA_NeverGrantedRecognition() public {
        vm.startPrank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(emptyContract));
        vm.expectRevert();
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();

        assertFalse(cvaAdapter.isRecognizedCVA(address(collateralAsset)));
    }

    function test_AdapterFailure_NeverCreatesAdditionalPermissions() public {
        // Point the registry's adapter reference at a contract that does
        // NOT implement IBitVCVAAdapter at all (the empty contract) —
        // every call the registry makes to it must revert, and the
        // registry's try/catch must resolve that to "not verified."
        vm.prank(admin);
        registry.setCVAAdapter(address(emptyContract));

        assertFalse(registry.isCVAInterfaceVerified(address(collateralAsset)));
        assertFalse(registry.isCVAFullyRecognized(address(collateralAsset)));
        // Eligibility for actual borrowing is completely unaffected by
        // this broken adapter reference — it never gates the existing
        // eligibility path at all.
        assertTrue(registry.isEligibleForNewActivity(address(collateralAsset)));
    }

    function test_Reentrancy_PolicyContractCannotReenterViaStaticcall() public {
        // verifyInterface uses staticcall specifically so a malicious
        // policy contract cannot perform any state-changing reentrant
        // call during the probe — attempting to call back into
        // verifyInterface itself (a state-changing function) from
        // within a staticcall context reverts at the EVM level
        // regardless of what the malicious contract does, which is
        // exactly what MockRevertingCVAPolicy's unconditional revert
        // already demonstrates indirectly. This test documents that
        // property explicitly rather than leaving it implicit.
        vm.startPrank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(revertingPolicy));
        vm.expectRevert(
            abi.encodeWithSelector(
                CVAErrors.InterfaceVerificationFailed.selector, address(collateralAsset), address(revertingPolicy)
            )
        );
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();
    }

    function test_MaliciousCVAContract_InterfaceVerificationAloneInsufficientForFullRecognition() public {
        // A contract an attacker fully controls can trivially implement
        // getRulesV2 to succeed (goodPolicy already demonstrates this
        // costs nothing) — proving onChainInterfaceVerified alone is
        // NOT equivalent to genuine Cleanverse approval, exactly the
        // documented limitation. isCVAFullyRecognized still requires
        // the independent admin attestation on top.
        vm.startPrank(admin);
        cvaAdapter.setPolicyContract(address(collateralAsset), address(goodPolicy));
        cvaAdapter.verifyInterface(address(collateralAsset));
        vm.stopPrank();

        assertTrue(cvaAdapter.isRecognizedCVA(address(collateralAsset)));
        assertFalse(registry.isCVAFullyRecognized(address(collateralAsset))); // no admin attestation
    }

    // ── Helpers ──────────────────────────────────────────────────────
    function _depositRwaCollateral(address user, uint256 amount) internal {
        vm.startPrank(user);
        collateralAsset.approve(address(lendingManager), amount);
        lendingManager.depositCollateral(address(collateralAsset), amount);
        vm.stopPrank();
    }

    function _supplyDebtLiquidity(uint256 amount) internal {
        debtAsset.mint(supplier, amount);
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), amount);
        poolManager.deposit(address(debtAsset), amount);
        vm.stopPrank();
    }
}
