# Cleanverse CVA Interface Verification (Build 07.2)

**Status: documentation and verification only. No Solidity, TypeScript,
or test file was modified for this milestone.** `BitVCVAAdapter`,
`IBitVCVAAdapter`, `IATokenPolicy`, `BitVRWACollateralRegistry`, and
every existing test file are byte-for-byte unchanged from Build 07.1.

**Source of truth**: the two official Cleanverse PDFs provided directly
to this project in Build 02.1 — "Cleanverse Compliance Protocol (CCP)
Integration Guide (For CVI Compliance Validator) V2" and "Cleanverse
Compliance Protocol (CCP) CVA Integration Guide" — exactly as already
transcribed in `docs/cleanverse-integration.md`,
`docs/cleanverse-integration-todo.md`, and
`docs/cva-integration-specification.md`. **No new Cleanverse material
was provided for this milestone.** This document re-verifies every item
the task lists against that existing transcription; it does not
re-search the web, does not consult third-party registries, does not
use generic ERC/EIP standards as a stand-in for Cleanverse-specific
confirmation, and does not infer missing details from memory. Every
item below is either traceable to a specific passage already quoted in
`docs/cleanverse-integration.md`, or marked `UNCONFIRMED`.

---

## 1. `IATokenPolicy`

**Official interface name**: `UNCONFIRMED` as a literal Solidity
identifier. The CVA guide (per `docs/cleanverse-integration.md` §3)
refers to the CVA policy interface using two different names in
different places — `IComplianceRule` and `IATokenPolicy` — without
disambiguating which one (if either, exclusively) is the actual
declared Solidity interface name Cleanverse ships. BitV's own
`contracts/src/interfaces/external/IATokenPolicy.sol` uses
`IATokenPolicy` as a working name, chosen because it's the more
frequently used of the two in the existing transcription — this is a
**naming choice BitV made**, not a confirmed fact about Cleanverse's
own source code.

**Function names**: `canTransfer`, `setRuleV2`, `addRuleV2`,
`removeRuleV2`, `setRuleV2FromToken`, `addRuleV2FromToken`,
`removeRuleV2FromToken`, `getRulesV2` — all confirmed to exist by name,
per `docs/cleanverse-integration.md` §3: "CVA's policy interface
(`IComplianceRule`/`IATokenPolicy`) uses the *same* `RuleV2` struct as
the CVI validator, but its own function names: `canTransfer`,
`setRuleV2`/`addRuleV2`/`removeRuleV2` (admin, by token address),
`setRuleV2FromToken`/`addRuleV2FromToken`/`removeRuleV2FromToken`
(token calling on its own behalf), `getRulesV2`."

**Parameters, return values, visibility, mutability**: `UNCONFIRMED`
for every function except `canTransfer`'s argument list (§3 below) and
the working assumption used for `getRulesV2` (§2 below, itself
disclosed as an inference, not a confirmation). No full Solidity
signature for any of these functions is given anywhere in the source
material.

**Events**: `UNCONFIRMED`. `docs/cleanverse-integration.md` §7 states
plainly: "Events — `UNCONFIRMED` — neither guide lists validator/CVA
events." This applies identically to the CVA policy interface; no
event name, no event field, nothing.

**Errors**: `UNCONFIRMED`. No custom error name is given for the CVA
policy interface anywhere in the source material.

**Modifiers**: `UNCONFIRMED`. No modifier name is given.

