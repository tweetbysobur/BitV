// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IIdentityOracle } from "../../src/interfaces/IIdentityOracle.sol";

/// @notice Freely-controllable identity oracle for tests. Lets a test set an
///         exact status/tier/pool-eligibility per account without needing a
///         live Cleanverse contract, while still exercising every consumer
///         (AccessManager, PoolManager, LendingManager, VaultManager) against
///         the real `IIdentityOracle` interface they depend on in
///         production.
contract MockIdentityOracle is IIdentityOracle {
    mapping(address => IdentityStatus) public statuses;
    mapping(address => uint16) public tiers;
    mapping(address => mapping(address => bool)) public poolEligibility;
    mapping(address => bool) public poolConfigured;
    mapping(address => bool) public poolPaused;

    function setStatus(address account, IdentityStatus status) external {
        statuses[account] = status;
    }

    function setTier(address account, uint16 tier) external {
        tiers[account] = tier;
    }

    function setPoolEligibility(address pool, address account, bool eligible) external {
        poolConfigured[pool] = true;
        poolEligibility[pool][account] = eligible;
    }

    function statusOf(address account) external view returns (IdentityStatus) {
        return statuses[account];
    }

    function tierOf(address account) external view returns (uint16) {
        return tiers[account];
    }

    function isEligibleForPool(address pool, address account) external view returns (bool) {
        return poolEligibility[pool][account];
    }

    function checkAssetEligibility(address, address) external pure returns (AssetEligibility) {
        return AssetEligibility.Eligible;
    }
}
