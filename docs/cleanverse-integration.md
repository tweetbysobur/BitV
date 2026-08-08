# Cleanverse Integration — BitV Compliance Foundation

**Status: compliance architecture implemented against confirmed primary
sources.** No financial logic, no BitScore calculation, no live Cleanverse
deployment.

## Source-of-truth status

`docs.cleanverse.com` remains network-blocked in every sandbox this
project has run in (`EGRESS_BLOCKED`, confirmed repeatedly, including via
raw `curl`). What unblocked this milestone was the user directly
providing two official PDFs:

1. **"Cleanverse Compliance Protocol (CCP) Integration Guide (For CVI
   Compliance Validator) V2"** — the primary source for everything below
   about `IAPassComplianceValidator`, `RuleV2`, Single-Contract Mode, and
   Factory Mode.
2. **"Cleanverse Compliance Protocol (CCP) CVA Integration Guide"** — the
   primary source for CVA (Cleanverse Verified Asset) issuance, which
   turns out to be a **separate interface** (`IComplianceRule` /
   `IATokenPolicy`) from the CVI validator, not the same contract.

Everything in this document is transcribed or paraphrased from those two
PDFs. Anything not in them is still marked `UNCONFIRMED`. Build 02.5
re-audited the entire implementation line-by-line against these same two
PDFs (no new source material) and found one real error, corrected in §4/§5
below: an earlier version of this document claimed the CVI validator's
registration signature scheme was "the same" as the CVA guide's EIP-191
`personal_sign` scheme — the CVI guide never says that; only the CVA guide
does. Everything else audited (the full `IAPassComplianceValidator`
interface, `RuleV2` field names/types/semantics, `complianceVerify`
behavior, Single-Contract Mode requirements) checked out unchanged against
the source PDFs.

## Verification Table

| Cleanverse Component | Official Definition | BitV Usage | Verified |
|---|---|---|---|
| `IAPassComplianceValidator` | On-chain CVI compliance validator contract, CVI guide §Overview | `BitVComplianceGuard.COMPLIANCE_VALIDATOR` (immutable) | ✅ Confirmed |
| `RuleV2` struct | `bytes2 allowedGroup, bytes2 allowedSubGroup, uint8 minTier, uint8 minSubTier, uint256 poolCountryBitmap`, CVI guide §3.1 | Mirrored exactly in the interface and `services/cleanverse/types.ts` | ✅ Confirmed |
| Rule logic (AND/OR) | "Fields within a single RuleV2 are AND; multiple RuleV2s are OR; country bitmaps are checked via bitwise AND," CVI guide §3.1 | `MockComplianceValidator.complianceVerify` test implementation; real semantics enforced by the real validator, not BitV's contracts | ✅ Confirmed |
| `complianceVerify(address poolAddress, address userAddress) view returns (bool)` | CVI guide §3.2 | `BitVComplianceGuard._requireCompliance` | ✅ Confirmed |
| Registration functions (`registerV2`, `registerApass` ×2, `setRuleV2FromRegistrar`, `isRegistered`) | CVI guide §3.2, `REGISTER_ROLE`-gated | Declared in the interface, not called by BitV's Single-Contract-Mode contracts | ✅ Confirmed (signatures); not exercised |
| Rule-management (`setRuleV2FromContract`/`addRuleV2FromContract`/`removeRuleV2FromContract`/`getRulesV2`) | CVI guide §3.2/§5.2/§6, callable by the business contract itself | `BitVComplianceGuard` owner-gated wrappers | ✅ Confirmed |
| Single-Contract Mode | CVI guide §5: "does not require Factory authorization. Deploy the contract and register it via the API" | Chosen architecture for all of BitV's protected contracts | ✅ Confirmed as the documented, applicable pattern |
| Factory Mode | CVI guide §4: for "multi-pool business (DEX, Launch Pool)" | Not implemented; documented as a future option (§12) | ✅ Confirmed as not currently needed |
| CVA / `IComplianceRule` / `IATokenPolicy` | CVA guide — separate interface (`canTransfer`, not `complianceVerify`) for issuing a compliant token | Not implemented — BitV isn't issuing a CVA this milestone | ✅ Confirmed distinct from the CVI validator |
| Validator registration signing scheme | CVI guide §5.4: `keccak256(chain + contract_address)`, lowercase hex — algorithm/field name not stated | Not implemented (no API client yet) | ❌ UNCONFIRMED (corrected this milestone — see above) |
| Validator's deployed address (any network) | Not given in either guide | `NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS` left empty | ❌ UNCONFIRMED |
| Monad Testnet support | Not named in either guide (CVA guide lists "Ethereum, Base, BSC, Arbitrum, Polygon, etc." — Monad absent from that list, though the guides are chain-agnostic Solidity/API specs) | N/A | ❌ UNCONFIRMED |

