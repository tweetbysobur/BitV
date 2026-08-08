// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
// `ReentrancyGuardTransient` is imported from the NON-upgradeable
// `@openzeppelin/contracts` package, not `-upgradeable` — intentional, not a
// mismatch. As of the OpenZeppelin version pinned in `contracts/lib`,
// `ReentrancyGuard`/`ReentrancyGuardTransient` are stateless (the transient
// variant uses EIP-1153 transient storage, cleared automatically at the end
// of every transaction) and are therefore no longer published as separate
// `-upgradeable` variants — OpenZeppelin's own migration guidance is to
// import the plain version directly, which is safe here specifically because
// it holds no persistent storage to collide with a proxy's layout. This also
// happens to be strictly cheaper than the old storage-slot-based guard, which
// on a chain that prices gas by LIMIT rather than usage (see
// `docs/contracts-architecture.md` §Gas model) is a real cost saving, not
// just a style preference.
import {
    ReentrancyGuardTransient
} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import { IProtocolRegistry } from "../interfaces/IProtocolRegistry.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title BaseModule
/// @notice Shared foundation for every upgradeable BitV manager contract
///         (AccessManager, PoolManager, LendingManager, VaultManager,
///         BitScoreManager, Treasury).
/// @dev Why UUPS over Transparent proxies: UUPS puts the upgrade logic in the
///      implementation (this contract), keeping the proxy itself a minimal,
///      cheap-to-deploy delegatecall forwarder — material when the protocol
///      deploys a new market/vault frequently and each could, in principle,
///      sit behind its own proxy. Upgrade authorization is explicit
///      (`_authorizeUpgrade`, gated to `UPGRADER_ROLE`) rather than left to
///      the default admin, so upgrade capability is a role governance can
///      grant/revoke/multisig independently of general protocol admin.
///
///      Storage uses the ERC-7201 namespaced storage pattern (see the NatSpec
///      tag above each storage struct below) specifically because this is a
///      BASE contract multiple managers
///      inherit: a plain sequential storage variable here would consume slot
///      0 of every child's storage layout, and a future BaseModule change
///      (e.g. adding a field) would then shift every child's own storage
///      slots out from under it on upgrade — a namespaced slot computed from
///      a fixed string is immune to that regardless of what the base
///      contract's own layout does over time.
abstract contract BaseModule is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardTransient
{
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    /// @custom:storage-location erc7201:bitv.storage.BaseModule
    struct BaseModuleStorage {
        IProtocolRegistry registry;
    }

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("bitv.storage.BaseModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BASE_MODULE_STORAGE_LOCATION =
        0xbff02208b672f968d6d7bbccb0ce942ab1e7e76984a3b0a7b3f87152ceaa1900;

    function _getBaseModuleStorage() private pure returns (BaseModuleStorage storage $) {
        assembly {
            $.slot := BASE_MODULE_STORAGE_LOCATION
        }
    }

    /// @dev Called by each concrete module's own `initialize(...)`, never
    ///      directly — `onlyInitializing` enforces that ordering at compile
    ///      + call time.
    // solhint-disable-next-line func-name-mixedcase
    function __BaseModule_init(address registry_, address admin) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        // No `ReentrancyGuardTransient` init call: it is stateless (EIP-1153
        // transient storage, cleared automatically at the end of every
        // transaction) rather than storage-backed, so there is nothing to
        // initialize — see the import-site note below for why this is used
        // in place of the removed `ReentrancyGuardUpgradeable`.

        if (registry_ == address(0) || admin == address(0)) revert Errors.ZeroAddress();

        _getBaseModuleStorage().registry = IProtocolRegistry(registry_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(GOVERNANCE_ROLE, admin);
    }

    function registry() public view returns (IProtocolRegistry) {
        return _getBaseModuleStorage().registry;
    }

    /// @notice Emergency stop, callable by `PAUSER_ROLE` — deliberately a
    ///         smaller, faster-to-grant role than `GOVERNANCE_ROLE`, so an
    ///         incident responder does not need full governance rights to
    ///         freeze a module under active exploitation.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(GOVERNANCE_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    /// @dev Storage gap intentionally omitted: the ERC-7201 namespaced
    ///      pattern above makes a traditional `__gap` array unnecessary —
    ///      new state added by this contract or by children in future
    ///      versions is placed in its own namespaced slot, not appended
    ///      sequentially, so there is no fixed-size gap to size correctly in
    ///      advance.
}
