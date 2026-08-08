// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IIdentityOracle
/// @notice The ONLY Cleanverse-facing interface any BitV protocol contract
///         (AccessManager, LendingManager, PoolManager, VaultManager)
///         depends on directly.
/// @dev This is the seam the whole integration is designed around: every
///      other contract in the protocol imports this interface and never
///      touches `ICleanverseAPass` / `ICleanverseValidator` /
///      `ICleanverseAccessCore` directly. `CleanverseIdentityAdapter`
///      (`src/core/CleanverseIdentityAdapter.sol`) is the single
///      implementation, translating BitV's stable questions ("is this
///      account eligible for this pool?") into Cleanverse's actual on-chain
///      calls. If Cleanverse's ABI changes, or a second identity provider is
///      ever added, exactly one contract changes — every manager contract
///      and every existing deployment's storage layout is untouched.
interface IIdentityOracle {
    enum IdentityStatus {
        Unregistered, // 0 — no A-Pass record
        Active, // 1
        Frozen, // 2 — Cleanverse compliance hold, no self-service remedy
        Expired // 3 — derived: status was Active but past expirationTime

    }

    /// @notice Asset-eligibility outcome, mirroring `verify_apass`'s
    ///         `data.code` 1-4 mapping documented in
    ///         `ICleanverseAccessCore` / `docs/cleanverse-integration.md`.
    enum AssetEligibility {
        Unavailable, // 0 — could not determine (fail closed)
        AssetNotSupported, // 1
        NoIdentity, // 2
        IdentityNotTransferable, // 3 — expired or frozen
        Eligible // 4

    }

    /// @notice Current identity status for `account`.
    function statusOf(address account) external view returns (IdentityStatus);

    /// @notice Current tier for `account`. Returns 0 if unregistered — callers
    ///         MUST check `statusOf` before treating 0 as a meaningful tier,
    ///         since 0 is also a theoretically valid tier value.
    function tierOf(address account) external view returns (uint16 tier);

    /// @notice Whether `account` currently satisfies `pool`'s Cleanverse
    ///         Validator rule set. Reverts with
    ///         `Errors.ValidatorPoolNotConfigured` if `pool` has no
    ///         registered Validator pool, and with
    ///         `Errors.ValidatorPoolPaused` if the pool is paused — both are
    ///         states in which "no" is not sufficient, callers need to know
    ///         WHY to avoid retrying a request that cannot succeed until an
    ///         operator acts.
    function isEligibleForPool(address pool, address account) external view returns (bool);

    /// @notice Pre-flight check for whether `account` may receive/hold the
    ///         Cleanverse Verified Asset governed by `accessCore`.
    function checkAssetEligibility(address accessCore, address account)
        external
        view
        returns (AssetEligibility);
}
