# BitV CVA (Cleanverse Verified Asset) Integration Specification (Build 07)

**Status: design specification only. No Solidity has been written or
modified for this milestone.** Every existing contract
(`BitVAccessManager`, `BitVComplianceGuard`, `BitVPoolManager`,
`BitVLendingManager`, `BitVVaultManager`, `BitScoreManager`,
`BitVTreasury`, `BitVRWACollateralRegistry`) is unmodified.

**Source of truth**: the two official Cleanverse PDFs provided directly
to this project in Build 02.1 — "Cleanverse Compliance Protocol (CCP)
Integration Guide (For CVI Compliance Validator) V2" and "Cleanverse
Compliance Protocol (CCP) CVA Integration Guide" — as already
transcribed in `docs/cleanverse-integration.md` and
`docs/cleanverse-integration-todo.md`. This document does not
re-search or re-derive anything from those PDFs beyond what's already
recorded there; it cites that existing transcription throughout rather
than re-paraphrasing from memory, and marks `UNCONFIRMED` exactly what
those documents already mark `UNCONFIRMED`. No new Cleanverse material
was available for this milestone. `docs.cleanverse.com` remains
network-blocked in this environment, unchanged from every prior
milestone's finding.

---

## 1. CVA definition

**What makes an asset a CVA** (CVA guide, per
`docs/cleanverse-integration.md` §3): "CVA is the native compliant
asset standard of the Cleanverse Compliance Protocol (CCP)... issued
directly on Cleanverse by qualified issuers, and every transfer is
gated through CVI compliance verification and the RuleV2 policy
engine." Confirmed.

**How a CVA is registered — two issuance paths, both confirmed:**
- **Method A (API Launch)**: Cleanverse deploys the token contract
  itself from a `POST /api/cooperate/atoken/launch` request.
- **Method B (Custom Contract Template)**: the issuer deploys their own
  ERC-20 (upgradeable or not) implementing `IATokenPolicy`, calling
  `policy.canTransfer(...)` inside `_update`, then registers it via
  `POST /api/cooperate/atoken/register` (owner-signed).

**Who registers it**: the token's issuer (in BitV's context, this would
be whoever issues the RWA-backing token — not BitV itself; BitV is
never described in either guide as a CVA issuer, and this specification
does not propose BitV become one).

**What Cleanverse verifies**: not stated beyond the registration
mechanics themselves (Method A's deployment-on-request, Method B's
owner-signed registration). No "review process" content, approval
criteria, or verification checklist is given in either guide — `UNCONFIRMED`.

**How provenance is established**: not addressed by either guide beyond
"issued directly on Cleanverse by qualified issuers." What makes an
issuer "qualified," and how that's established or verified, is
`UNCONFIRMED`.

**How CVI relates to CVA**: every CVA transfer is gated by CVI
compliance verification (per the definition above) — CVA is built *on
top of* the same identity primitive CVI provides, not a separate
identity system. Confirmed.

**How RuleV2 relates to CVA**: CVA's policy interface
(`IComplianceRule`/`IATokenPolicy`) uses the *same* `RuleV2` struct as
the CVI validator (identical fields), but its own function names
(`canTransfer`, `setRuleV2`/`addRuleV2`/`removeRuleV2`, etc. — full
list in §3 below). Confirmed, `docs/cleanverse-integration.md` §3/§7.

**Whether CVA status can change**: not addressed by either guide.
Neither document describes a CVA being frozen, revoked, suspended, or
otherwise having its status changed after issuance — no such mechanism,
event, or function is documented. **`UNCONFIRMED`.**

**What happens when a CVA is frozen, revoked, or otherwise restricted**:
**`UNCONFIRMED`** — not addressed by either guide at all. The CVI
guide's overview mentions the *validator* "can pause pools or freeze
accounts (emergency risk control)," but that is a CVI-validator-level
control over pools/accounts, not a CVA-token-level freeze/revoke
mechanism, and even that control's exact function signatures are not
given (`docs/cleanverse-integration.md` §1, §"Still open" item 9 in the
todo file). This specification does not invent a CVA freeze/revoke
mechanism to fill this gap — see §12 (Failure handling) for how BitV
should behave given this unknown.

## 2. CVA registration

Per `docs/cleanverse-integration.md` §3/§5, restated here for this
milestone's specific focus (BitV as a *consumer*, never an issuer, of
CVA):

