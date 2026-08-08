# BitV CVA Adapter + Registry Extension Implementation (Build 07.1)

Implements `docs/cva-integration-specification.md`'s architecture
decision (D) exactly — no redesign of the lending, liquidation, vault,
BitScore, or compliance architecture. This document records what was
actually built, exactly what Cleanverse behavior it does and does not
call, and what remains a known limitation.

## Adapter architecture

New: `contracts/src/core/BitVCVAAdapter.sol`, implementing
`IBitVCVAAdapter` (`contracts/src/interfaces/IBitVCVAAdapter.sol`).
`BitVRoleConsumer`-based, reusing `RWA_ADMIN_ROLE` for every
administrative function — **no new role was introduced** (see "Access
control" below for why).

```
BitVRWACollateralRegistry
  │  cvaAdapter.isRecognizedCVA(asset) — the only call the registry
  │  ever makes toward CVA-specific logic
  ▼
BitVCVAAdapter
  │  policy.staticcall(getRulesV2(token)) — the only call this codebase
  │  ever makes toward an actual Cleanverse CVA policy contract
  ▼
Cleanverse CVA policy contract (IATokenPolicy, off-chain-approved,
  outside BitV's trust boundary)
```

**The adapter is the only BitV component that calls Cleanverse
CVA-specific interfaces** — no other contract (the registry,
`BitVLendingManager`, `BitVYieldVault`) imports or references
`IATokenPolicy` at all. This was verified by construction: `grep -r
IATokenPolicy contracts/src/` returns only the interface's own
declaration file and `BitVCVAAdapter.sol`.

## CVA status model

Per the approved specification's two-stage model, implemented in
`BitVRWACollateralRegistry.AssetConfig`:

```solidity
struct AssetConfig {
    // ... existing fields (status, underlyingPool, ltvBps, ...) ...
    bool adminAttestedCVA; // RWA_ADMIN_ROLE's claim, stored here
}
```

- **`isCVAAdminAttested(asset)`** — reads `AssetConfig.adminAttestedCVA`
  directly. Set via `setCVAAttestation(asset, bool)`
  (`RWA_ADMIN_ROLE`-gated). This is a claim only, stored entirely
  within the registry, independent of anything the adapter reports.
- **`isCVAInterfaceVerified(asset)`** — a **live** call to
  `cvaAdapter.isRecognizedCVA(asset)`, `try`/`catch`-wrapped, never
  cached in the registry's own storage. Deliberately not cached: caching
  would create a second source of truth that could drift from the
  adapter's own state (e.g. if the adapter's policy contract for that
  token is later reconfigured, `BitVCVAAdapter.setPolicyContract`
  already resets its own verification flag — a registry-side cache
  would need its own reset logic duplicating that, for no benefit).
  Fails safe to `false` if no adapter is wired (`address(0)`) or the
  adapter call reverts for any reason.
- **`isCVAFullyRecognized(asset)`** — `true` only when **both** flags
  are `true`. Per the specification and this milestone's task
  explicitly: **this is not, and is never presented as, equivalent to
  Cleanverse's own approval of the asset as a CVA.** It means "an admin
  claims this is a CVA, and a contract this asset points to responds
  the way a CVA policy contract is expected to" — nothing more. No
  function, comment, or event in this codebase claims otherwise.

**The two states remain fully independent**, verified directly by
`test_AdminAttestationWithoutInterfaceVerification_NotFullyRecognized`
and `test_InterfaceVerificationWithoutAdminAttestation_NotFullyRecognized`
— setting one never sets or clears the other.

## Cleanverse interfaces used

Exactly one Cleanverse-defined function is ever called by this
codebase: `IATokenPolicy.getRulesV2(address token) external view
returns (RuleV2[] memory)`, via `staticcall` inside
`BitVCVAAdapter.verifyInterface`.

**`canTransfer` is never called anywhere in this codebase.**
`IBitVCVAAdapter.previewTransfer` exists as the interface boundary the
task requires but its implementation (`BitVCVAAdapter.previewTransfer`)
unconditionally reverts `CVAErrors.TransferValidationUnconfirmed()` —
per the task's explicit instruction: "If the return behavior is still
unconfirmed, implement the adapter boundary without pretending the
transfer validation is fully executable." Verified directly by
`test_PreviewTransfer_AlwaysReverts`.

