// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IIdentityOracle } from "../interfaces/IIdentityOracle.sol";
import { ICleanverseAPass } from "../interfaces/external/ICleanverseAPass.sol";
import { ICleanverseValidator } from "../interfaces/external/ICleanverseValidator.sol";
import { ICleanverseAccessCore } from "../interfaces/external/ICleanverseAccessCore.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title CleanverseIdentityAdapter
/// @notice The ONLY contract in the protocol that talks to Cleanverse's
///         on-chain contracts directly. Implements the stable
///         `IIdentityOracle` interface every manager depends on. See the
///         provenance notes in `interfaces/external/ICleanverseAPass.sol` and
///         `ICleanverseValidator.sol` — the exact field/function shapes here
///         must be confirmed against Cleanverse's deployed ABI before
///         mainnet; this adapter is the single point of change if they
///         differ, by design.
contract CleanverseIdentityAdapter is AccessControl, IIdentityOracle {
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    ICleanverseAPass public aPass;
    ICleanverseValidator public validator;

    event APassSet(address indexed previous, address indexed current);
    event ValidatorSet(address indexed previous, address indexed current);

    constructor(address admin, address aPass_, address validator_) {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIG_ROLE, admin);

        if (aPass_ != address(0)) aPass = ICleanverseAPass(aPass_);
        if (validator_ != address(0)) validator = ICleanverseValidator(validator_);
    }

    // ── IIdentityOracle ──────────────────────────────────────────────────

    function statusOf(address account) public view returns (IdentityStatus) {
        if (address(aPass) == address(0)) return IdentityStatus.Unregistered;

        ICleanverseAPass.APassRecord memory record = aPass.getAPass(account);

        if (record.status == 0) return IdentityStatus.Unregistered;
        if (record.status == 2) return IdentityStatus.Frozen;

        // status == 1 (active per Cleanverse) still requires an expiry check
        // — see docs/cleanverse-integration.md's identity-state table: the
        // REST API's binary `status` cannot express "was active, has since
        // lapsed" on its own, so BitV derives `Expired` the same way the
        // frontend does in `deriveVerificationState`.
        if (record.expirationTime != 0 && block.timestamp >= record.expirationTime) {
            return IdentityStatus.Expired;
        }

        return IdentityStatus.Active;
    }

    function tierOf(address account) external view returns (uint16) {
        if (address(aPass) == address(0)) return 0;
        return aPass.getAPass(account).tier;
    }

    function isEligibleForPool(address pool, address account) external view returns (bool) {
        if (address(validator) == address(0)) {
            revert Errors.ValidatorPoolNotConfigured(pool);
        }
        if (!validator.isRegistered(pool)) {
            revert Errors.ValidatorPoolNotConfigured(pool);
        }
        if (validator.isPaused(pool)) {
            revert Errors.ValidatorPoolPaused(pool);
        }

        return validator.verify(pool, account);
    }

    function checkAssetEligibility(address accessCore, address account)
        external
        view
        returns (AssetEligibility)
    {
        if (accessCore == address(0)) return AssetEligibility.Unavailable;

        // Pre-flight check only — mirrors `verify_apass`'s `data.code`.
        // A revert from the external call (unreachable contract, unexpected
        // interface) is treated as `Unavailable` by the caller wrapping this
        // in a try/catch (see `AccessManager._safeCheckAssetEligibility`)
        // rather than propagating — a compliance check that reverts the
        // caller's entire transaction on a transient RPC/contract issue is a
        // worse failure mode than a clearly-labelled "unavailable" the UI can
        // retry.
        uint8 code = ICleanverseAccessCore(accessCore).checkEligibility(account);

        if (code == 1) return AssetEligibility.AssetNotSupported;
        if (code == 2) return AssetEligibility.NoIdentity;
        if (code == 3) return AssetEligibility.IdentityNotTransferable;
        if (code == 4) return AssetEligibility.Eligible;
        return AssetEligibility.Unavailable; // undocumented code — fail closed
    }

    // ── Configuration ────────────────────────────────────────────────────

    function setAPass(address aPass_) external onlyRole(CONFIG_ROLE) {
        emit APassSet(address(aPass), aPass_);
        aPass = ICleanverseAPass(aPass_);
    }

    function setValidator(address validator_) external onlyRole(CONFIG_ROLE) {
        emit ValidatorSet(address(validator), validator_);
        validator = ICleanverseValidator(validator_);
    }
}