## 1. Cleanverse architecture

Two related but distinct systems, both keyed on the shared `RuleV2`
policy structure:

- **CVI (Cleanverse Verified Identity) + `IAPassComplianceValidator`** —
  the on-chain compliance authority a DeFi protocol calls to check
  whether a *user* is compliant for a given *pool/contract*. This is what
  BitV integrates with in this milestone: BitV's pool/lending/vault
  contracts are not CVI issuers, they're `complianceVerify` callers.
- **CVA (Cleanverse Verified Asset) + `IComplianceRule`/`IATokenPolicy`**
  — a separate primitive for *issuing a compliant ERC20 token itself*
  (e.g. a stablecoin or RWA token), where every transfer is
  automatically gated via `canTransfer(token, from, to, amount)`. BitV is
  not issuing its own CVA token in this milestone — RWA-backed lending
  would eventually *hold* CVA tokens as collateral, not issue them — so
  `IATokenPolicy` is documented here for completeness (§3) but not
  implemented in `contracts/`.

The validator "manages per-pool compliance rules (multiple rules per
pool, OR logic), registers CVI for CVA vaults so they can hold/transfer
CVAs, and can pause pools or freeze accounts (emergency risk control)."
Pause/freeze functions were not given exact signatures in the guide's
§3.2 interface list (which is explicitly scoped to registration, rule
management, and compliance verification) — not implemented, not guessed.

## 2. Identity (CVI) — partially confirmed

Confirmed: CVI is Cleanverse's identity primitive; a user's CVI carries a
**Group**, **Sub-Group**, **Tier**, and **Sub-Tier**, checked by
`complianceVerify` against a pool's registered `RuleV2` set, plus a
country dimension checked via `poolCountryBitmap`.

**Still unconfirmed** (not in either guide): how a user obtains/proves a
CVI in the first place (the actual KYC/verification flow a wallet goes
through), CVI expiration/revocation behavior, and any off-chain
identity-status lookup API. `services/cleanverse/client.ts` stays a
throwing stub for identity lookups.

## 3. Verified Assets (CVA)

Confirmed from the CVA guide:

- CVA is "the native compliant asset standard of the Cleanverse
  Compliance Protocol (CCP)... issued directly on Cleanverse by qualified
  issuers, and every transfer is gated through CVI compliance
  verification and the RuleV2 policy engine."
- Two issuance paths: **Method A (API Launch)** — Cleanverse deploys the
  token contract from a `POST /api/cooperate/atoken/launch` request;
  **Method B (Custom Contract Template)** — you deploy your own
  ERC20 (upgradeable or not) implementing `IATokenPolicy`, calling
  `policy.canTransfer(...)` in `_update`, then register it via
  `POST /api/cooperate/atoken/register` (owner-signed).
- CVA's policy interface (`IComplianceRule`/`IATokenPolicy`) uses the
  *same* `RuleV2` struct as the CVI validator, but its own function names:
  `canTransfer`, `setRuleV2`/`addRuleV2`/`removeRuleV2` (admin, by token
  address), `setRuleV2FromToken`/`addRuleV2FromToken`/`removeRuleV2FromToken`
  (token calling on its own behalf), `getRulesV2`.
- Optional `MINTER_ROLE` grant lets a platform contract (e.g. Cleanverse's
  "AccessCore") mint/burn CVA on the issuer's behalf.