| Item | Status |
|---|---|
| API registration (`POST /api/cooperate/atoken/launch`, Method A) | Confirmed to exist; full request/response schema beyond the named fields (`chain`/`atoken_address`/`atoken_icon`/`owner_signature`/`callback_url` for registration; AES/CBC/PKCS5Padding-encrypted body, `api-id` + `X-Request-ID` headers for launch) not given |
| Custom CVA contract registration (`POST /api/cooperate/atoken/register`, Method B) | Confirmed to exist; `owner_signature` = EIP-191 `personal_sign` over `lowercase(chain + atoken_address)`, confirmed for this endpoint specifically |
| Required parameters (full schema) | Only the fields named above are confirmed; full schemas are `UNCONFIRMED` |
| Registration signatures | Method B's is confirmed as above; the *review process* Cleanverse applies before accepting a registration is `UNCONFIRMED` |
| Review process | **`UNCONFIRMED`** — neither guide describes what Cleanverse checks before approving a CVA registration |
| Contract registration | Confirmed at the level of "call this endpoint with this signature"; nothing about Cleanverse's internal approval process |
| Required roles | Optional `MINTER_ROLE` grant lets a platform contract (e.g. Cleanverse's "AccessCore") mint/burn CVA on the issuer's behalf — confirmed to exist, no further detail on granting/managing it |
| Required Cleanverse approval | Implied by "registration" existing as a distinct step from deployment, but the approval criteria/timeline are `UNCONFIRMED` |
| **What BitV can verify on-chain** | Whether a given token address implements the `IATokenPolicy` interface (by attempting to call its functions, §3) and whether `canTransfer` returns a sane boolean for a given transfer — this is real, callable, on-chain behavior BitV's own contracts can observe directly |
| **What remains an off-chain Cleanverse dependency** | Whether Cleanverse actually *approved* a given token as a CVA (as opposed to merely deploying/registering a contract that happens to implement the right interface) — no on-chain "is this token Cleanverse-approved" query is documented anywhere in either guide. This is the single most important gap this specification's architecture (§6, §7, §14) is built around, not glossed over. |

**No missing request fields, addresses, endpoints, signatures, or
response formats are invented anywhere in this document.**

## 3. CVA contract interface

Extracted verbatim from `docs/cleanverse-integration.md` §3/§7 (itself
transcribed from the CVA guide) — **exact function names as
documented; parameter/return types not exhaustively re-specified by
either guide beyond what's listed below**, so this table states
exactly what's confirmed and marks the rest `UNCONFIRMED` rather than
inferring types by analogy to `IAPassComplianceValidator`.

| Interface | `IComplianceRule` / `IATokenPolicy` (CVA guide's own naming — the guide uses both names for what is functionally one policy interface; which name is the interface's actual Solidity identifier is not disambiguated by the source material) |
|---|---|
| **Purpose** | The compliance policy contract a CVA token calls into on every transfer, gating it via CVI verification + RuleV2 |

| Function (name, as documented) | Parameters | Return | Visibility/Mutability | Purpose | Confirmed? |
|---|---|---|---|---|---|
| `canTransfer` | `(token, from, to, amount)` — parameter *names* not given in the transcription; this is the call signature described in `docs/cleanverse-integration.md` §5's CVA-guide citation ("`canTransfer(token, from, to, amount)`") | `UNCONFIRMED` (presumed `bool`, matching `complianceVerify`'s pattern, but no guide text confirms this) | `UNCONFIRMED` (presumed `view`/`external`, not stated) | Decides whether a specific CVA transfer is compliant | Function name + argument list: ✅ Confirmed. Exact types/visibility: ❌ `UNCONFIRMED` |
| `setRuleV2` | Takes a `RuleV2` (§4), by token address (admin-facing) | `UNCONFIRMED` | `UNCONFIRMED` | Set the policy's RuleV2 for a given token, admin-gated | Name confirmed; signature detail `UNCONFIRMED` |
| `addRuleV2` | Takes a `RuleV2`, by token address (admin-facing) | `UNCONFIRMED` | `UNCONFIRMED` | Append a RuleV2 | Name confirmed; signature detail `UNCONFIRMED` |
| `removeRuleV2` | `UNCONFIRMED` | `UNCONFIRMED` | `UNCONFIRMED` | Remove a RuleV2, by token address | Name confirmed; signature detail `UNCONFIRMED` |
| `setRuleV2FromToken` | Takes a `RuleV2` — called by the token contract itself | `UNCONFIRMED` | `UNCONFIRMED` | Same as `setRuleV2` but self-service (token calling on its own behalf, mirroring `setRuleV2FromContract`'s pattern on the CVI validator) | Name confirmed; signature detail `UNCONFIRMED` |
| `addRuleV2FromToken` | Takes a `RuleV2` | `UNCONFIRMED` | `UNCONFIRMED` | Self-service append | Name confirmed; signature detail `UNCONFIRMED` |
| `removeRuleV2FromToken` | `UNCONFIRMED` | `UNCONFIRMED` | `UNCONFIRMED` | Self-service remove | Name confirmed; signature detail `UNCONFIRMED` |
| `getRulesV2` | By token address | `UNCONFIRMED` (presumed `RuleV2[]`, matching the CVI validator's `getRulesV2` pattern, but not stated for this interface specifically) | `UNCONFIRMED` (presumed `view`) | Read the current RuleV2 set for a token | Name confirmed; signature detail `UNCONFIRMED` |

**Events, errors, modifiers**: **`UNCONFIRMED` for all of the above** —
`docs/cleanverse-integration.md` §7 states plainly: "Events —
`UNCONFIRMED` — neither guide lists validator/CVA events." No error
names or modifier names are given for `IATokenPolicy` either. This
specification does not invent any.

**Why this table is thinner than §3's own function-name list might
suggest it could be**: the task instructs "do not paraphrase function
signatures where exact documentation is available" — the exact
documentation available (via `docs/cleanverse-integration.md`, itself
built from the two PDFs) gives function *names* with confidence but not
full parameter/return type signatures for most of them, `canTransfer`'s
argument list being the one partial exception. Filling in the rest with
plausible-looking Solidity types (by analogy to `IAPassComplianceValidator`)
would be exactly the kind of invention this milestone's instructions
forbid.

## 4. RuleV2

Confirmed, verbatim from the CVI guide §3.1 (already implemented in
`contracts/src/interfaces/external/IAPassComplianceValidator.sol` for
the CVI validator; the CVA policy interface uses "the *same* `RuleV2`
struct," per §3 above):

```solidity
struct RuleV2 {
    bytes2 allowedGroup;      // Allowed CVI group (empty = no restriction)
    bytes2 allowedSubGroup;   // Allowed CVI sub-group (empty = no restriction)
    uint8 minTier;            // Minimum CVI tier (0 = no restriction)
    uint8 minSubTier;         // Minimum CVI sub-tier (0 = no restriction)
    uint256 poolCountryBitmap; // Country bitmap (0 = no restriction)
}
```

**No additional fields are created here** — this is the complete,
confirmed field list, unchanged from the existing implementation.

- **AND behavior within a rule**: "Fields within a single RuleV2 are
  AND" — every non-empty/non-zero field on one `RuleV2` entry must be
  satisfied simultaneously.
- **OR behavior across rules**: "multiple RuleV2s are OR" — a
  participant/transfer need only satisfy *one* registered `RuleV2` entry
  to pass.
- **Country bitmap semantics**: "country bitmaps are checked via
  bitwise AND" — a participant's own country bit(s) are AND-ed against
  `poolCountryBitmap`; a nonzero result satisfies that field (per the
  existing `MockComplianceValidator` test implementation's mirroring of
  this rule, `countryOk = rule.poolCountryBitmap == 0 || (rule.poolCountryBitmap & cvi.countryBit) != 0`).
- **How rules affect transfers**: for the CVA policy interface
  specifically, `canTransfer` is presumed (by direct analogy to
  `complianceVerify`'s confirmed behavior, and consistent with "the same
  `RuleV2` struct") to apply the identical AND/OR/bitwise-AND semantics
  against the *transfer's* participants (from/to) rather than a single
  `user` — but which of `from`, `to`, or both are checked against the
  registered `RuleV2` set is **`UNCONFIRMED`**; neither guide states
  this explicitly for `canTransfer`.
- **How CVI status participates**: every transfer is "gated through CVI
  compliance verification and the RuleV2 policy engine" (§1) — meaning
  `canTransfer`'s decision is expected to depend on the CVI status of at
  least one transfer participant, consistent with `complianceVerify`'s
  pattern, but the exact mechanism (does `canTransfer` call
  `complianceVerify` internally? does it duplicate that logic?) is
  **`UNCONFIRMED`**.

## 5. CVA transfer flow

**Who calls `canTransfer`?** The CVA token contract itself, from inside
its own `_update` hook (ERC-20 transfer hook) — per §1/§3 above:
"deploy your own ERC20... implementing `IATokenPolicy`, calling
`policy.canTransfer(...)` in `_update`." **BitV never calls
`canTransfer` directly as part of a normal transfer** — it happens
automatically, transparently, inside the CVA token's own transfer
logic, whenever *anyone* (including BitV's contracts) calls `transfer`/
`transferFrom` on that token.

**What inputs are required?** `(token, from, to, amount)` per §3 — the
exact parameter types are `UNCONFIRMED`.

**What happens when it returns `false`?** **`UNCONFIRMED`** — neither
guide states whether the token's `_update` reverts, silently no-ops, or
does something else when `canTransfer` returns `false`. The only
confirmed statement is the high-level one already cited in §1: "every
transfer is gated through CVI compliance verification and the RuleV2
policy engine" — implying *some* enforcement occurs, but not its exact
mechanism.

**Can transfers revert?** Presumed yes (an ERC-20 `_update` override
that gates a transfer and finds it non-compliant would conventionally
revert, matching how `BitVComplianceGuard._requireCompliance` already
reverts on a `false` `complianceVerify` result) — but this is an
inference from convention, not a confirmed fact from either guide, and
is treated as such throughout this specification (§12 designs for the
possibility that it might instead silently fail or return a boolean
`transferFrom` result of `false` without reverting).

**Where does CVI enter the decision?** Inside `canTransfer` itself
(§4's analysis) — not something BitV's own contracts additionally
check for a CVA-to-CVA leg, per the CVI guide §4.5's "CVA automatic
compliance" mode already documented in
`docs/cleanverse-integration.md` §3: "compliance checks are performed
automatically by the CVA contract — the business contract does not
need to call the validator explicitly."

**Where does RuleV2 enter the decision?** The CVA policy contract's own
registered `RuleV2` set (via `getRulesV2`, §3/§4) — a separate rule set
from whatever `RuleV2` entries BitV's own contracts (via
`BitVComplianceGuard`) have registered with the CVI validator for their
own `complianceVerify` gate. These are **two independent rule sets**,
not a shared one — confirmed by the fact that the CVA policy interface
has its own `setRuleV2`/`getRulesV2` functions distinct from the CVI
validator's.

**What happens during transfers initiated by BitV?** When BitV's own
contract (e.g. `BitVLendingManager`) calls `transferFrom` on a CVA
token — for collateral deposit, withdrawal, or liquidation seizure —
that call flows through the CVA token's own `_update`/`canTransfer`
gate exactly the same as any other caller's transfer would. BitV's
contract does not need, and per the confirmed "automatic compliance"
mode should not perform, a redundant `complianceVerify` call for that
specific asset leg — but BitV's own `BitVComplianceGuard._requireCompliance`
gate on the *protocol action* itself (e.g. "can this wallet call
`depositCollateral` at all") remains mandatory and independent, per
§11's compliance ordering.

## 6. BitV CVA adapter

**`IBitVCVAAdapter`** (new, narrow interface — not implemented in
Solidity this milestone, specified here for the next milestone):

```solidity
interface IBitVCVAAdapter {
    /// @notice True only if `token` both implements the confirmed
    /// IATokenPolicy/IComplianceRule call surface (verified by
    /// successfully calling its documented view functions) AND has
    /// been explicitly attested by RWA_ADMIN_ROLE as a real,
    /// Cleanverse-approved CVA (see §7 — the off-chain approval fact
    /// this adapter cannot itself verify on-chain).
    function isRecognizedCVA(address token) external view returns (bool);

    /// @notice The policy contract address `token` uses, if any.
    function policyOf(address token) external view returns (address);

    /// @notice Best-effort preview of whether a transfer would be
    /// permitted, by calling the policy's own canTransfer — "best
    /// effort" because canTransfer's exact revert/return behavior on
    /// rejection is UNCONFIRMED (§5); this function does not claim to
    /// resolve that ambiguity, only to surface whatever answer the
    /// policy contract actually gives, non-reverting.
    function previewTransfer(address token, address from, address to, uint256 amount)
        external
        view
        returns (bool permitted);

    /// @notice Whether `token` is currently usable by BitV at all —
    /// combines isRecognizedCVA with any BitV-side suspension (see §7's
    /// integration with BitVRWACollateralRegistry's existing
    /// Active/Frozen/Delisted states).
    function isCurrentlyUsable(address token) external view returns (bool);
}
```

**Design principles, per the task's explicit instructions:**
- **Does not duplicate Cleanverse's policy engine** — `previewTransfer`
  and `isRecognizedCVA` call *into* the actual on-chain policy contract
  (`canTransfer`, `getRulesV2`) rather than reimplementing RuleV2's
  AND/OR/bitwise-AND semantics in BitV's own code. BitV's adapter is a
  thin caller, never a second implementation of the same logic.
- **Remains replaceable if Cleanverse changes its integration surface**
  — every consuming BitV contract (§7, §8, §9) depends only on
  `IBitVCVAAdapter`, never on `IATokenPolicy` directly, so a future
  Cleanverse interface change only requires a new adapter
  implementation behind the same narrow interface, mirroring exactly
  how `IBitScoreManager`/`IRWACollateralRegistry` already insulate
  `BitVLendingManager` from their respective implementations' internals.
- **`isRecognizedCVA` cannot, by itself, fully answer "is this
  Cleanverse-approved"** — per §2's core finding, no on-chain query for
  Cleanverse's off-chain approval exists. The adapter can verify the
  token *behaves like* a CVA (implements the interface, responds to
  calls) but cannot verify Cleanverse actually *approved* it. This
  limitation is inherent to the adapter design, not fixable by a
  cleverer adapter — it is a genuine gap in what Cleanverse's
  documentation makes verifiable on-chain, addressed structurally in §7
  rather than pretended away.

## 7. RWA registry integration

**What should replace/supplement `BitVRWACollateralRegistry`'s current
bare `AssetConfig.isCVA` bool**, per the task's explicit instruction
that admin-attested metadata alone is not sufficient for this
milestone:

**Recommended change (specified here, not implemented): replace the
bare `bool isCVA` field with a richer, two-part verification model:**

```solidity
struct CVAStatus {
    bool adminAttestedCVA;   // RWA_ADMIN_ROLE's claim that this is a CVA
    address cvaAdapter;      // IBitVCVAAdapter instance verifying it, address(0) if none configured
    bool onChainInterfaceVerified; // adapter successfully resolved the token's policy contract
}
```

**The exact verification boundary, stated explicitly (per the task's
instruction to define it exactly, not vaguely):**

1. `RWA_ADMIN_ROLE` may still set `adminAttestedCVA = true` — this
   claim alone is **never sufficient** to unlock any CVA-specific
   behavior (§8, §9).
2. A CVA-specific behavior (e.g. skipping a redundant `complianceVerify`
   call for a "automatic compliance" asset leg, per §5) may only be
   enabled when **both** `adminAttestedCVA == true` **and**
   `onChainInterfaceVerified == true` — the latter set only by a
   successful, on-chain call through `IBitVCVAAdapter.isRecognizedCVA`
   confirming the token actually responds to the documented
   `IATokenPolicy` call surface.
3. **What this boundary does *not* claim to solve**: even with both
   flags `true`, BitV still cannot verify Cleanverse's own off-chain
   approval of the token (§2, §6). The two-flag model raises the bar
   above pure assertion (a token must be a real, responding contract
   implementing the right interface — an admin cannot mark an arbitrary
   ERC-20 with no such interface as CVA-verified and have
   `onChainInterfaceVerified` become `true`), but it is **not** a
   substitute for Cleanverse confirmation and must never be presented
   as one. This is the honest, explicit limitation the task asks for
   rather than a claim of complete verification.
4. **`RWAStatus` (Active/Frozen/Delisted/Unregistered, unchanged from
   the existing implementation) remains the single authoritative
   eligibility gate** for whether an asset counts toward new borrowing
   capacity at all (per `docs/rwa-market-implementation.md`'s existing
   `isEligibleForNewActivity`) — the CVA flags above are additive
   metadata read by lending/vault integration points (§8, §9) for
   CVA-*specific* behavior only (automatic-compliance skip, CVA-specific
   settlement notes), never a replacement for that existing gate.

## 8. Lending integration

CVA status changes **nothing** about the hard gates already in place —
restated explicitly per the task's instruction:

- **Collateral deposits**: `BitVComplianceGuard._requireCompliance`
  (CVI, on the depositing user) and `BitVRWACollateralRegistry`'s
  existing eligibility gate (§7's point 4) both remain mandatory,
  unconditionally, regardless of CVA status. A CVA-recognized asset
  additionally has its `transferFrom` leg gated by the token's own
  `canTransfer` (§5) — an *additional* check layered on top, never a
  replacement for either existing gate.
- **Borrowing**: unaffected — CVA status has no bearing on the debt
  asset side; `docs/rwa-market-specification.md`/`-implementation.md`'s
  LTV, oracle, and BitScore integration are entirely unchanged.
- **Repayment**: same as deposits — CVI compliance and (if the debt
  asset happens to be a CVA) the token's own transfer gate both apply,
  additively.
- **Withdrawal**: same principle — a CVA-recognized asset's withdrawal
  transfer is subject to the token's own `canTransfer` on the receiving
  side (the withdrawing user), which is outside BitV's control; if that
  reverts, the withdrawal reverts, and there is nothing BitV's contract
  should or could do to force it through (matches
  `docs/rwa-market-specification.md` §5's already-identified liquidation
  wrinkle, extended here to withdrawal).
- **Liquidation**: identical wrinkle already identified in
  `docs/rwa-market-specification.md` §5's CVA table — seizing CVA
  collateral during liquidation is a `transferFrom` to the liquidator,
  which the CVA token's own hook compliance-gates on the *recipient*.
  **A liquidator who is not CVI-compliant could have a CVA-backed
  liquidation revert at the token level** — this specification does not
  resolve that (§14 lists it as an explicit item requiring a product
  decision before implementation, same as the RWA spec left it as open
  question 3).

**CVA compliance never bypasses**: the CVI gate, the RWA registry gate,
oracle checks, LTV limits, BitScore limits, or pool limits — every one
of these remains exactly as implemented today; CVA integration only
ever adds an *additional* check on top (the token's own transfer gate),
never removes or weakens an existing one. **The lending engine itself
is not rewritten** — no function in `BitVLendingManager` needs new
control flow beyond, at most, an optional query to
`IBitVCVAAdapter.isCurrentlyUsable` mirrored exactly on the existing
`try`/`catch`-wrapped, fail-safe pattern already used for
`IBitScoreManager`/`IRWACollateralRegistry`.

## 9. Vault integration

**Not every CVA can automatically be used in every vault** — explicit
eligibility, per the task's instruction:

- **Vault underlying assets**: `docs/yield-vault-specification.md`
  already requires "one immutable underlying asset per vault,
  explicitly configured" (§5) and already refuses to label an asset CVA
  "unless confirmed by Cleanverse documentation" (§5/§10). This
  specification adds nothing new here beyond noting that if a specific
  vault's underlying *is* recognized as a CVA (via §6/§7's adapter +
  registry model), the vault's own `deposit`/`withdraw` transfers would
  additionally be gated by that token's `canTransfer` — same additive
  principle as §8.
- **Strategy assets**: `IBitVVaultStrategy` (Build 05.1) is
  asset-agnostic by design — whatever the vault's underlying is, the
  strategy moves the same token. No CVA-specific strategy behavior is
  proposed; a strategy holding CVA collateral is subject to the same
  `canTransfer` gate on every strategy-vault transfer leg as any other
  CVA transfer.
- **Yield distribution assets**: `docs/yield-vault-specification.md`
  never proposed yield paid in a different asset than the vault's own
  underlying — no change needed here.
- **Withdrawal assets**: same as underlying — no separate withdrawal
  asset exists in the current vault design (ERC-4626's single-asset
  model), so this is not a distinct integration point.

**Explicit eligibility rule**: a vault's underlying asset being
CVA-recognized (§6/§7) does not automatically make it eligible for
*any* vault — vault deployment already requires `PROTOCOL_ADMIN_ROLE`
to explicitly configure a specific underlying asset at construction
(`docs/yield-vault-implementation.md`'s existing, unmodified
architecture); CVA recognition is orthogonal metadata about that
already-explicit choice, not an automatic unlock.

## 10. Settlement

**What Cleanverse actually supports regarding CVA settlement, per the
two guides: nothing beyond the transfer-time compliance gating already
described in §1/§5.** Restated explicitly, per the task's instruction
not to invent:

- **Settlement contracts**: **`UNCONFIRMED`** — not described in either
  guide.
- **Recovery mechanisms**: **`UNCONFIRMED`** — not described.
- **Redemption systems**: **`UNCONFIRMED`** — not described (a CVA
  representing an off-chain RWA presumably has *some* real-world
  redemption process, but neither guide documents one; this mirrors
  `docs/rwa-market-specification.md` §5's identical conclusion for CVA
  settlement/recovery/redemption).
- **CVA treasury mechanics**: **`UNCONFIRMED`** — not described. BitV's
  own `BitVTreasury` is a BitV-native concept entirely independent of
  Cleanverse; nothing in either guide describes a Cleanverse-side
  treasury mechanism for CVA.
- **Cross-chain settlement**: **`UNCONFIRMED`** — neither guide
  describes any cross-chain mechanism for CVA; the CVA guide's network
  list ("Ethereum, Base, BSC, Arbitrum, Polygon, etc.") describes where
  CVA *can be deployed*, not any bridging/cross-chain settlement
  capability.

**No settlement mechanism beyond "transfers are compliance-gated" is
proposed anywhere in this specification.**

## 11. Compliance order

The exact flow the task requires, verified against every integration
point described above:

```
CVI eligibility
  (BitVComplianceGuard._requireCompliance — existing, unmodified,
   mandatory for every protected BitV action regardless of asset type)
  ↓
CVA eligibility
  (IBitVCVAAdapter.isRecognizedCVA + BitVRWACollateralRegistry's
   two-flag CVA status, §7 — only relevant when the asset in question
   is CVA-recognized; irrelevant/skipped for non-CVA assets)
  ↓
CVA transfer/policy validation
  (the CVA token's own canTransfer, invoked automatically inside its
   _update hook whenever a transfer actually occurs — not a separate
   BitV-initiated call, §5)
  ↓
BitV market rules
  (BitVPoolManager pool config, BitVRWACollateralRegistry eligibility/
   caps, existing and unmodified)
  ↓
BitScore adjustments where applicable
  (existing Build 04 IBitScoreManager integration, unmodified — LTV/
   interest-rate-quote adjustments only, never eligibility)
  ↓
Transaction execution
```

**CVA must never replace CVI** — confirmed by construction: every
protected BitV action still requires `_requireCompliance` regardless
of whether the asset involved is a CVA; CVA's automatic-compliance mode
(§5) only means BitV doesn't need a *redundant* `complianceVerify` call
for that specific asset *transfer* leg — it never removes the
*protocol-action*-level CVI gate.

**BitScore must never replace CVI** — unchanged from Build 04's
existing, already-tested guarantee (`docs/bitscore-implementation.md`);
nothing in this specification touches that boundary.

**BitScore must never override CVA policy restrictions** — structurally
guaranteed by the ordering above: CVA policy validation happens at the
token-transfer level, entirely outside and prior to
`BitVLendingManager`'s BitScore-adjusted LTV calculation; BitScore has
no code path that could even attempt to influence a CVA token's own
`canTransfer` decision, since BitV's contracts never call `canTransfer`
directly (§5) — it fires automatically inside the token, unreachable
from BitScore's LTV-adjustment logic.

## 12. Failure handling

**Default behavior must be fail-safe — a failure must never accidentally
increase user permissions or borrowing capacity.** Every scenario the
task lists, resolved in that direction:

| Condition | BitV behavior |
|---|---|
| Invalid CVA (malformed/non-conforming contract) | `IBitVCVAAdapter.isRecognizedCVA` returns `false` (or the underlying call reverts, caught and treated as `false`) — asset is treated as a non-CVA, ordinary RWA asset subject to the existing registry gate only |
| Unregistered CVA (never registered with the registry at all) | Entirely outside CVA-specific logic — behaves exactly as any non-RWA-registered asset does today, per `docs/rwa-market-implementation.md`'s existing "unaffected" principle |
| CVA policy rejection (`canTransfer` returns `false`, if that's confirmed to be its rejection mechanism — §5's `UNCONFIRMED` note applies) | The underlying token transfer fails/reverts (at the token level, not something BitV's contract needs to separately detect) — the BitV-level action (deposit/borrow/withdraw/liquidate) that depended on that transfer fails as a whole, no partial state change, matching the existing `SafeERC20`-based all-or-nothing transfer pattern already used throughout `BitVLendingManager`/`BitVPoolManager`/`BitVYieldVault` |
| CVI rejection | Existing, unchanged behavior — `ComplianceErrors.ComplianceCheckFailed` |
| Frozen CVA | **`UNCONFIRMED`** whether this concept even exists at the Cleanverse level (§1) — if a future confirmed mechanism exists, `IBitVCVAAdapter.isCurrentlyUsable` should reflect it as `false`, structurally identical to the RWA registry's existing `Frozen` status handling (new deposits/borrowing stop, existing positions remain manageable) |
| Revoked CVA | Same as Frozen — **`UNCONFIRMED`** whether the concept exists; if confirmed later, treated identically to the registry's `Delisted` status |
| Unsupported CVA (e.g. a token claiming CVA status Cleanverse never actually verified) | This is exactly §7's "admin-attested but not on-chain-interface-verified" case — never granted any CVA-specific behavior; falls back to ordinary-RWA-asset treatment |
| Missing policy (token implements no discoverable policy contract) | `IBitVCVAAdapter.policyOf` returns `address(0)` / `isRecognizedCVA` returns `false` — same fallback as "invalid CVA" |
| Cleanverse integration unavailable (adapter address unset, or every call reverts) | Mirrors the existing `IBitScoreManager`/`IRWACollateralRegistry` optional-dependency pattern exactly: `address(0)` = feature disabled, every consuming call site `try`/`catch`-wrapped, falling back to "not a CVA, treat as ordinary asset" — never to "assume compliant" |
| Unknown CVA state | Treated as ineligible/non-CVA by default — the fail-safe direction applies to *ambiguity* itself, not just confirmed-negative results |
| Transfer validation failure | Propagates as a reverted transaction (via `SafeERC20`'s existing revert-on-failure semantics) — no BitV contract catches and continues past a failed asset transfer |

**No failure path in this specification ever results in more favorable
terms, higher borrowing capacity, or bypassed compliance than the
non-CVA baseline** — exactly the same fail-safe direction already
established for BitScore (Build 04) and the RWA registry (Build 06.1).

## 13. Security model

| Risk | Analysis |
|---|---|
| Fake CVA tokens | `isRecognizedCVA`'s on-chain-interface-verification step (§6/§7) means a fake token that doesn't actually implement the documented call surface fails verification and gets no CVA-specific treatment — but see the next row for the deeper risk |
| Admin-attested CVA spoofing | The core risk this milestone's two-flag model (§7) exists to blunt, not eliminate: a malicious or careless `RWA_ADMIN_ROLE` could still set `adminAttestedCVA = true` on a token that implements `IATokenPolicy`'s call surface *cosmetically* (e.g. a contract the admin themselves deployed to always return permissive answers) without genuine Cleanverse approval. `onChainInterfaceVerified` proves the token *responds like* a CVA, not that Cleanverse *approved* it — this is an inherent limitation given the confirmed absence of an on-chain approval query (§2), not a bug to be fixed by better Solidity |
| Policy bypass | BitV never implements its own copy of RuleV2/canTransfer logic (§6's design principle) — there is no BitV-side policy logic to bypass; the only bypass surface is the token's own (Cleanverse-controlled) policy contract, outside BitV's trust boundary entirely |
| Transfer bypass | Not possible via BitV's contracts specifically — every collateral/debt transfer already goes through standard `SafeERC20` calls that hit the token's real `_update`/`canTransfer` hook; BitV cannot special-case a CVA to skip that hook even if it wanted to, since the hook lives in the token contract, not BitV's |
| CVI bypass | Unchanged from the existing, already-tested guarantee — CVA integration adds no new path around `_requireCompliance` |
| Reentrancy | The adapter's functions are `view`-only by design (§6) and consuming contracts already wrap all external calls in `nonReentrant`-guarded functions (existing pattern); no new reentrancy surface |
| Malicious token contracts | A token claiming to be a CVA could implement `canTransfer` to always return `true` regardless of actual compliance — this is indistinguishable on-chain from a genuine, permissive CVA policy without Cleanverse's own off-chain attestation (same root cause as "admin-attested CVA spoofing" above) |
| Malicious policy contracts | Same root cause — the adapter calls whatever policy contract the token points to; if that contract is malicious, the adapter has no independent way to detect it beyond the interface-response check already described |
| Oracle manipulation | Out of scope for this specification — CVA status is orthogonal to price oracles; `docs/rwa-market-specification.md`/`-implementation.md`'s existing oracle staleness/manipulation analysis is unaffected and unchanged |
| Frozen CVA collateral | See §12 — treated as ineligible for new activity, existing positions remain manageable, mirroring the RWA registry's existing `Frozen` handling |
| Revoked CVA collateral | Same as frozen, mirroring `Delisted` |
| Unauthorized policy changes | BitV never calls `setRuleV2`/`addRuleV2`/`removeRuleV2` on a CVA policy contract it doesn't own — those are the *issuer's* rule-management functions (§3), entirely outside BitV's authority or intent; BitV only ever reads (`getRulesV2`, `canTransfer` previews) |
| Unauthorized asset registration | Unchanged — `RWA_ADMIN_ROLE`-gated exactly as today, plus the two-flag model requiring `onChainInterfaceVerified` for any CVA-specific behavior to activate |
| Cross-contract callback attacks | The adapter makes no state-changing external calls (all `view`), and every BitV contract consuming it does so from within its own `nonReentrant` boundary — no new callback surface is introduced |

## 14. Architecture decision

**Comparing the four options the task lists:**

**(A) Inline CVA logic inside `BitVRWACollateralRegistry`.**
- *Risk*: mixes two genuinely different concerns — "is this asset
  eligible RWA collateral" (the registry's existing, focused job) and
  "does this asset behave like a real CVA on-chain" (a Cleanverse-
  specific verification concern) — into one contract, growing its
  complexity and coupling it to Cleanverse's specific interface shape.
  A future Cleanverse interface change would require modifying the
  registry itself.

**(B) Dedicated `BitVCVARegistry`.**
- *Risk*: significant overlap with `BitVRWACollateralRegistry`'s
  existing responsibilities (asset status, eligibility) — a CVA is
  always *also* an RWA asset in BitV's model (§9's vault case aside,
  which doesn't need a registry at all), so a second, parallel registry
  invites the exact kind of accounting duplication
  `docs/rwa-market-specification.md` §2 already rejected once for the
  RWA-vs-lending-engine split. Not the smallest architecture.

**(C) Dedicated `BitVCVAAdapter` only** (no registry changes).
- *Risk*: leaves `BitVRWACollateralRegistry`'s `isCVA` exactly as
  admin-attested as it is today — the adapter would exist but nothing
  would require consulting it before treating an asset as CVA-verified,
  failing the task's explicit instruction that admin-attested metadata
  alone is insufficient for this milestone.

**(D) Combination of registry (extended) + adapter — chosen.**
- A thin, replaceable `BitVCVAAdapter` (§6) owns 100% of the actual
  Cleanverse-interface-calling logic — the only place BitV code touches
  `IATokenPolicy`-shaped calls at all.
- `BitVRWACollateralRegistry` is *extended* (not rewritten) with the
  two-flag `CVAStatus` model (§7) — reusing its existing
  Active/Frozen/Delisted eligibility gate unchanged, adding only the
  additional metadata needed to distinguish "admin claims CVA" from
  "on-chain-interface-verified CVA."
- **This is the smallest architecture that provides a clean separation
  between Cleanverse infrastructure (the adapter, entirely replaceable)
  and BitV protocol logic (the registry's existing eligibility model,
  entirely unchanged in its core responsibility)** — exactly the
  separation the task asks for, achieved with one new, narrow contract
  plus an additive extension to an existing one, rather than a second
  full registry or logic buried inside an unrelated contract.

## 15. Existing contract impact

| Contract | Change required? | Reason |
|---|---|---|
| `BitVAccessManager` | **None** | `RWA_ADMIN_ROLE` (already exists, Build 06.1) is sufficient for the registry's new `CVAStatus` fields; no new role is needed for this milestone's scope |
| `BitVComplianceGuard` | **None** | CVI compliance checking is entirely unaffected — CVA integration adds a parallel, independent check, never modifies this one |
| `BitVPoolManager` | **None** | Pool-level accounting (LTV, liquidation threshold, caps) is asset-type-agnostic already; CVA status doesn't change any pool mechanic |
| `BitVLendingManager` | **Additive only, optional** — at most a `try`/`catch`-wrapped `IBitVCVAAdapter.isCurrentlyUsable` query mirroring the existing `IBitScoreManager`/`IRWACollateralRegistry` integration pattern, if a future implementation milestone decides BitV-level logic should differentiate CVA vs. non-CVA assets beyond what the token's own transfer hook already enforces automatically | No existing function signature changes; every existing collateral/debt/liquidation code path is unaffected for non-CVA assets |
| `BitVVaultManager` | **None** (this milestone) | No CVA-specific vault logic is proposed beyond the eligibility principle in §9, which requires no code change — vault deployment is already explicit-asset-only |
| `BitScoreManager` | **None** | Confirmed unaffected by §11's ordering — BitScore has no CVA awareness and needs none |
| `BitVTreasury` | **None** | No CVA-specific treasury mechanics exist (§10) |
| `BitVRWACollateralRegistry` | **Additive extension**: replace the bare `bool isCVA` field with the two-flag `CVAStatus` struct (§7); no existing field, function signature, or eligibility check is removed or narrowed | Directly implements the task's core requirement that admin-attested metadata alone is insufficient |

**Zero or additive changes throughout, as the task prefers** — no
existing economic contract's core logic is rewritten.

## 16. Test plan

None of the following exist yet — this is the plan for a future
implementation milestone's Foundry suite, mirroring the established
style of `BitVRWACollateralRegistry.t.sol`/`RWAHandler.sol`:

**CVA recognition / verification**
- `test_RecognizedCVA_InterfaceVerificationSucceeds`
- `test_FakeToken_InterfaceVerificationFails`
- `test_AdminAttestedOnly_WithoutInterfaceVerification_NotTreatedAsCVA`
- `test_PolicyContractMissing_TreatedAsNonCVA`

**CVA policy acceptance/rejection**
- `test_CanTransfer_PermittedTransfer_PreviewReturnsTrue`
- `test_CanTransfer_RejectedTransfer_PreviewReturnsFalse`
- `test_CanTransfer_RevertingPolicy_TreatedAsRejected`

**CVI + CVA interaction**
- `test_CVICompliantUser_CVANotRecognized_FallsBackToOrdinaryRwaFlow`
- `test_CVINonCompliantUser_CVARecognized_StillRejected` (CVA never
  substitutes for CVI, §11)

**Lending with CVA**
- `test_DepositCVACollateral_RequiresBothCVIAndRegistryEligibility`
- `test_BorrowAgainstCVACollateral_UnaffectedLtvBitScoreLogic`
- `test_RepayWithCVADebtAsset_TransferGatedByTokenPolicy`

**RWA collateral with CVA**
- `test_CVAFlaggedAsset_StillSubjectToExistingRegistryStatusGate`
- `test_FrozenRegistryAsset_CVAStatusDoesNotOverrideFreeze`

**Vault interaction with CVA**
- `test_VaultUnderlyingIsCVA_TransferGatedOnDepositAndWithdraw`
- `test_CVAStatusDoesNotAutoEnableVaultEligibility`

**CVA transfer rejection**
- `test_CVATransferRejected_DepositReverts`
- `test_CVATransferRejected_LiquidationSeizureReverts` (the §8 wrinkle)

**Frozen / revoked CVA**
- `test_FrozenCVA_NewDepositBlocked` (if/when the underlying concept is
  confirmed to exist — otherwise this test documents the current
  `UNCONFIRMED` status and asserts BitV's fallback behavior instead)
- `test_RevokedCVA_ExistingPositionsRemainManageable`

**Fake CVA**
- `test_FakeCVA_NeverGrantedAutomaticComplianceSkip`

**Unauthorized registration / policy configuration**
- `test_UnauthorizedCaller_CannotSetCVAStatus`
- `test_UnauthorizedCaller_CannotChangeAdapterAddress`

**Policy bypass attempts**
- `test_CannotForceBitVToSkipCVITransferGate_ViaCVAClaim`

**Reentrancy**
- `test_Reentrancy_MaliciousCVATokenCannotReenterDeposit` (mirrors the
  existing `MockReentrantERC20`/`MockReentrantVaultERC20` pattern)

**Oracle failure**
- `test_OracleFailure_UnaffectedByCVAStatus` (proves the two concerns
  stay orthogonal, per §13)

**Cleanverse integration failure**
- `test_AdapterUnset_FallsBackToOrdinaryRwaTreatment`
- `test_AdapterCallReverts_TreatedAsNonCVA`

**Invariants** (fuzzed, mirroring `RWAHandler.sol`'s established style)
- `invariant_CVAStatusNeverGrantsEligibilityWithoutRegistryStatus`
- `invariant_UnverifiedCVAClaimsNeverTreatedAsVerified`
- `invariant_ComplianceOrderNeverViolated` (CVI always checked before
  any CVA-specific logic runs)
- `invariant_AdapterFailureNeverIncreasesBorrowCapacity`

## 17. Cleanverse dependency table

| Requirement | Confirmed by Cleanverse docs? | Source | BitV implementation impact |
|---|---|---|---|
| CVI validator interface (`IAPassComplianceValidator`, `RuleV2`, `complianceVerify`) | ✅ Confirmed | CVI guide, `docs/cleanverse-integration.md` §Verification Table | Already implemented, unaffected by this milestone |
| CVA is a distinct primitive from CVI, built on the same RuleV2 struct | ✅ Confirmed | CVA guide §3 | Basis for §1/§4 of this spec |
| Two CVA issuance paths (API Launch, Custom Contract + register) | ✅ Confirmed | CVA guide, `docs/cleanverse-integration.md` §3/§5 | Basis for §2 |
| `canTransfer(token, from, to, amount)` function name + argument list | ✅ Confirmed | CVA guide, cited in `docs/cleanverse-integration.md` §5 | Basis for §3/§5/§6 |
| `canTransfer`'s return type, visibility, mutability | ❌ Unconfirmed | — | §3 leaves these unspecified rather than guessing |
| `setRuleV2`/`addRuleV2`/`removeRuleV2`/`*FromToken`/`getRulesV2` function names | ✅ Confirmed | CVA guide, `docs/cleanverse-integration.md` §3/§7 | Basis for §3 |
| Full signatures for the above | ❌ Unconfirmed | — | §3 |
| "Automatic compliance" mode (CVA transfers self-gate, business contract doesn't need a redundant `complianceVerify` call) | ✅ Confirmed | CVI guide §4.5, `docs/cleanverse-integration.md` §3 | Basis for §5/§8 |
| Behavior when `canTransfer` returns false (revert vs. silent) | ❌ Unconfirmed | — | §5/§12 design for both possibilities defensively |
| CVA freeze/revoke mechanism | ❌ Unconfirmed | — | §1/§12 explicitly do not invent one |
| CVA registration review/approval process | ❌ Unconfirmed | — | §2/§7's core finding — motivates the two-flag verification model |
| On-chain "is this token Cleanverse-approved" query | ❌ Unconfirmed (does not appear to exist) | — | §6/§7/§13's central limitation |
| CVA events (any) | ❌ Unconfirmed | — | Not referenced anywhere in this spec |
| CVA settlement/recovery/redemption mechanisms | ❌ Unconfirmed | — | §10 — none proposed |
| Cross-chain CVA settlement | ❌ Unconfirmed | — | §10 — not proposed |
| Monad Testnet support (general, unrelated to CVA specifically but relevant to any deployment) | ❌ Unconfirmed | `docs/cleanverse-integration.md` §Deployment Readiness | Not required for this specification (design-only), blocks any future deployment exactly as already documented |
| `MINTER_ROLE`/AccessCore mint-burn delegation | ✅ Confirmed to exist as a concept | CVA guide, `docs/cleanverse-integration.md` §3 | Not relevant to BitV as a consumer (only relevant to issuers) — **not required for MVP** |
| Query Apply Status / Supported CVA List / Add CVA Rule APIs | ❌ Unconfirmed (referenced by name only, no path) | CVA guide | Not usable, not required for MVP (BitV doesn't call these) |

## 18. Final recommendation

**Recommended architecture**: (D) — a dedicated, thin, replaceable
`BitVCVAAdapter` implementing the narrow `IBitVCVAAdapter` interface
(§6), paired with an additive extension of
`BitVRWACollateralRegistry`'s existing `isCVA` bool into a two-flag
`CVAStatus` model (§7) that requires both admin attestation *and*
on-chain interface verification before any CVA-specific behavior
activates. No other existing contract requires modification.

**Required contracts** (future implementation milestone, not this one):
- `BitVCVAAdapter` (new)

**Required interfaces** (future implementation milestone):
- `IBitVCVAAdapter` (new, specified in full in §6)
- `IATokenPolicy`/`IComplianceRule` (new — a BitV-side transcription of
  Cleanverse's documented CVA policy interface, exactly as
  `IAPassComplianceValidator.sol` already transcribes the CVI
  validator's interface; per §3, this transcription can only include
  what's actually confirmed — function names with `UNCONFIRMED` full
  signatures for most of them)

**Required changes to existing contracts**: `BitVRWACollateralRegistry`
only — replace `AssetConfig.isCVA` (bool) with the `CVAStatus` struct
(§7); every other existing contract requires zero changes for this
milestone's scope (§15's table).

**Cleanverse dependencies remaining before implementation should be
considered complete** (not before this specification, which is design-
only): full `canTransfer`/`setRuleV2`/`getRulesV2` signatures
(§3/§17), confirmation of `canTransfer`'s rejection mechanism
(§5/§17), and — ultimately, for any deployment, not specific to CVA —
Monad Testnet support and a deployed validator address (unchanged,
pre-existing blockers from `docs/cleanverse-integration.md`).

**Security considerations**: the central, unresolved risk is "admin-
attested CVA spoofing" (§13) — no amount of on-chain interface
verification can substitute for Cleanverse's own off-chain approval
fact, which is not queryable on-chain per current documentation. Any
future implementation must present `CVAStatus.onChainInterfaceVerified`
for exactly what it is (interface-shape verification) and never
conflate it with "Cleanverse-approved."

**Test scope**: per §16 — CVA recognition, policy accept/reject, CVI+CVA
interaction, lending/RWA/vault integration, transfer rejection,
frozen/revoked (contingent on future confirmation), fake-CVA, access
control, reentrancy, oracle-orthogonality, and adapter-failure
fail-safes, plus four fuzzed invariants.

**Deployment blockers** (unchanged from, and additive to, the existing
list in `docs/cleanverse-integration.md`):
1. Full `IATokenPolicy`/`canTransfer` signatures from Cleanverse —
   without them, `BitVCVAAdapter` cannot be implemented correctly.
2. Confirmation of `canTransfer`'s rejection mechanism (revert vs.
   return `false`) — needed to implement `previewTransfer` and §12's
   failure handling correctly rather than defensively guessing.
3. Any confirmation (or explicit denial) of a CVA freeze/revoke
   mechanism, and if one exists, its exact signature — currently
   entirely `UNCONFIRMED`.
4. The pre-existing, still-unresolved blockers: Monad Testnet support,
   a deployed `IAPassComplianceValidator` address, and the validator
   registration signing mechanism (`docs/cleanverse-integration.md`
   §Deployment Readiness) — none of these are CVA-specific, but all
   block any real deployment regardless of CVA readiness.

**This specification does not claim CVA integration is complete, does
not treat admin-attested metadata as equivalent to verified CVA
status, and does not invent any Cleanverse address, endpoint,
signature, or event beyond what `docs/cleanverse-integration.md`
already confirms.**
