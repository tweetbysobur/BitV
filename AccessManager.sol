// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseModule } from "./BaseModule.sol";
import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IAccessManager } from "../interfaces/IAccessManager.sol";
import { IIdentityOracle } from "../interfaces/IIdentityOracle.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title AccessManager
/// @notice Protocol-wide capability gate. Every manager contract calls
///         `requireCapability` before performing a verification-gated
///         action; this is where "is this account allowed to do X" is
///         answered once, using `IIdentityOracle` (the Cleanverse adapter),
///         rather than each manager re-deriving eligibility from raw A-Pass
///         and Validator-pool data independently.
/// @custom:storage-location erc7201:bitv.storage.AccessManager
contract AccessManager is BaseModule, IAccessManager {
    struct AccessManagerStorage {
        mapping(Capability => address) capabilityValidatorPool;
    }

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("bitv.storage.AccessManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0xcf08b221a479a77152934bd9f36571c4652a124c6af33aaa459dc31e1f5f5100;

    function _s() private pure returns (AccessManagerStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address registry_, address admin) external initializer {
        __BaseModule_init(registry_, admin);
    }

    // ── Capability checks ────────────────────────────────────────────────

    function requireCapability(Capability capability, address account) external view {
        address pool = _s().capabilityValidatorPool[capability];

        // No Validator pool bound to this capability = ungated by identity
        // (e.g. before Cleanverse registration is complete, or for a
        // capability governance has deliberately opened). This is an
        // explicit governance choice via `setCapabilityRequirement`, not a
        // default — every capability starts with no pool bound, which is
        // itself the intended "not yet gated" state during rollout.
        if (pool == address(0)) return;

        IIdentityOracle oracle = IIdentityOracle(registry().requireAddress(registry().IDENTITY_ORACLE()));

        IIdentityOracle.IdentityStatus status = oracle.statusOf(account);
        if (status == IIdentityOracle.IdentityStatus.Unregistered) {
            revert Errors.IdentityNotRegistered(account);
        }
        if (status == IIdentityOracle.IdentityStatus.Frozen) {
            revert Errors.IdentityIneligible(account, uint8(status));
        }
        if (status == IIdentityOracle.IdentityStatus.Expired) {
            revert Errors.IdentityIneligible(account, uint8(status));
        }

        // Status is Active — evaluate the pool's actual rule set (tier,
        // group, country). `isEligibleForPool` itself reverts with
        // `ValidatorPoolNotConfigured` / `ValidatorPoolPaused` for those
        // distinct conditions, which is exactly the behaviour this function
        // wants to surface unmodified.
        if (!oracle.isEligibleForPool(pool, account)) {
            revert Errors.IdentityIneligible(account, uint8(status));
        }
    }

    function hasCapability(Capability capability, address account) external view returns (bool) {
        address pool = _s().capabilityValidatorPool[capability];
        if (pool == address(0)) return true;

        address oracleAddress = registry().getAddress(registry().IDENTITY_ORACLE());
        if (oracleAddress == address(0)) return false;

        IIdentityOracle oracle = IIdentityOracle(oracleAddress);
        IIdentityOracle.IdentityStatus status = oracle.statusOf(account);
        if (status != IIdentityOracle.IdentityStatus.Active) return false;

        // View-only, non-reverting form: a paused/unconfigured pool must
        // read as "not eligible" here rather than reverting, since this
        // function's entire purpose is to be safely callable from other view
        // functions (e.g. rendering eligible-pools lists) that cannot
        // propagate a revert.
        try oracle.isEligibleForPool(pool, account) returns (bool eligible) {
            return eligible;
        } catch {
            return false;
        }
    }

    function setCapabilityRequirement(Capability capability, address validatorPool)
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        _s().capabilityValidatorPool[capability] = validatorPool;
        emit CapabilityRequirementSet(capability, validatorPool);
    }

    function getCapabilityRequirement(Capability capability) external view returns (address) {
        return _s().capabilityValidatorPool[capability];
    }

    // ── Role management ──────────────────────────────────────────────────
    // `grantRole`/`revokeRole`/`hasRole` are already implemented by
    // `AccessControlUpgradeable` (via `BaseModule`); re-declared here only to
    // satisfy `IAccessManager` and emit the interface's named events
    // alongside AccessControl's own, so off-chain indexers watching this
    // contract's ABI see one consistent event shape rather than needing to
    // also know AccessControl's generic `RoleGranted`/`RoleRevoked` layout.

    /// @dev Access control is enforced by `super.grantRole`, which already
    ///      carries `onlyRole(getRoleAdmin(role))` — not repeated here to
    ///      avoid evaluating the same check twice on every call.
    function grantRole(bytes32 role, address account)
        public
        override(AccessControlUpgradeable, IAccessManager)
    {
        super.grantRole(role, account);
        emit RoleGranted(role, account, msg.sender);
    }

    function revokeRole(bytes32 role, address account)
        public
        override(AccessControlUpgradeable, IAccessManager)
    {
        super.revokeRole(role, account);
        emit RoleRevoked(role, account, msg.sender);
    }

    function hasRole(bytes32 role, address account)
        public
        view
        override(AccessControlUpgradeable, IAccessManager)
        returns (bool)
    {
        return super.hasRole(role, account);
    }
}