**How BitV should use CVA vs. direct `complianceVerify` calls** (per the
CVI guide §4.5/§4.6, which describes this from the *consuming pool's*
side, not the issuer's side):

| Mode | When | Mechanism |
|---|---|---|
| **CVA automatic compliance** | BitV holds/transfers an existing CVA (e.g. a Cleanverse-issued stablecoin) as a pool asset or RWA collateral | The CVA token's own `_update` hook already calls compliance checks on every transfer — BitV's contract does **not** need its own `complianceVerify` call for that asset leg, per §4.5: "compliance checks are performed automatically by the CVA contract — the business contract does not need to call the validator explicitly." BitV would still call `registerApass(pool, aTokenAddress, feeAddress)` (Factory-mode) or rely on the CVA already being registered, to let the pool hold/transfer it. |
| **Direct `complianceVerify` calls** | Native ERC20 trading pairs, or any BitV-defined access gate (e.g. "can this wallet call `borrow()` at all") | What's implemented in this milestone: `BitVComplianceGuard._requireCompliance` calls `complianceVerify(address(this), user)` explicitly before every protected action. |

**Do not label any BitV asset as CVA** until it is actually issued via one
of the two confirmed paths above (registered with Cleanverse, backed by a
real `IATokenPolicy`-implementing contract) — no CVA assets, fake or real,
exist in this milestone.

## 4. Authentication

**Confirmed, on-chain side:** `complianceVerify` is a permissionless
`view` call — no auth needed to *check* compliance. Rule-management calls
(`registerV2`, `registerApass`, `setRuleV2FromRegistrar`) require the
caller to hold `REGISTER_ROLE` on the validator, granted by Cleanverse via
an off-chain API call (`POST /api/cooperate/validator/grant`, Factory
Mode) — BitV's own Single-Contract-Mode contracts never hold
`REGISTER_ROLE` themselves; they call `setRuleV2FromContract` /
`addRuleV2FromContract` / `removeRuleV2FromContract`, which the guide
states the business contract calls "itself" (no special role needed
beyond being the registered pool).

**Confirmed, off-chain API side — these are two separate, only
partially-specified schemes; do not assume they're identical:**
- **CVA registration** (`POST /api/cooperate/atoken/register`, CVA guide
  §"Step 2"): field `owner_signature`, explicitly documented as "EIP-191
  `personal_sign` signature over `lowercase(chain + atoken_address)`."
- **Validator registration** (`POST /api/cooperate/validator/register`,
  CVI guide §5.4): documented only as "Signature Rule:
  `keccak256(chain + contract_address)`, lowercase hex concatenation."
  The CVI guide does **not** say this is EIP-191 `personal_sign`, does
  not name a request field (no confirmed `owner_signature` field for this
  endpoint — that name only appears in the CVA guide), and doesn't state
  what's actually signed with that hash (raw ECDSA over the hash? the hash
  as an EIP-191 message?). An earlier version of this document incorrectly
  asserted these two schemes were "the same" — corrected in Build 02.5;
  treat the validator-registration signing mechanism as **UNCONFIRMED**
  beyond "some signature covering `keccak256(chain + contract_address)`."
- Launch CVA API (`POST /api/cooperate/atoken/launch`): request body's
  `data` field is AES/CBC/PKCS5Padding-encrypted, then base64-encoded;
  `api-id` and `X-Request-ID` headers are set.

**Still unconfirmed:** the exact signing/hashing algorithm for validator
registration (see above), the API key/`api-id` provisioning process
itself, full request/response schemas beyond the fields listed in §5, and
webhook/callback (`callback_url`) payload verification.

**Never expose client-side:** any Cleanverse API key/credential used for
the AES encryption or signing above. `.env.example` keeps
`CLEANVERSE_API_KEY` / `CLEANVERSE_API_BASE_URL` private, server-only.

## 5. API — confirmed endpoints (from both guides)

