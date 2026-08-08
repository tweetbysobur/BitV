// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdUtils} from "forge-std/StdUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {BitVPoolManager} from "../../src/core/BitVPoolManager.sol";
import {BitVLendingManager} from "../../src/core/BitVLendingManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Bounded-random-action handler for BitV's pool/lending
/// invariant tests. Every action is wrapped so a revert (e.g. exceeding
/// LTV, withdrawing more than available) is swallowed rather than
/// failing the fuzz run — invariant testing checks that state stays
/// consistent across whatever sequence of *valid or attempted* actions
/// occurs, not that every attempted action succeeds.
contract Handler is StdUtils {
    Vm private constant VM = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    BitVPoolManager public poolManager;
    BitVLendingManager public lendingManager;
    MockERC20 public debtAsset;
    MockERC20 public collateralAsset;

    address[] public actors;

    constructor(
        BitVPoolManager poolManager_,
        BitVLendingManager lendingManager_,
        MockERC20 debtAsset_,
        MockERC20 collateralAsset_,
        address[] memory actors_
    ) {
        poolManager = poolManager_;
        lendingManager = lendingManager_;
        debtAsset = debtAsset_;
        collateralAsset = collateralAsset_;
        actors = actors_;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function deposit(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 boundedAmount = bound(amount, 1, 1_000_000e18);

        VM.startPrank(actor);
        debtAsset.mint(actor, boundedAmount);
        debtAsset.approve(address(poolManager), boundedAmount);
        try poolManager.deposit(address(debtAsset), boundedAmount) {} catch {}
        VM.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 balance = poolManager.balanceOf(address(debtAsset), actor);
        if (balance == 0) return;
        uint256 boundedAmount = bound(amount, 1, balance);

        VM.startPrank(actor);
        try poolManager.withdraw(address(debtAsset), boundedAmount) {} catch {}
        VM.stopPrank();
    }

    function depositCollateral(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 boundedAmount = bound(amount, 1, 1_000e18);

        VM.startPrank(actor);
        collateralAsset.mint(actor, boundedAmount);
        collateralAsset.approve(address(lendingManager), boundedAmount);
        try lendingManager.depositCollateral(address(collateralAsset), boundedAmount) {} catch {}
        VM.stopPrank();
    }

    function borrow(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 boundedAmount = bound(amount, 1, 1_000_000e18);

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
}
