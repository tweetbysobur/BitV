// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IProtocolRegistry } from "../interfaces/IProtocolRegistry.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title ProtocolRegistry
/// @notice Deployed once, first, before every other BitV contract. See
///         `IProtocolRegistry` for why this exists.
/// @dev Deliberately NOT upgradeable via proxy, unlike the manager modules
///      (`BaseModule`). A registry swap is not an in-place upgrade — it's a
///      full re-pointing of every module's peer resolution — so there is no
///      "preserve existing storage" case to design for the way there is for
///      PoolManager's balances or LendingManager's debt positions. A plain
///      `AccessControl`-gated contract is simpler, cheaper, and has a smaller
///      audit surface than a proxy for a contract that is a handful of
///      mappings and event emissions.
contract ProtocolRegistry is AccessControl, IProtocolRegistry {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    mapping(bytes32 key => address value) private _addresses;

    constructor(address admin) {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    // ── Canonical keys ───────────────────────────────────────────────────
    // solhint-disable func-name-mixedcase
    function ACCESS_MANAGER() external pure returns (bytes32) {
        return keccak256("bitv.access_manager");
    }

    function POOL_MANAGER() external pure returns (bytes32) {
        return keccak256("bitv.pool_manager");
    }

    function LENDING_MANAGER() external pure returns (bytes32) {
        return keccak256("bitv.lending_manager");
    }

    function VAULT_MANAGER() external pure returns (bytes32) {
        return keccak256("bitv.vault_manager");
    }

    function BITSCORE_MANAGER() external pure returns (bytes32) {
        return keccak256("bitv.bitscore_manager");
    }

    function TREASURY() external pure returns (bytes32) {
        return keccak256("bitv.treasury");
    }

    function IDENTITY_ORACLE() external pure returns (bytes32) {
        return keccak256("bitv.identity_oracle");
    }

    function PRICE_ORACLE() external pure returns (bytes32) {
        return keccak256("bitv.price_oracle");
    }
    // solhint-enable func-name-mixedcase

    // ── Read / write ─────────────────────────────────────────────────────

    function setAddress(bytes32 key, address value) external onlyRole(REGISTRAR_ROLE) {
        if (key == bytes32(0)) revert Errors.InvalidRegistryKey(key);
        address previous = _addresses[key];
        _addresses[key] = value;
        emit AddressSet(key, previous, value);
    }

    function getAddress(bytes32 key) external view returns (address) {
        return _addresses[key];
    }

    function requireAddress(bytes32 key) external view returns (address value) {
        value = _addresses[key];
        if (value == address(0)) revert Errors.ZeroAddress();
    }
}
