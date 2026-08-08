// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseTest } from "../BaseTest.sol";
import { Errors } from "../../src/libraries/Errors.sol";

contract VaultManagerTest is BaseTest {
    bytes32 internal vaultId;
    address internal strategy = makeAddr("strategy");

    function setUp() public override {
        super.setUp();

        vm.prank(admin);
        (vaultId,) = vaultManager.createVault({
            asset: address(usdc),
            minIdentityTier: 0,
            validatorPool: address(0),
            performanceFeeBps: 1000,
            depositCap: 0,
            withdrawalLockSeconds: 7 days,
            strategyOrRewardsDistributor: strategy
        });
    }

    function test_deposit_mintsSharesAtParForFirstDeposit() public {
        vm.startPrank(alice);
        usdc.approve(address(vaultManager), 10_000e6);
        uint256 shares = vaultManager.deposit(vaultId, 10_000e6);
        vm.stopPrank();

        assertEq(shares, 10_000e6);
        assertEq(vaultManager.sharesOf(vaultId, alice), 10_000e6);
    }

    function test_withdraw_revertsBeforeLockExpires() public {
        vm.startPrank(alice);
        usdc.approve(address(vaultManager), 10_000e6);
        vaultManager.deposit(vaultId, 10_000e6);

        vm.expectRevert();
        vaultManager.withdraw(vaultId, 10_000e6);
        vm.stopPrank();
    }

    function test_withdraw_succeedsAfterLockExpires() public {
        vm.startPrank(alice);
        usdc.approve(address(vaultManager), 10_000e6);
        vaultManager.deposit(vaultId, 10_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(alice);
        uint256 assets = vaultManager.withdraw(vaultId, 10_000e6);
        assertEq(assets, 10_000e6);
    }

    function test_distributeRewards_increasesPricePerShare() public {
        vm.startPrank(alice);
        usdc.approve(address(vaultManager), 100_000e6);
        vaultManager.deposit(vaultId, 100_000e6);
        vm.stopPrank();

        usdc.mint(strategy, 10_000e6);
        vm.startPrank(strategy);
        usdc.approve(address(vaultManager), 10_000e6);
        vaultManager.distributeRewards(vaultId, 10_000e6);
        vm.stopPrank();

        // 10,000 reward - 10% performance fee = 9,000 net to the vault.
        // pricePerShare = totalAssets / totalShares = 109,000 / 100,000.
        uint256 price = vaultManager.pricePerShare(vaultId);
        assertEq(price, 1.09e18);
    }

    function test_distributeRewards_revertsForNonStrategy() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.Unauthorized.selector, alice));
        vaultManager.distributeRewards(vaultId, 1_000e6);
    }

    function test_deposit_revertsBelowMinIdentityTier() public {
        vm.prank(admin);
        (bytes32 gatedVault,) = vaultManager.createVault({
            asset: address(usdc),
            minIdentityTier: 50,
            validatorPool: address(0),
            performanceFeeBps: 0,
            depositCap: 0,
            withdrawalLockSeconds: 0,
            strategyOrRewardsDistributor: strategy
        });

        identityOracle.setTier(alice, 10); // below the required tier 50

        vm.startPrank(alice);
        usdc.approve(address(vaultManager), 1_000e6);
        vm.expectRevert();
        vaultManager.deposit(gatedVault, 1_000e6);
        vm.stopPrank();
    }
}