**Role requirements**: Partially confirmed at a conceptual level only.
`docs/cleanverse-integration.md` §3 confirms an "Optional `MINTER_ROLE`
grant lets a platform contract (e.g. Cleanverse's 'AccessCore') mint/
burn CVA on the issuer's behalf" — this is a role concept for
*minting/burning*, not for calling `canTransfer`/`getRulesV2`/rule-
management functions, and no `Solidity` role identifier (e.g. a
`bytes32` role hash, an `AccessControl` role name) is given for any of
those either. Whether `setRuleV2`/`addRuleV2`/`removeRuleV2` require a
specific role (as opposed to just being "admin, by token address," per
§3's own phrasing) is **`UNCONFIRMED`** beyond that phrase itself.

**Conclusion**: `IATokenPolicy.sol`'s current, Build 07.1 transcription
is already the maximally honest representation of this state — it
declares only `getRulesV2` (with a disclosed inference, §2) and
explicitly does not declare `canTransfer` or the rule-management
functions, exactly matching what this re-verification confirms remains
true. No update to that file is needed or made this milestone.

## 2. `getRulesV2`

**Function name**: Confirmed to exist for the CVA policy interface,
per §1 above.

**Exact CVA-side signature**: **`UNCONFIRMED`.** The CVA guide's own
text (as transcribed) states only that the function exists by name and
that the CVA policy interface "uses the *same* `RuleV2` struct" as the
CVI validator — it does not independently give `getRulesV2`'s
parameter list, return type, visibility, or mutability *for the CVA
policy interface specifically*.

**Parameters**: `UNCONFIRMED` for the CVA-side function. BitV's
`IATokenPolicy.sol` currently declares `getRulesV2(address token)` —
this parameter (one `address`) is an inference by direct analogy to the
CVI validator's `getRulesV2(address poolAddress)`, whose signature *is*
fully confirmed (§4/§7 of `docs/cleanverse-integration.md`). The
analogy is motivated by the shared-`RuleV2`-struct statement, but the
CVA guide does not independently confirm this parameter for its own
`getRulesV2`.

**Return type**: `UNCONFIRMED` for the CVA-side function, for the same
reason. BitV's current declaration (`RuleV2[] memory`) is the same
disclosed inference.

**Visibility / mutability**: `UNCONFIRMED`. BitV's current declaration
(`external view`) is inferred by the same analogy — a read function
mirroring the CVI validator's `external view` `getRulesV2`.

**Return structure**: `UNCONFIRMED` whether the CVA-side `getRulesV2`
returns a flat array (as inferred/assumed), a struct wrapper, or
something else.

**Whether it is token-specific**: Implied by context (the CVA guide
discusses per-token rule management: "admin, by token address") but not
stated as an explicit function-signature fact for `getRulesV2` itself —
**`UNCONFIRMED`** as a precise signature detail, though reasonably
implied.

**Whether it returns active rules only or all rules (including
inactive/expired ones)**: **`UNCONFIRMED`.** Neither guide discusses a
rule-activation/expiration concept at all for either the CVI validator
or the CVA policy interface — there is no documented distinction
between "active" and "inactive" `RuleV2` entries anywhere in the source
material, so this question cannot even be answered as "presumably all
rules" with confidence; it is simply not addressed.

**Conclusion, matching Build 07.1's own disclosure exactly**: the
signature BitV's adapter actually calls
(`getRulesV2(address) external view returns (RuleV2[] memory)`) remains
a **disclosed inference**, not a confirmed fact, and is used only as a
best-effort, read-only interface-shape probe (`BitVCVAAdapter.verifyInterface`)
— never as proof of anything beyond "this contract responded without
reverting to a call shaped this way." Nothing about this changes as a
result of this re-verification pass; no new source material was found
that resolves the remaining `UNCONFIRMED` items above.

## 3. `canTransfer`

**Confirmed**: the function name and its argument list —
`canTransfer(token, from, to, amount)` — per
`docs/cleanverse-integration.md` §5's direct citation from the CVA
guide. Parameter *names* (`token`, `from`, `to`, `amount`) are as given
in that citation; parameter *types* are not independently stated (they
are reasonably inferable as `address, address, address, uint256` by
convention, but the guide's own text does not spell out Solidity types
for this specific function signature).

**Return type**: **`UNCONFIRMED`.** No guide text states whether
`canTransfer` returns `bool`, reverts with structured data, or
something else.

**Visibility**: **`UNCONFIRMED`.**

**Mutability**: **`UNCONFIRMED`** — not stated whether `view`,
`nonpayable`, or otherwise.

**Revert behavior**: **`UNCONFIRMED`.** No text states whether a
non-compliant transfer causes `canTransfer` itself to revert, or
whether it returns a "false" signal that the *token's* `_update` hook
then interprets (and only the hook reverts).

**Return-false behavior**: **`UNCONFIRMED`**, for the identical reason
— it isn't established that `canTransfer` returns a boolean at all,
so "what happens when it returns false" cannot be answered beyond "if
it returns a boolean and that boolean is `false`, *something* in the
gating chain is expected to block the transfer" (per the general
confirmed principle in §1's CVA definition — "every transfer is gated"
— which describes an outcome, not a mechanism).

**Whether it performs state changes**: **`UNCONFIRMED`.** A read-only
compliance check (`view`) would be the more conventional design
(matching the CVI validator's own `complianceVerify`, which is
confirmed `view`), but this is an inference from convention and from
the CVI validator's own confirmed pattern — not an independent
confirmation for `canTransfer` itself.

**Whether it requires CVI data**: Confirmed at the conceptual level
only — "every transfer is gated through CVI compliance verification and
the RuleV2 policy engine" (§1 of `docs/cva-integration-specification.md`,
itself citing the CVA guide). Whether `canTransfer` receives CVI data as
an explicit parameter, looks it up internally (e.g. by calling the CVI
validator itself), or some other mechanism is **`UNCONFIRMED`**.

