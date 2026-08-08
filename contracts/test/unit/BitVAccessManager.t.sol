// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BitVAccessManager} from "../../src/core/BitVAccessManager.sol";
import {ProtocolErrors} from "../../src/libraries/ProtocolErrors.sol";

contract BitVAccessManagerTest is Test {
    address internal admin = makeAddr("admin");

    function test_Constructor_GrantsEveryRoleToAdmin() public {
        BitVAccessManager accessManager = new BitVAccessManager(admin);

        assertTrue(accessManager.hasRole(accessManager.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(accessManager.hasRole(accessManager.PROTOCOL_ADMIN_ROLE(), admin));
        assertTrue(accessManager.hasRole(accessManager.RISK_MANAGER_ROLE(), admin));
        assertTrue(accessManager.hasRole(accessManager.POOL_MANAGER_ROLE(), admin));
        assertTrue(accessManager.hasRole(accessManager.PAUSER_ROLE(), admin));
        assertTrue(accessManager.hasRole(accessManager.VAULT_MANAGER_ROLE(), admin));
        assertTrue(accessManager.hasRole(accessManager.STRATEGY_MANAGER_ROLE(), admin));
        assertTrue(accessManager.hasRole(accessManager.RWA_ADMIN_ROLE(), admin));
        assertTrue(accessManager.hasRole(accessManager.ORACLE_MANAGER_ROLE(), admin));
    }

    /// @notice Regression test for Build 10 Phase 1: deploying with
    /// `admin == address(0)` would otherwise grant every role to the
    /// zero address, permanently bricking administration of this
    /// contract and everything that depends on it (no address can ever
    /// be `msg.sender == address(0)`).
    function test_Constructor_ZeroAdmin_Reverts() public {
        vm.expectRevert(ProtocolErrors.ZeroAddress.selector);
        new BitVAccessManager(address(0));
    }
}
