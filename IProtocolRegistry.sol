// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IProtocolRegistry
/// @notice Single source of truth for the current address of every protocol
///         module. Every manager resolves its peers (AccessManager,
///         PoolManager, BitScoreManager, Treasury, the identity oracle)
///         through this registry by a stable `bytes32` key rather than
///         holding a hardcoded/constructor-set peer address.
/// @dev This is what makes the suite upgrade-friendly without a full proxy
///      pattern on every contract: if LendingManager is redeployed (e.g. a
///      new liquidation engine version), governance updates ONE entry here,
///      and PoolManager / VaultManager / AccessManager — none of which store
///      LendingManager's address directly — pick up the new address on their
///      next call. Contracts that DO need proxy-upgradeability for in-place
///      state preservation (see `BaseModule.sol`) still register themselves
///      here under a stable key, so the registry and the UUPS proxy pattern
///      compose rather than compete.
interface IProtocolRegistry {
    event AddressSet(bytes32 indexed key, address indexed previous, address indexed current);

    /// @notice Canonical keys. Declared as functions (not a shared constants
    ///         file every module would need to import) so the registry
    ///         itself is the single definition site.
    function ACCESS_MANAGER() external pure returns (bytes32);
    function POOL_MANAGER() external pure returns (bytes32);
    function LENDING_MANAGER() external pure returns (bytes32);
    function VAULT_MANAGER() external pure returns (bytes32);
    function BITSCORE_MANAGER() external pure returns (bytes32);
    function TREASURY() external pure returns (bytes32);
    function IDENTITY_ORACLE() external pure returns (bytes32);
    function PRICE_ORACLE() external pure returns (bytes32);

    function setAddress(bytes32 key, address value) external;
    function getAddress(bytes32 key) external view returns (address);

    /// @notice Reverts with `Errors.ZeroAddress` if unset, rather than
    ///         returning `address(0)` — every call site that needs a peer
    ///         module resolved wants "configured or revert", never a silent
    ///         zero address it would have to remember to check itself.
    function requireAddress(bytes32 key) external view returns (address);
}