**Whether RuleV2 is evaluated internally**: Confirmed at the conceptual
level (the CVA policy interface "uses the same RuleV2 struct," and
transfers are described as gated by "the RuleV2 policy engine") but the
*mechanism* by which `canTransfer` specifically evaluates RuleV2
(internally within the same call, via a separate call, synchronously or
otherwise) is **`UNCONFIRMED`**.

**Whether BitV should call it directly before a transfer**:
**Answered by the existing, confirmed "automatic compliance" mode** —
not `UNCONFIRMED`, but resolved in the opposite direction from "BitV
should call it directly." Per `docs/cleanverse-integration.md` §3
(citing the CVI guide §4.5): "compliance checks are performed
automatically by the CVA contract — the business contract does not
need to call the validator explicitly." This is the one piece of
`canTransfer`-adjacent behavior that *is* confirmed: **BitV's own
contracts are not expected to call `canTransfer` directly** — it fires
automatically inside the CVA token's own `_update` hook whenever a
transfer occurs, regardless of who initiates it. This is exactly why
`BitVCVAAdapter.previewTransfer` was built as a boundary function that
reverts rather than as a real call in Build 07.1 — not only because the
return/revert behavior is unconfirmed, but because BitV was never
expected to call it as a pre-transfer check in the first place.

**Conclusion**: no new information resolves any of `canTransfer`'s
unconfirmed signature details. Build 07.1's decision not to declare or
call this function stands confirmed as the correct posture, not merely
a cautious placeholder.

## 4. RuleV2

**Exact structure — fully confirmed, unchanged**, per
`docs/cleanverse-integration.md` §Verification Table / §7 (CVI guide
§3.1), and per `docs/cva-integration-specification.md` §3's citation
that the CVA policy interface "uses the *same* `RuleV2` struct":

```solidity
struct RuleV2 {
    bytes2 allowedGroup;
    bytes2 allowedSubGroup;
    uint8 minTier;
    uint8 minSubTier;
    uint256 poolCountryBitmap;
}
```

**Field ordering**: as listed above, per the CVI guide §3.1's verbatim
struct definition — this is the exact confirmed field order, not a
BitV-chosen convenience ordering.

**Meaning**: `allowedGroup`/`allowedSubGroup` — "Allowed CVI
group"/"Allowed CVI sub-group (empty = no restriction)"; `minTier`/
`minSubTier` — "Minimum CVI tier"/"sub-tier (0 = no restriction)";
`poolCountryBitmap` — "Country bitmap (0 = no restriction)." All
confirmed, CVI guide §3.1, exactly as already implemented in
`contracts/src/interfaces/external/IAPassComplianceValidator.sol`.

**AND behavior within one rule**: Confirmed — "Fields within a single
RuleV2 are AND."

**OR behavior between rules**: Confirmed — "multiple RuleV2s are OR."

**Country bitmap semantics**: Confirmed — "country bitmaps are checked
via bitwise AND."

**How RuleV2 is evaluated during a CVA transfer specifically**: The
struct and its AND/OR/bitwise-AND semantics are confirmed as *general*
`RuleV2` evaluation rules (documented for the CVI validator's
`complianceVerify`), and the CVA guide confirms the CVA policy
interface reuses the identical struct — but **whether `canTransfer`
applies these exact semantics against `from`, `to`, or both transfer
participants is `UNCONFIRMED`** (already flagged identically in
`docs/cva-integration-specification.md` §4, restated here as
unchanged after this re-verification pass: no new source material
resolves it).

## 5. Rule-management functions

