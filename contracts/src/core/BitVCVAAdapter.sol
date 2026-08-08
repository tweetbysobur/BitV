// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BitVRoleConsumer} from "../access/BitVRoleConsumer.sol";
import {IBitVCVAAdapter} from "../interfaces/IBitVCVAAdapter.sol";
import {IATokenPolicy} from "../interfaces/external/IATokenPolicy.sol";
import {CVAErrors} from "../libraries/CVAErrors.sol";

/**
 * @title BitVCVAAdapter
 * @notice Implements docs/cva-integration-specification.md's
 * architecture decision (D): the single BitV component responsible for
 * calling Cleanverse CVA-specific interfaces. Owns exactly one
 * responsibility — tracking, per token, which contract claims to be
 * that token's CVA policy, and whether this adapter has been able to
 * confirm (via the one safely-callable, confirmed probe available,
 * `IATokenPolicy.getRulesV2`) that the contract responds the way a CVA
 * policy contract is expected to.
 *
 * This contract never duplicates Cleanverse's RuleV2/canTransfer policy
 * logic — it only ever calls into the real policy contract (via
 * `staticcall`, read-only) and reports what it observes. It never
 * asserts Cleanverse's own off-chain approval of a token, because no
 * on-chain query for that fact is confirmed to exist (see
 * docs/cva-integration-specification.md §2/§7).
 *
 * `RWA_ADMIN_ROLE` is reused for every administrative function here —
 * no new role was introduced. CVA administration is, in this
 * milestone's scope, an extension of RWA asset administration (the
 * same role that already registers/configures RWA collateral assets in
 * BitVRWACollateralRegistry), not a distinct responsibility that would
 * justify a new role under the "do not introduce unnecessary
 * administrative roles" instruction.
 */
contract BitVCVAAdapter is BitVRoleConsumer, IBitVCVAAdapter {
    mapping(address token => address policyContract) private _policyContract;
    mapping(address token => bool) private _interfaceVerified;

    event PolicyContractSet(address indexed token, address indexed policyContract);
    event InterfaceVerified(address indexed token, address indexed policyContract);
    event InterfaceVerificationCleared(address indexed token);

    constructor(address accessManager) BitVRoleConsumer(accessManager) {}

    /// @notice Configures which contract `token` claims as its CVA
    /// policy. Resets any prior interface-verification result — a
    /// reconfigured policy contract has not yet been (re-)probed, and
    /// must not be trusted until `verifyInterface` succeeds again,
    /// mirroring BitVRWACollateralRegistry.setOracleConfig's identical
    /// "reconfiguration resets attestation" pattern.
    function setPolicyContract(address token, address policyContract)
        external
        onlyRole(ACCESS_MANAGER.RWA_ADMIN_ROLE())
    {
        if (token == address(0)) revert CVAErrors.ZeroAddress();
        _policyContract[token] = policyContract;
        _interfaceVerified[token] = false;
        emit PolicyContractSet(token, policyContract);
        emit InterfaceVerificationCleared(token);
    }

    /// @notice Attempts to confirm `token`'s configured policy contract
    /// responds to `IATokenPolicy.getRulesV2` — the one piece of CVA
    /// policy behavior this adapter can check without guessing an
    /// unconfirmed signature (see IATokenPolicy's NatSpec for the
    /// disclosed inference this relies on). Uses `staticcall`
    /// explicitly: a read-only probe of an otherwise-untrusted
    /// contract, never a state-changing interaction.
    ///
    /// Success proves the policy contract *behaves like* a CVA policy
    /// contract. It does NOT prove Cleanverse approved `token` as a
    /// CVA — see `isRecognizedCVA`'s NatSpec. A malicious contract could
    /// trivially implement `getRulesV2` to return successfully without
    /// being a genuine Cleanverse-approved policy; this is the
    /// documented, inherent limitation of on-chain-only verification
    /// (docs/cva-integration-specification.md §13, "admin-attested CVA
    /// spoofing"), not something this function claims to solve.
    function verifyInterface(address token) external onlyRole(ACCESS_MANAGER.RWA_ADMIN_ROLE()) {
        address policy = _policyContract[token];
        if (policy == address(0)) revert CVAErrors.PolicyContractNotSet(token);

        (bool success, bytes memory returndata) =
            policy.staticcall(abi.encodeWithSelector(IATokenPolicy.getRulesV2.selector, token));
        if (!success || returndata.length == 0) {
            revert CVAErrors.InterfaceVerificationFailed(token, policy);
        }

        _interfaceVerified[token] = true;
        emit InterfaceVerified(token, policy);
    }

    function isRecognizedCVA(address token) public view returns (bool) {
        return _policyContract[token] != address(0) && _interfaceVerified[token];
    }

    function policyOf(address token) external view returns (address) {
        return _policyContract[token];
    }

    /// @notice Always reverts — see IBitVCVAAdapter's NatSpec and
    /// CVAErrors.TransferValidationUnconfirmed's NatSpec. This function
    /// exists to satisfy the interface boundary Build 07.1 requires
    /// ("route CVA transfer validation through BitVCVAAdapter... if the
    /// return behavior is still unconfirmed, implement the adapter
    /// boundary without pretending the transfer validation is fully
    /// executable") without fabricating Cleanverse's `canTransfer`
    /// return type, visibility, or rejection mechanism, none of which
    /// are confirmed by the approved specification.
    function previewTransfer(address, address, address, uint256) external pure returns (bool) {
        revert CVAErrors.TransferValidationUnconfirmed();
    }

    /// @notice Identical to `isRecognizedCVA` in this implementation —
    /// see IBitVCVAAdapter's NatSpec for why the two are kept as
    /// separate interface functions regardless.
    function isCurrentlyUsable(address token) external view returns (bool) {
        return isRecognizedCVA(token);
    }
}
