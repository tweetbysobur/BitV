// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdUtils} from "forge-std/StdUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {BitVRWACollateralRegistry} from "../../src/core/BitVRWACollateralRegistry.sol";
import {BitVCVAAdapter} from "../../src/core/BitVCVAAdapter.sol";
import {BitVLendingManager} from "../../src/core/BitVLendingManager.sol";
import {MockCVAPolicy} from "../mocks/MockCVAPolicy.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Bounded-random-action handler for CVA-status invariant
/// tests, mirroring RWAHandler.sol/VaultHandler.sol's established
/// pattern. Includes actions that only role-holders can legitimately
/// perform (via VM.prank(admin)) alongside a fuzzed "attempt as a
/// random actor" action that must always revert.
contract CVAHandler is StdUtils {
    Vm private constant VM = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    BitVRWACollateralRegistry public registry;
    BitVCVAAdapter public cvaAdapter;
    BitVLendingManager public lendingManager;
    MockERC20 public rwaAsset;
    MockERC20 public debtAsset;
    address public admin;
    MockCVAPolicy public goodPolicy;

    address[] public actors;

    /// @notice Ghost tracker: last admin-attestation value set via the
    /// handler's own role-holding action.
    bool public ghostLastAttestation;

    constructor(
        BitVRWACollateralRegistry registry_,
        BitVCVAAdapter cvaAdapter_,
        BitVLendingManager lendingManager_,
        MockERC20 rwaAsset_,
        MockERC20 debtAsset_,
        address admin_,
        address[] memory actors_
    ) {
        registry = registry_;
        cvaAdapter = cvaAdapter_;
        lendingManager = lendingManager_;
        rwaAsset = rwaAsset_;
        debtAsset = debtAsset_;
        admin = admin_;
        actors = actors_;
        goodPolicy = new MockCVAPolicy();
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function depositCollateral(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 boundedAmount = bound(amount, 1e6, 100e18);

        VM.startPrank(actor);
        rwaAsset.mint(actor, boundedAmount);
        rwaAsset.approve(address(lendingManager), boundedAmount);
        try lendingManager.depositCollateral(address(rwaAsset), boundedAmount) {} catch {}
        VM.stopPrank();
    }

    function borrow(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 boundedAmount = bound(amount, 1, 10_000e18);

        VM.startPrank(actor);
        try lendingManager.borrow(address(debtAsset), boundedAmount) {} catch {}
        VM.stopPrank();
    }

    function toggleFreeze(bool freeze) external {
        VM.startPrank(admin);
        try registry.setAssetStatus(
            address(rwaAsset),
            freeze ? BitVRWACollateralRegistry.AssetStatus.Frozen : BitVRWACollateralRegistry.AssetStatus.Active
        ) {} catch {}
        VM.stopPrank();
    }

    /// @notice The handler's only legitimate path to change CVA
    /// admin-attestation — the invariant suite checks nothing else can.
    function setCVAAttestation(bool attested) external {
        VM.prank(admin);
        registry.setCVAAttestation(address(rwaAsset), attested);
        ghostLastAttestation = attested;
    }

    function configurePolicyAndVerify() external {
        VM.startPrank(admin);
        cvaAdapter.setPolicyContract(address(rwaAsset), address(goodPolicy));
        try cvaAdapter.verifyInterface(address(rwaAsset)) {} catch {}
        VM.stopPrank();
    }

    /// @notice Fuzzed attempt at unauthorized CVA status mutation, from
    /// a non-role-holding actor — must always revert.
    function attemptUnauthorizedCVAAttestation(uint256 actorSeed, bool attested) external {
        address actor = _actor(actorSeed);
        VM.prank(actor);
        try registry.setCVAAttestation(address(rwaAsset), attested) {
            revert("unauthorized setCVAAttestation unexpectedly succeeded");
        } catch {}
    }

    /// @notice Fuzzed attempt at an unauthorized adapter swap — must
    /// always revert.
    function attemptUnauthorizedAdapterChange(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        VM.prank(actor);
        try registry.setCVAAdapter(address(0)) {
            revert("unauthorized setCVAAdapter unexpectedly succeeded");
        } catch {}
    }
}
