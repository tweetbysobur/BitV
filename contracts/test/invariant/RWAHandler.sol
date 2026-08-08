// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdUtils} from "forge-std/StdUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {BitVLendingManager} from "../../src/core/BitVLendingManager.sol";
import {BitVPoolManager} from "../../src/core/BitVPoolManager.sol";
import {BitVRWACollateralRegistry} from "../../src/core/BitVRWACollateralRegistry.sol";
import {StaticPriceOracle} from "../../src/oracles/StaticPriceOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Bounded-random-action handler for the RWA registry's
/// invariant tests, mirroring Handler.sol / VaultHandler.sol's
/// established pattern: every action is wrapped so a revert is
/// swallowed, and a dedicated "attacker" actor's unauthorized attempts
/// are asserted to always revert rather than silently skipped.
contract RWAHandler is StdUtils {
    Vm private constant VM = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    BitVLendingManager public lendingManager;
    BitVPoolManager public poolManager;
    BitVRWACollateralRegistry public registry;
    StaticPriceOracle public oracle;
    MockERC20 public rwaAsset;
    MockERC20 public debtAsset;
    address public admin;

    address[] public actors;

    /// @notice Ghost tracker: last collateral cap this handler itself
    /// set via its own role-holding action.
    uint256 public ghostLastCap;

    constructor(
        BitVLendingManager lendingManager_,
        BitVPoolManager poolManager_,
        BitVRWACollateralRegistry registry_,
        StaticPriceOracle oracle_,
        MockERC20 rwaAsset_,
        MockERC20 debtAsset_,
        address admin_,
        address[] memory actors_
    ) {
        lendingManager = lendingManager_;
        poolManager = poolManager_;
        registry = registry_;
        oracle = oracle_;
        rwaAsset = rwaAsset_;
        debtAsset = debtAsset_;
        admin = admin_;
        actors = actors_;
        ghostLastCap = registry.getCollateralCap(address(rwaAsset_));
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function depositCollateral(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 boundedAmount = bound(amount, 1, 100e18);

        VM.startPrank(actor);
        rwaAsset.mint(actor, boundedAmount);
        rwaAsset.approve(address(lendingManager), boundedAmount);
        try lendingManager.depositCollateral(address(rwaAsset), boundedAmount) {} catch {}
        VM.stopPrank();
    }

    function withdrawCollateral(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 balance = lendingManager.getCollateralBalance(actor, address(rwaAsset));
        if (balance == 0) return;
        uint256 boundedAmount = bound(amount, 1, balance);

        VM.startPrank(actor);
        try lendingManager.withdrawCollateral(address(rwaAsset), boundedAmount) {} catch {}
        VM.stopPrank();
    }

    function borrow(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 boundedAmount = bound(amount, 1, 10_000e18);

        VM.startPrank(actor);
        try lendingManager.borrow(address(debtAsset), boundedAmount) {} catch {}
        VM.stopPrank();
    }

    function repay(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 debt = lendingManager.getCurrentDebt(actor, address(debtAsset));
        if (debt == 0) return;
        uint256 boundedAmount = bound(amount, 1, debt);

        VM.startPrank(actor);
        debtAsset.mint(actor, boundedAmount);
        debtAsset.approve(address(lendingManager), boundedAmount);
        try lendingManager.repay(address(debtAsset), boundedAmount) {} catch {}
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

    function movePrice(uint96 newPrice) external {
        uint256 bounded = bound(newPrice, 1, 5_000e18);
        VM.prank(admin);
        oracle.setPrice(address(rwaAsset), bounded, 18);
    }

    function markPriceFresh() external {
        VM.prank(admin);
        try registry.markPriceFresh(address(rwaAsset)) {} catch {}
    }

    function warpForward(uint32 secondsElapsed) external {
        uint256 bounded = bound(secondsElapsed, 0, 3 days);
        VM.warp(block.timestamp + bounded);
    }

    /// @notice The handler's only path that legitimately changes the
    /// collateral cap — the invariant suite checks nothing else can.
    function setCollateralCap(uint96 cap) external {
        uint256 bounded = bound(cap, 0, 10_000e18);
        VM.prank(admin);
        registry.setCollateralCap(address(rwaAsset), bounded);
        ghostLastCap = bounded;
    }

    /// @notice Fuzzed attempt at unauthorized registry mutation, from a
    /// non-role-holding actor — must always revert.
    function attemptUnauthorizedRegistration(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        VM.prank(actor);
        try registry.setCollateralCap(address(rwaAsset), 0) {
            revert("unauthorized setCollateralCap unexpectedly succeeded");
        } catch {}
    }

    function liquidate(uint256 liquidatorSeed, uint256 targetSeed, uint96 repayAmount) external {
        address liquidatorActor = _actor(liquidatorSeed);
        address target = _actor(targetSeed);
        uint256 debt = lendingManager.getCurrentDebt(target, address(debtAsset));
        if (debt == 0) return;
        uint256 boundedAmount = bound(repayAmount, 1, debt);

        VM.startPrank(liquidatorActor);
        debtAsset.mint(liquidatorActor, boundedAmount);
        debtAsset.approve(address(lendingManager), boundedAmount);
        try lendingManager.liquidate(target, address(debtAsset), address(rwaAsset), boundedAmount) {} catch {}
        VM.stopPrank();
    }
}
