// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseTest } from "../BaseTest.sol";
import { IBitScoreManager } from "../../src/interfaces/IBitScoreManager.sol";
import { Errors } from "../../src/libraries/Errors.sol";

contract BitScoreManagerTest is BaseTest {
    function test_scoreOf_defaultsToBaseline() public view {
        assertEq(bitScoreManager.scoreOf(alice), 300e18);
    }

    function test_reportEvent_revertsForUnauthorizedReporter() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.Unauthorized.selector, alice));
        bitScoreManager.reportEvent(alice, IBitScoreManager.ScoreEvent.OnTimeRepayment, 1e18);
    }

    function test_reportEvent_increasesScoreOnRepayment() public {
        vm.prank(admin);
        bitScoreManager.setReporterAuthorized(alice, true);

        vm.prank(alice);
        bitScoreManager.reportEvent(bob, IBitScoreManager.ScoreEvent.OnTimeRepayment, 1e18);

        assertEq(bitScoreManager.scoreOf(bob), 300e18 + 15e18);
    }

    function test_reportEvent_liquidationSlashesScoreHeavily() public {
        vm.prank(admin);
        bitScoreManager.setReporterAuthorized(alice, true);

        vm.prank(alice);
        bitScoreManager.reportEvent(bob, IBitScoreManager.ScoreEvent.Liquidated, 1e18);

        assertEq(bitScoreManager.scoreOf(bob), 300e18 - 150e18);
    }

    function test_score_clampsAtZero() public {
        vm.prank(admin);
        bitScoreManager.setReporterAuthorized(alice, true);

        vm.startPrank(alice);
        for (uint256 i = 0; i < 10; i++) {
            bitScoreManager.reportEvent(bob, IBitScoreManager.ScoreEvent.Liquidated, 1e18);
        }
        vm.stopPrank();

        assertEq(bitScoreManager.scoreOf(bob), 0);
    }

    function test_score_clampsAtMax() public {
        vm.prank(admin);
        bitScoreManager.setReporterAuthorized(alice, true);

        vm.startPrank(alice);
        for (uint256 i = 0; i < 200; i++) {
            bitScoreManager.reportEvent(bob, IBitScoreManager.ScoreEvent.OnTimeRepayment, 1e18);
        }
        vm.stopPrank();

        assertEq(bitScoreManager.scoreOf(bob), 1000e18);
    }

    function test_creditLimitUsd_zeroWithoutIdentityTier() public view {
        assertEq(bitScoreManager.creditLimitUsd(alice, 0), 0);
    }

    function test_creditLimitUsd_scalesWithTierAndScore() public view {
        // baseline score (300/1000) at tier 10: $500 ceiling * 30% = $150
        uint256 limit = bitScoreManager.creditLimitUsd(alice, 10);
        assertEq(limit, 150e18);
    }
}