`setRuleV2`, `addRuleV2`, `removeRuleV2`,
`setRuleV2FromToken`/`addRuleV2FromToken`/`removeRuleV2FromToken` —
**function names confirmed** (§1 above); **full signatures for every
one of them remain `UNCONFIRMED`**. No parameter list beyond "takes a
`RuleV2`" (for the `set`/`add` variants, by direct textual context —
they manage `RuleV2` entries) is given; no parameter list at all is
given for `removeRuleV2`/`removeRuleV2FromToken` (the CVI validator's
own `removeRuleV2FromContract(uint256 index)` takes an index, but this
is the *CVI validator's* confirmed signature, not independently
confirmed for the CVA policy interface's `removeRuleV2` — inferring the
CVA-side removal function also takes an index, by analogy, would be
exactly the kind of unconfirmed inference this milestone's instructions
forbid, so it is not made here). No return types, visibility, or
mutability are given for any of these six functions.

**Per instruction, none of these are implemented** — `IATokenPolicy.sol`
does not declare any of them, and no BitV contract calls any of them
(these are the CVA *issuer's* rule-management functions; BitV, as a
CVA *consumer*, has no occasion to call them regardless of signature
confirmation status).

## 6. CVA verification mechanism

**Question**: does Cleanverse expose an official on-chain method
answering "is this token an officially registered/verified CVA?"

**Searched for** (within the existing transcription — no new source
material to search this milestone): registry contracts, factory
contracts, registration contracts, verification functions, status
functions, token lookup functions.

**Finding: no such method is documented anywhere in either guide.**
The closest confirmed concepts are:

- `isRegistered(address poolAddress)` — but this is a function on the
  **CVI validator** (confirmed, CVI guide §3.2), answering "is this
  *pool/business contract* registered with the CVI validator," not "is
  this *token* a verified CVA." Different question, different contract.
- The CVA guide describes *how a CVA gets registered* (Method A: API
  Launch; Method B: Custom Contract + `POST /api/cooperate/atoken/register`)
  but does not describe a corresponding *query* function or endpoint to
  check registration/verification status after the fact, on-chain or
  off-chain, beyond the vaguely-named "Query Apply Status API"
  (referenced by name only, no path given — `docs/cleanverse-integration.md`
  §5).
- No "CVA registry contract," "CVA factory contract," or "token lookup"
  contract/function is named anywhere in either guide.

**This confirms, unchanged, the central finding already reached in
`docs/cva-integration-specification.md` §2/§7**: BitV cannot verify
Cleanverse's own approval of a token as a CVA on-chain, because no such
query is documented to exist. This re-verification pass does not
discover a previously-missed mechanism — it confirms the absence,
having searched specifically for the categories the task lists.

## 7. CVA freeze / revoke

**Question**: does Cleanverse officially define freeze / unfreeze /
revoke / suspend / disable / de-register for CVA assets?

**Finding: no mechanism is documented for any of these six concepts,
for CVA assets specifically, in either guide.** The one adjacent,
partially-relevant statement (already noted in
`docs/cleanverse-integration.md` §1 and
`docs/cva-integration-specification.md` §1) is about the **CVI
validator**, not CVA tokens: "[the validator] manages per-pool
compliance rules (multiple rules per pool, OR logic), registers CVI
for CVA vaults so they can hold/transfer CVAs, and can pause pools or
freeze accounts (emergency risk control)." This describes:
- Pausing **pools** (business contracts registered with the validator),
  not CVA tokens.
- Freezing **accounts** (presumably wallets/participants), not CVA
  tokens.

Neither of these is "freezing a CVA token" or "revoking a CVA's
verified status" — they are different controls over different objects.
Critically, even for *these* documented controls, `docs/cleanverse-integration.md`
§1 already notes: "Pause/freeze functions were not given exact
signatures in the guide's §3.2 interface list (which is explicitly
scoped to registration, rule management, and compliance verification)
— not implemented, not guessed." This remains true after
re-verification: no function signature for pool-pause or
account-freeze exists in the source material either, let alone for a
CVA-token-specific freeze/revoke.

**Conclusion: `UNCONFIRMED` in full** — no freeze, unfreeze, revoke,
suspend, disable, or de-register mechanism for CVA assets is documented
to exist at all, and the one adjacent (pool/account-level) control
mentioned has no confirmed signature either. This matches
`docs/cva-integration-specification.md` §1/§12's existing conclusion
exactly; nothing new is found.

## 8. CVA registration

Re-verified against `docs/cleanverse-integration.md` §3/§5, separated
exactly as the task requests:

| Stage | Confirmed? | Detail |
|---|---|---|
| **API Launch** (Method A) | ✅ Confirmed to exist | `POST /api/cooperate/atoken/launch` — Cleanverse deploys the token contract from the request. Body's `data` field is AES/CBC/PKCS5Padding-encrypted then base64-encoded; `api-id` and `X-Request-ID` headers are set. Full request/response schema beyond this is `UNCONFIRMED`. |
| **Custom CVA contract** (Method B) | ✅ Confirmed to exist | Issuer deploys their own ERC-20 implementing `IATokenPolicy`, calling `policy.canTransfer(...)` in `_update`. |
| **Register** | ✅ Confirmed to exist (Method B) | `POST /api/cooperate/atoken/register` — `owner_signature` = EIP-191 `personal_sign` over `lowercase(chain + atoken_address)`, confirmed for this endpoint specifically. |
| **Review** | ❌ `UNCONFIRMED` | No review criteria, checklist, or process description exists in either guide. |
| **Approval** | ❌ `UNCONFIRMED` | No explicit "approval" step, timeline, or criteria is documented distinct from the registration call itself succeeding. |
| **Activation** | ❌ `UNCONFIRMED` | No distinct "activation" step (separate from registration/deployment) is documented. |

**What BitV can verify on-chain vs. what requires Cleanverse's
off-chain confirmation** — restated, unchanged from
`docs/cva-integration-specification.md` §2:
- **On-chain, BitV-verifiable**: whether a given contract address
  implements the (partially confirmed) `IATokenPolicy` call surface —
  i.e., whether it responds to a call shaped like `getRulesV2` (§2's
  disclosed-inference caveat applies).