**`setRuleV2`/`addRuleV2`/`removeRuleV2`/`*FromToken` are never
called anywhere in this codebase** — these are the CVA issuer's own
rule-management functions (per `docs/cva-integration-specification.md`
§13's "unauthorized policy changes" analysis); BitV has no reason to
call them and doesn't.

## Confirmed behavior

- `IATokenPolicy`'s existence, its role as the CVA transfer-gating
  policy interface, and its sharing the identical `RuleV2` struct with
  the CVI validator — confirmed, `docs/cleanverse-integration.md` §3.
- `canTransfer(token, from, to, amount)`'s function name and argument
  list — confirmed.
- `getRulesV2`/`setRuleV2`/etc.'s function *names* — confirmed.

## Unconfirmed behavior (deliberately not implemented)

- `canTransfer`'s return type, visibility, mutability, and rejection
  mechanism (revert vs. boolean) — **not implemented**; see
  `IATokenPolicy.sol`'s NatSpec for the full disclosure.
- `getRulesV2`'s exact signature for the CVA policy interface
  specifically — the signature this adapter actually calls
  (`address token) external view returns (RuleV2[] memory)`) is a
  **disclosed inference by analogy** to
  `IAPassComplianceValidator.getRulesV2`'s fully-confirmed identical
  shape, motivated by the CVA guide's statement that the two interfaces
  share the same `RuleV2` struct. This is flagged explicitly in
  `IATokenPolicy.sol`'s NatSpec and here — it is the one piece of
  "reasonable inference" this implementation makes, and it is used only
  for a read-only interface-shape probe, never for anything
  security-critical (transfer authorization, compliance decisions).
- Any on-chain query for "is this token Cleanverse-approved as a CVA"
  — **does not exist** per the approved specification's research;
  `verifyInterface`'s success does not and cannot answer this question.
- CVA freeze/revoke mechanism — **unconfirmed to exist at all**; not
  implemented. If Cleanverse later confirms one, `isCurrentlyUsable`'s
  interface slot (already distinct from `isRecognizedCVA`, even though
  currently implemented identically) is where it would be wired in
  without an interface break.

## CVI relationship

Unchanged, verified directly. Every protected `BitVLendingManager`
action still calls `BitVComplianceGuard._requireCompliance(msg.sender)`
exactly as before this milestone — CVA status (attested, verified, or
fully recognized) has no code path that touches this check.
`test_CVIRejection_TakesPrecedenceOverFullCVARecognition` and
`invariant_CVICannotBeBypassedThroughCVA` confirm a never-compliant
wallet is rejected regardless of how "fully recognized" the CVA status
on the asset it's trying to deposit is.

## RWA relationship

**CVA status changes nothing about `isEligibleForNewActivity`** —
verified directly by `test_CVAStatus_DoesNotAffectEligibility`,
`test_FrozenCVA_StillIneligibleDespiteFullRecognition`,
`test_DelistedCVA_StillIneligibleDespiteFullRecognition`,
`test_OracleFailureCombinedWithCVAStatus_StillIneligible`, and the
`invariant_RWAEligibilityCannotBeBypassedThroughCVA` fuzzed invariant.
A CVA asset must still satisfy every existing RWA requirement
(registered, `Active` status, oracle available and fresh, valid
collateral configuration, collateral cap, allowed debt assets, CVI
compliance) — none of that logic was touched. CVA status is purely
additive metadata, queryable via `isCVAAdminAttested`/
`isCVAInterfaceVerified`/`isCVAFullyRecognized`, consulted by nothing
in the existing eligibility/borrowing/liquidation code paths.

**BitScore cannot override CVA restrictions** — trivially true because
CVA status doesn't restrict anything BitScore could override in the
first place in this milestone; `test_BitScoreCannotOverrideCVARestrictions`
confirms a frozen-yet-fully-CVA-recognized asset still contributes
exactly zero available borrow value regardless of the borrower's
BitScore tier, since BitScore's adjustment operates on a base figure
that's already zero.

## Failure handling

| Condition | Behavior |
|---|---|
| Adapter unset (`address(0)`) | `isCVAInterfaceVerified` returns `false` for every asset; `isEligibleForNewActivity` (the actual eligibility gate) is entirely unaffected |
| Adapter call reverts | Caught by the registry's `try`/`catch`, resolved to `false` — never propagates, never defaults to `true` |
| Adapter points at a non-conforming contract | Same as above — `test_AdapterFailure_NeverCreatesAdditionalPermissions` and `invariant_AdapterFailureCannotCreateAdditionalPermissions` confirm both the CVA queries and the actual eligibility gate are unaffected |
| Policy contract unset for a token | `verifyInterface` reverts `PolicyContractNotSet` — no ambiguous partial state |
| Policy contract reverts on the probe call | `verifyInterface` reverts `InterfaceVerificationFailed` — `_interfaceVerified` stays `false` |
| Policy contract has no matching function (empty/non-conforming) | Same as above — the `staticcall` returns `success = false`, caught identically |
| Reconfiguring a token's policy contract | Immediately resets `_interfaceVerified` to `false` — a stale verification against a since-changed policy contract can never survive reconfiguration |

**No failure path in this implementation increases borrowing capacity,
bypasses CVI, bypasses RWA registration, bypasses oracle requirements,
bypasses LTV limits, bypasses BitScore limits, or marks an asset as
officially Cleanverse-verified** — verified by the full test suite and
all seven fuzzed invariants (see below). **The protocol is not
crippled if the adapter is unavailable**: every non-CVA-attested asset
(the entire pre-existing RWA test suite, 48 tests) is completely
unaffected, since `isCVAInterfaceVerified`'s `address(0)`/revert
fallback only ever affects the CVA-status *query* — it does not gate
`isEligibleForNewActivity`, deposits, borrowing, or any other existing
function.

## Security assumptions

- `verifyInterface` uses `staticcall` specifically — a read-only probe
  that cannot itself perform any state-changing reentrant call back
  into BitV's contracts, regardless of what a malicious policy contract
  attempts. `test_Reentrancy_PolicyContractCannotReenterViaStaticcall`
  documents this property directly.
- **Admin-attested CVA spoofing remains structurally possible and is
  not solved by this implementation** — a malicious or careless
  `RWA_ADMIN_ROLE` could still set `adminAttestedCVA = true` on an
  arbitrary token, and any contract (including one the admin controls)
  can trivially implement `getRulesV2` to make `verifyInterface`
  succeed. `test_MaliciousCVAContract_InterfaceVerificationAloneInsufficientForFullRecognition`
  demonstrates this directly rather than hiding it — this is exactly
  the documented, inherent limitation from
  `docs/cva-integration-specification.md` §13, not a bug introduced
  here.
- No new reentrancy surface beyond the `staticcall` above — the
  registry's `isCVAInterfaceVerified`/`isCVAFullyRecognized` are plain
  `view` functions with no state-changing external calls.
- `_validateAgainstPool` (pre-existing, unmodified) continues to
  guarantee RWA risk parameters never exceed the underlying pool's own
  hard configuration — untouched by this milestone.

## Known limitations

- **No on-chain proof of genuine Cleanverse approval exists or is
  claimed** — `isCVAFullyRecognized` combines an admin claim with an
  interface-shape probe, neither of which can verify Cleanverse's own
  off-chain decision. This is the specification's central, disclosed
  limitation, not something this implementation resolves.
- **`getRulesV2`'s exact signature for the CVA policy interface is an
  inference, not an independently confirmed fact** — see "Unconfirmed
  behavior" above. If Cleanverse's real CVA policy contracts use a
  different signature, `verifyInterface` would fail against a genuine
  CVA (a false negative, the safe failure direction) rather than
  silently misbehaving.
- **`canTransfer`/transfer-time validation is not implemented at all**
  — `previewTransfer` is a boundary function only, always reverting.
  No BitV code path (deposit, borrow, repay, withdraw, liquidate) calls
  it or depends on it; CVA-recognized assets still move via ordinary
  `SafeERC20` transfers exactly as any other RWA asset does, and if the
  underlying token happens to be a genuine, Cleanverse-gated CVA, its
  own transfer hook (outside BitV's code entirely) still applies
  automatically — this implementation simply doesn't add any
  BitV-side preview/validation on top of that.
- **CVA freeze/revoke handling is unimplemented** because the
  underlying Cleanverse mechanism is unconfirmed to exist — `Frozen`/
  `Delisted` remain purely `BitVRWACollateralRegistry`'s own,
  pre-existing status concepts, unrelated to any Cleanverse-side CVA
  state.
- **No CVA issuance, minting, redemption, settlement, recovery, or
  cross-chain settlement is implemented** — per instruction, out of
  scope for this milestone.

## Tests created

- `contracts/test/mocks/MockCVAPolicy.sol` — `MockCVAPolicy` (responds
  successfully to `getRulesV2`), `MockRevertingCVAPolicy` (reverts on
  every call), `MockEmptyContract` (no matching function selector).
- `contracts/test/unit/BitVCVAAdapter.t.sol` — 30 scenario tests across
  policy configuration, interface verification, transfer-validation
  boundary, registry CVA-status model, CVA-never-bypasses-existing-
  controls, CVI+CVA interaction, and security categories.
- `contracts/test/invariant/CVAHandler.sol` +
  `BitVCVAInvariant.t.sol` — 7 fuzzed invariants (256 runs / 128,000
  calls each) covering all six properties the task specifies, plus a
  seventh confirming attestation only ever changes via the handler's
  authorized path.
- `contracts/test/BaseRWATest.sol` extended to deploy and wire a
  `BitVCVAAdapter` alongside the existing registry fixture (harmless
  for every pre-existing RWA test — no asset is CVA-attested or
  policy-configured by default).