| Method | Path | Purpose | Auth | Notes |
|---|---|---|---|---|
| POST | `/api/cooperate/validator/grant` | Grant `REGISTER_ROLE` to a Factory address | Off-chain (unspecified scheme) | Factory Mode only — not used by BitV's Single-Contract Mode |
| POST | `/api/cooperate/validator/register` | Register a Single-Contract-Mode business contract with the validator | Signature rule only: `keccak256(chain + contract_address)`, lowercase hex concatenation — signing algorithm and request field name **UNCONFIRMED** (see §4) | **This is the call BitV needs** before any deployed BitV contract's `complianceVerify` will do anything meaningful |
| POST | `/api/cooperate/atoken/launch` | Launch a new CVA (Method A) | AES/CBC/PKCS5Padding-encrypted body, `api-id` + `X-Request-ID` headers | Not used by BitV this milestone (BitV isn't issuing a CVA) |
| POST | `/api/cooperate/atoken/register` | Register a self-deployed CVA contract (Method B) | `owner_signature` = EIP-191 `personal_sign` over `lowercase(chain + atoken_address)` (confirmed for **this** endpoint only) | Not used by BitV this milestone |
| — | Query Apply Status API | Poll CVA verification status | UNCONFIRMED — path not given | Referenced by name only |
| — | Query Supported CVA List | Look up e.g. AccessCore's address for `MINTER_ROLE` grants | UNCONFIRMED — path not given | Referenced by name only |
| — | Add CVA Rule API | Append a RuleV2 to a CVA off-chain instead of calling `addRuleV2` directly | UNCONFIRMED — path not given | Referenced by name only |

Request/response body schemas beyond the fields explicitly listed (token
config table in the CVA guide; `chain`/`atoken_address`/`atoken_icon`/
`owner_signature`/`callback_url` for registration) were not given, so no
TypeScript request/response types were written for these — `services/
cleanverse/client.ts` does not call any of them yet.

## 6. SDK

No JS/TS SDK package name was given in either guide — both describe raw
HTTP APIs and Solidity interfaces only. `services/cleanverse/client.ts`
does not import any `@cleanverse/*` package.

## 7. Blockchain

| Item | Value | Status |
|---|---|---|
| Explicit Monad Testnet support | Not stated by either guide. The CVA guide's "Supported networks" line names "Ethereum, Base, BSC, Arbitrum, Polygon, etc." — Monad is absent from that explicit list (though "etc." and the guides' network-agnostic Solidity/API design leave it plausible). The CVI guide states no network list at all. | **UNCONFIRMED** — do not assume Monad Testnet support without asking Cleanverse directly |
| Chain ID | Not given by either guide for any network, including Monad | **UNCONFIRMED** |
| Contract | `IAPassComplianceValidator` | **Fully implemented** — `contracts/src/interfaces/external/IAPassComplianceValidator.sol`, transcribed from the CVI guide §3.2 |
| Deployed validator address (any network, including Monad Testnet) | — | **UNCONFIRMED** — `NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS` left empty; no address invented |
| CVA contract addresses | — | **UNCONFIRMED** — not applicable yet (BitV isn't issuing/holding a named CVA) |
| `RuleV2` fields | `bytes2 allowedGroup, bytes2 allowedSubGroup, uint8 minTier, uint8 minSubTier, uint256 poolCountryBitmap` | **Confirmed**, verbatim from CVI guide §3.1 |
| Validation logic | Fields within one `RuleV2`: AND. Multiple `RuleV2`s: OR. Country bitmaps: bitwise AND. | **Confirmed** |
| Registration functions (`REGISTER_ROLE`) | `registerV2`, `registerApass` (2 overloads), `setRuleV2FromRegistrar`, `isRegistered` | **Confirmed**, declared in the interface; not called by BitV's Single-Contract-Mode contracts |
| Rule-management functions (business contract) | `setRuleV2FromContract`, `addRuleV2FromContract`, `removeRuleV2FromContract`, `getRulesV2` | **Confirmed and implemented** — exposed as owner-gated wrappers on `BitVComplianceGuard` |
| Compliance check | `complianceVerify(address poolAddress, address userAddress) view returns (bool)` | **Confirmed and implemented** |
| CVA policy interface | `IComplianceRule.RuleV2` (identical fields), `IATokenPolicy.canTransfer/setRuleV2/addRuleV2/removeRuleV2/setRuleV2FromToken/addRuleV2FromToken/removeRuleV2FromToken/getRulesV2` | **Confirmed, not implemented** (BitV isn't issuing a CVA yet — see §3) |
| Events | — | **UNCONFIRMED** — neither guide lists validator/CVA events |
| ABI | Derived from the interface above | Matches the guide's declared function signatures; still not a Cleanverse-published ABI JSON |

## 8. BitV Mapping

| Cleanverse primitive | BitV module | Purpose | Implementation this milestone |
|---|---|---|---|
| `IAPassComplianceValidator.complianceVerify` | `BitVComplianceGuard` (shared base) | Gate every protected action behind CVI compliance | **Implemented** — `contracts/src/compliance/BitVComplianceGuard.sol` |
| `IAPassComplianceValidator.{set,add,remove}RuleV2FromContract`, `getRulesV2` | `BitVComplianceGuard` owner-gated wrappers | Let BitV's own governance manage each contract's RuleV2 set | **Implemented** |
| `RuleV2` | Off-chain mirror in `services/cleanverse/types.ts` | UI/off-chain reasoning about eligibility criteria | Type mirror only, no reads wired up yet |
| CVA + `IATokenPolicy` (conceptual) | Future RWA collateral path in `BitVLendingManager` | Skip redundant per-tx checks for pre-verified CVA collateral (§3 table) | Documented, not implemented |
| BitScore (BitV-native, **not** Cleanverse) | `BitScoreManager` | Borrowing limits, LTV, interest tier, pool eligibility, yield access | Skeleton only, explicitly out of scope this milestone |

## 9. BitV User Flow

```
Connect wallet
  → (UNCONFIRMED) User completes CVI verification with Cleanverse
    (off-platform flow — not specified in either guide)
  → BitV reads ComplianceStatus (loading → eligible | ineligible |
    verification-required | error) — UI types exist, no real read wired up
  → BitV access decision: user calls a protected action on a BitV
    contract → BitVComplianceGuard._requireCompliance() →
    IAPassComplianceValidator.complianceVerify(address(this), user)
  → If false: revert ComplianceErrors.ComplianceCheckFailed(pool, user) —
    no state change
  → If true: BitScore (BitV-native, separate from Cleanverse) determines
    borrowing limits / tier / eligibility — NOT implemented this milestone
  → Protocol interaction (pool/lending/vault/RWA action) — stubs revert
    NotImplemented after the compliance check passes
  → Verified asset settlement: if the asset involved is CVA, its own
    transfer hook re-checks compliance automatically (§3); if native
    ERC20, BitV's own complianceVerify call is the only check — NOT
    implemented (no economics yet)
```

## 10. Security

- **Compliance check runs first, always.** Every protected function in
  `BitVPoolManager` / `BitVLendingManager` / `BitVVaultManager` calls
  `_requireCompliance(msg.sender)` as its first line.
- **Validator address is immutable**, rejects `address(0)` at
  construction, no setter — matches the guide's Single-Contract-Mode
  template pattern ("Store the validator address (immutable)").
- **Rule-management functions are `onlyOwner`-gated** on
  `BitVComplianceGuard`, per the guide's explicit instruction: "Access
  Control: The business contract should enforce `onlyOwner` or
  `AccessControl` on rule management methods."
- **Off-chain registration is a prerequisite, not a contract-level
  concern**: a deployed BitV contract's `complianceVerify` calls will
  simply return however the (unregistered) validator answers until
  someone calls `POST /api/cooperate/validator/register` with a valid
  signature over `keccak256(chain + contract_address)` for that contract
  (exact request field/algorithm UNCONFIRMED — see §4) — this is an
  operational/deployment step, not something Solidity code can enforce.
- **API key handling / AES encryption / signature verification** on the
  Cleanverse API side — the schemes are named (§4) but full
  implementation detail (key management, IV handling) wasn't given;
  `services/cleanverse` doesn't call these APIs yet, so none of this is
  implemented.
- **Identity spoofing / asset verification** — entirely Cleanverse's
  responsibility; BitV only trusts `complianceVerify`'s boolean answer
  for the immutable validator address it was constructed with.
- **Server-side validation** — `CLEANVERSE_API_KEY` / `CLEANVERSE_API_BASE_URL`
  stay non-`NEXT_PUBLIC_`, never bundled to the client.

## 11. Environment Variables

| Variable | Category | Notes |
|---|---|---|
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | Public frontend | WalletConnect/RainbowKit |
| `NEXT_PUBLIC_MONAD_TESTNET_RPC_URL` | Blockchain (public) | No hardcoded fallback in code |
| `NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS` | Blockchain (public) | Contract address, not a secret; UNCONFIRMED — leave empty until BitV's validator instance/registration is confirmed on Monad Testnet |
| `CLEANVERSE_API_KEY` | Cleanverse credential (private) | UNCONFIRMED exact name/format; used for whatever `api-id`/signing scheme backs the Launch/Register APIs |
| `CLEANVERSE_API_BASE_URL` | Cleanverse credential (private) | UNCONFIRMED |

## 12. Single-Contract Mode vs. Factory Mode

**Confirmed from the guide's own comparison table (§"Choosing an
Integration Mode"):**

| Scenario | Mode | Notes (verbatim) |
|---|---|---|
| Single business contract (lending, staking, NFT) | Single-contract mode | "Local deployment, no Factory authorization required" |
| Multi-pool business (DEX, Launch Pool) | Factory mode | "One authorization, batch management of multiple pools" |

BitV MVP uses **Single-Contract Mode**, which the guide itself frames as
matching BitV's exact shape ("lending... verify borrower CVI to filter
compliant borrowers" is one of its listed use cases). Each of BitV's
protocol contracts (`BitVPoolManager`, `BitVLendingManager`,
`BitVVaultManager`) is deployed once, then individually registered with
Cleanverse (`POST /api/cooperate/validator/register`) and self-manages
its own `RuleV2` set via the owner-gated wrappers on
`BitVComplianceGuard`.

**Factory Mode is not implemented.** If BitV later needs many
independently registered pools (the guide's own trigger: "DEX pools" or
"Launch Pool: create a separate pool for each new project"), the
architecture stays extensible: a `DexLaunchFactory`-style contract
(holding `REGISTER_ROLE`, calling `registerV2`/`registerApass` on pool
creation — the guide provides a full template for this) would sit
alongside, not replace, `BitVComplianceGuard`'s pattern — the compliance
*check* (`complianceVerify`) works identically either way; only *who
registers the rules* changes.