- **Off-chain, Cleanverse-only**: whether that same contract was
  actually reviewed/approved/registered by Cleanverse as a genuine CVA
  — no on-chain query for this exists (§6), and the review/approval
  process itself is entirely undocumented (this section's table above).

## 9. Cleanverse deployments

**Question**: does official documentation provide deployed addresses
for the CVI validator, CVA policy, CVA registry, CVA factory, or any
other contract BitV would need?

**Finding: no address is given for any of these, on any network,
anywhere in either guide.** Restated directly from
`docs/cleanverse-integration.md` §7/§Deployment Readiness (unchanged,
re-confirmed this milestone, no new search performed since no new
source material exists to search):

- **CVI validator (`IAPassComplianceValidator`) deployed address**:
  `UNCONFIRMED` — not given for any network.
- **CVA policy contract address(es)**: **Not applicable in the form
  asked** — CVA tokens are per-issuer, freshly deployed via the Launch/
  Register flow (§8 above), not pre-deployed at a fixed, reusable
  address. There is no single "the CVA policy contract" to have an
  address for; each issued CVA (or its policy contract, under Method B)
  is its own deployment.
- **CVA registry contract address**: **Not applicable** — no such
  contract is documented to exist at all (§6).
- **CVA factory contract address**: **Not applicable** — no CVA-issuing
  factory contract (distinct from the API-driven Method A "Launch"
  flow) is documented.
- **No addresses were invented anywhere in this document or in the
  existing implementation** — `BitVCVAAdapter`'s `_policyContract`
  mapping is populated per-token by `RWA_ADMIN_ROLE` at configuration
  time, never pre-seeded with any address.

## 10. Monad support

**Searched (within the existing transcription) for**: "Monad," "Monad
Testnet," explicit chain support, chain ID, and deployment addresses on
Monad — restated, unchanged, from
`docs/cleanverse-integration.md`'s own prior, already-thorough
re-search (Build 02.6): "the string 'Monad' does not appear anywhere in
either PDF." No new search was performed this milestone because no new
source material exists to search against — re-stating a prior finding
from unchanged source material is not the same as re-confirming it
against new evidence, and this document does not claim the latter.

- **Whether Monad is supported**: `UNCONFIRMED`. The CVA guide's only
  network statement lists "Ethereum, Base, BSC, Arbitrum, Polygon,
  etc." — Monad is absent from the explicit list; the trailing "etc."
  neither confirms nor rules it out. The CVI guide gives no network
  list at all.
- **Whether Monad Testnet is supported**: `UNCONFIRMED`, for the same
  reason — testnets aren't distinguished from mainnets in either
  guide's (already sparse) network discussion.
- **Expected chain ID**: `UNCONFIRMED` — no chain ID is given for any
  network in either guide, Monad or otherwise.
- **Any Cleanverse deployment addresses on Monad**: `UNCONFIRMED` — see
  §9; no addresses are given for any network.
- **Third-party registries were not consulted** for this section, per
  instruction — only the two official PDFs (via the existing
  transcription) were used.

## 11. Registration signature

Re-checked, kept explicitly separate as instructed:

**CVI validator registration** (`POST /api/cooperate/validator/register`,
CVI guide §5.4):
- **Hash construction**: Confirmed — `keccak256(chain + contract_address)`,
  lowercase hex concatenation. This is the *only* thing §5.4 states.
- **Signing algorithm**: `UNCONFIRMED` — the guide does not state what
  algorithm actually produces a signature *over* that keccak256 hash
  (raw ECDSA over the hash directly? the hash wrapped as an EIP-191
  personal-sign message? something else?).
- **Message format**: `UNCONFIRMED` beyond the hash-construction rule
  above.
- **Encoding**: `UNCONFIRMED`.
- **Required request fields**: `UNCONFIRMED` — no field name (e.g.
  whether the signature is carried in a field called `owner_signature`,
  as the *CVA* guide's endpoint uses, or something else) is given for
  this specific endpoint.
- **Whether EIP-191/`personal_sign` is actually specified**: **No — not
  for this endpoint.** This is the exact correction already made in
  Build 02.5 and restated deliberately here per the task's explicit
  instruction not to let it silently reappear: an earlier draft of
  `docs/cleanverse-integration.md` incorrectly asserted the CVI
  validator's registration signature scheme was "the same" as the CVA
  guide's EIP-191 `personal_sign` scheme. The CVI guide never says
  this. Re-verified again this milestone: still true, still corrected,
  still not EIP-191/`personal_sign` as far as the source material
  confirms.

**CVA registration** (`POST /api/cooperate/atoken/register`, CVA guide
"Step 2") — **kept separate, not merged**:
- **Hash construction**: `lowercase(chain + atoken_address)`.
- **Signing algorithm**: **EIP-191 `personal_sign`** — explicitly
  confirmed, but **only for this endpoint**.
- **Message format**: the lowercase concatenation above, signed via
  `personal_sign`.
- **Encoding**: Not further specified beyond "lowercase" concatenation.
- **Required request fields**: `owner_signature` — confirmed, named
  explicitly for this endpoint.

**These are two separate, only partially-specified schemes — restated
explicitly, per instruction, not to be treated as identical.** The CVI
validator's scheme is missing the actual signing algorithm; the CVA
registration's scheme has a confirmed algorithm (EIP-191 `personal_sign`)
but that confirmation does not transfer to the CVI validator's endpoint.

## 12. API surface

Every officially-named Cleanverse API BitV's integration touches or
would touch, per the existing transcription (`docs/cleanverse-integration.md`
§5) — re-verified, unchanged:

| Method | Path | Auth | Required params (confirmed only) | Response | Errors | Purpose | BitV need |
|---|---|---|---|---|---|---|---|
| POST | `/api/cooperate/validator/grant` | `UNCONFIRMED` scheme | `UNCONFIRMED` | `UNCONFIRMED` | `UNCONFIRMED` | Grant `REGISTER_ROLE` to a Factory address | Not needed — Factory Mode not used by BitV |
| POST | `/api/cooperate/validator/register` | Signature rule only (§11) — full scheme `UNCONFIRMED` | `UNCONFIRMED` beyond the signature | `UNCONFIRMED` | `UNCONFIRMED` | Register a Single-Contract-Mode business contract with the CVI validator | **Needed** — this is the call that makes any deployed BitV contract's `complianceVerify` meaningful; still blocked on the unconfirmed signing algorithm |
| POST | `/api/cooperate/atoken/launch` | AES/CBC/PKCS5Padding-encrypted body, `api-id` + `X-Request-ID` headers | `chain`/`atoken_address`/`atoken_icon`/`owner_signature`/`callback_url` named (CVA guide's token-config table); full schema `UNCONFIRMED` | `UNCONFIRMED` | `UNCONFIRMED` | Launch a new CVA (Method A) | Not needed this milestone — BitV is a CVA consumer, not issuer |
| POST | `/api/cooperate/atoken/register` | `owner_signature` = EIP-191 `personal_sign` over `lowercase(chain + atoken_address)` (confirmed) | Same named fields as launch | `UNCONFIRMED` | `UNCONFIRMED` | Register a self-deployed CVA contract (Method B) | Not needed this milestone — BitV isn't issuing a CVA |
| — | "Query Apply Status API" | `UNCONFIRMED` | `UNCONFIRMED` | `UNCONFIRMED` | `UNCONFIRMED` | Poll CVA verification status | Referenced by name only, no path — would be directly relevant to §6/§8 if it existed with a real path, but it cannot be called without one |
| — | "Query Supported CVA List" | `UNCONFIRMED` | `UNCONFIRMED` | `UNCONFIRMED` | `UNCONFIRMED` | Look up e.g. AccessCore's address for `MINTER_ROLE` grants | Referenced by name only, no path |
| — | "Add CVA Rule API" | `UNCONFIRMED` | `UNCONFIRMED` | `UNCONFIRMED` | `UNCONFIRMED` | Append a RuleV2 to a CVA off-chain instead of calling `addRuleV2` directly | Referenced by name only, no path |

**No missing detail in this table is invented** — every `UNCONFIRMED`
cell reflects a genuine absence in the source material, not an
oversight in transcription.

## 13. Final dependency table

| Requirement | Confirmed | Exact source | BitV impact |
|---|---|---|---|
| `IATokenPolicy`/`IComplianceRule` exists as the CVA policy interface | CONFIRMED | CVA guide, per `docs/cleanverse-integration.md` §3 | Basis for `BitVCVAAdapter`'s entire design |
| CVA policy interface uses the same `RuleV2` struct as the CVI validator | CONFIRMED | CVA guide, §3 | Basis for `IATokenPolicy.sol`'s `RuleV2` definition and the `getRulesV2` inference |
| `canTransfer(token, from, to, amount)` — name + argument list | CONFIRMED | CVA guide, cited §5 | Basis for §5/§6 of `docs/cva-integration-specification.md`; not implemented (return type unconfirmed) |
| `canTransfer`'s return type, visibility, mutability, revert behavior | UNCONFIRMED | — | `BitVCVAAdapter.previewTransfer` deliberately reverts rather than calling it |
| `setRuleV2`/`addRuleV2`/`removeRuleV2`/`*FromToken`/`getRulesV2` — function names | CONFIRMED | CVA guide, §3 | Basis for declaring `getRulesV2` in `IATokenPolicy.sol`; others deliberately not declared |
| `getRulesV2`'s exact signature for the CVA policy interface | UNCONFIRMED (disclosed inference by analogy used) | — | `BitVCVAAdapter.verifyInterface`'s probe is a best-effort, non-authoritative check only |
| "Automatic compliance" mode — CVA transfers self-gate, no redundant BitV-side `complianceVerify` call needed | CONFIRMED | CVI guide §4.5, per `docs/cleanverse-integration.md` §3 | Confirms BitV should NOT call `canTransfer` directly, independent of its unconfirmed signature |
| On-chain "is this token an approved CVA" query | **Does not appear to exist — CONFIRMED ABSENT** | Searched both guides, per §6 | Central limitation motivating the two-flag `adminAttestedCVA`/`isCVAInterfaceVerified` model; neither flag claims Cleanverse approval |
| CVA freeze/revoke/suspend/disable/de-register mechanism | UNCONFIRMED (appears not to exist) | Searched both guides, per §7 | Not implemented; `isCurrentlyUsable`'s interface slot reserved for if/when confirmed |
| CVA registration review/approval/activation process | UNCONFIRMED | — | Cannot verify Cleanverse's actual approval criteria; motivates the admin-attestation-plus-probe model rather than a "verified" claim |
| CVI validator deployed address (any network) | UNCONFIRMED | — | Blocks any real deployment, unrelated to CVA specifically |
| CVA policy/registry/factory contract addresses | NOT REQUIRED (not applicable in the form asked — CVA tokens are per-issuer, not pre-deployed at fixed addresses) | §8/§9 | No address needed or invented |
| Monad / Monad Testnet support | UNCONFIRMED | Re-verified §10, matches Build 02.6's prior finding | Blocks any deployment on Monad, unrelated to CVA specifically |
| Monad chain ID | UNCONFIRMED | — | Same |
| CVI validator registration signing algorithm (beyond the hash rule) | UNCONFIRMED | CVI guide §5.4 | Blocks writing a working registration API client |
| CVA registration (`atoken/register`) signing scheme | CONFIRMED (EIP-191 `personal_sign` over `lowercase(chain + atoken_address)`) | CVA guide "Step 2" | Not needed this milestone — BitV isn't issuing a CVA — but confirmed for completeness and to keep the two schemes explicitly distinct |
| Query Apply Status / Supported CVA List / Add CVA Rule API paths | UNCONFIRMED | Referenced by name only | Cannot be called without a path |
| CVA/validator events | UNCONFIRMED | — | Not referenced anywhere in the implementation |
| `MINTER_ROLE`/AccessCore delegation | CONFIRMED to exist as a concept | CVA guide, §3 | NOT REQUIRED for BitV as a CVA consumer (issuer-side concern only) |

## 14. Implementation decision

**A. Can BitV safely implement real CVA transfer validation
(`canTransfer`) now? — No.** `canTransfer`'s return type, visibility,
mutability, and rejection mechanism are all `UNCONFIRMED` (§3).
Implementing a call to it now would require guessing at least one of
these, which would risk either (a) a call that reverts unexpectedly
against a real CVA token due to a mismatched signature, or (b)
misinterpreting a `false`/non-revert result as permission when it
wasn't intended that way. `BitVCVAAdapter.previewTransfer`'s current
revert-always implementation remains the correct posture.

**B. Can BitV safely verify CVA status on-chain now? — Only partially,
and already implemented exactly to that partial extent.** BitV can
verify (best-effort) that a claimed policy contract *responds* the way
one is expected to (`verifyInterface`'s `getRulesV2` probe) — this is
already implemented (Build 07.1) and remains appropriately labeled as
interface-shape verification, not Cleanverse approval. **Full CVA
status verification (i.e., "is this genuinely Cleanverse-approved") is
not possible on-chain**, because no such query exists (§6) — this is
not a temporary gap to close with more Solidity; it's a structural
absence in what Cleanverse's documented interfaces expose.

**C. Can BitV safely implement CVA freeze/revoke handling now? — No.**
No such mechanism is confirmed to exist (§7). There is nothing to wire
up — implementing "freeze/revoke handling" without a confirmed
Cleanverse-side signal to react to would mean inventing either a fake
Cleanverse mechanism or a purely BitV-side concept mislabeled as
Cleanverse integration. Neither is acceptable per this milestone's
(and Build 07.1's) instructions.

**D. Can BitV safely deploy this integration on Monad Testnet now? —
No.** Monad support itself is unconfirmed (§10), no chain ID is known,
and no Cleanverse contract address exists for any network, let alone
Monad specifically. This is unrelated to CVA-specific readiness — it
is the same, unresolved, pre-existing blocker documented since Build
02.6.

**E. Exact information still required from Cleanverse, consolidated:**
1. `canTransfer`'s full signature (return type, visibility, mutability)
   and its rejection mechanism (revert vs. return value).
2. `getRulesV2`'s exact signature for the CVA policy interface
   specifically (not inferred from the CVI validator's).
3. Full signatures for `setRuleV2`/`addRuleV2`/`removeRuleV2`/
   `*FromToken` (even though BitV doesn't call these as a consumer,
   confirming them would validate the interface-shape probe's
   robustness).
4. Confirmation of whether *any* on-chain "CVA verification status"
   query exists, anywhere in Cleanverse's actual deployed contracts
   (even if undocumented in these two guides).
5. Confirmation of whether any CVA freeze/revoke/suspend mechanism
   exists at all.
6. The CVI validator registration signing algorithm (beyond the
   `keccak256(chain + contract_address)` hash rule).
7. Explicit confirmation (or denial) of Monad/Monad Testnet support,
   a chain ID, and a deployed `IAPassComplianceValidator` address.
8. Full paths and schemas for the Query Apply Status API, Query
   Supported CVA List, and Add CVA Rule API, if BitV ever needs them.

## 15. Whether Build 07.3 can begin

**Not without new Cleanverse source material.** This verification pass
did not resolve any previously-`UNCONFIRMED` item — it confirmed that
every gap already identified in Build 07.1's implementation remains a
genuine gap in the two source PDFs, not an oversight in prior
transcription. A future "Build 07.3" milestone that attempts to
implement real `canTransfer` validation, on-chain CVA-approval
verification, freeze/revoke handling, or Monad deployment would
necessarily have to fabricate at least one of the items in §14.E's
list — which is exactly what this project's own standing instruction
("do not invent Cleanverse functionality") forbids. **Build 07.3 should
wait until new, official Cleanverse material (updated documentation, a
direct answer from Cleanverse, or example/reference contract source)
resolves at least the `canTransfer` signature and the CVI validator
registration/deployment blockers** — the two items that gate the most
implementation work respectively (real transfer validation, and any
real deployment at all).
