# BitV Cleanverse Dependency Lock (Build 10)

No new Cleanverse functionality is implemented by this milestone. This
is a final, consolidated lock-file of exactly what's confirmed, what
isn't, and what's needed next — built from the two official Cleanverse
PDFs already in hand (per `docs/cleanverse-integration.md`,
`docs/cleanverse-integration-todo.md`, and Build 09's audit), with no new
inference performed here.

| Requirement | Status | Required for | Source | Next action |
|---|---|---|---|---|
| CVI validator address (Monad Testnet) | **CONFIRMED (Build 11) — `0xaC7e5179C2C7f03f209136886c172eb34F161792`** | Deployed `BitVPoolManager`/`BitVLendingManager` — used in both constructors and confirmed consistent by `ValidateDeployment.s.sol` | BitV team, direct confirmation (not independently verified against `docs.cleanverse.com` — that domain remains network-blocked from this sandbox) | None — recorded in `docs/deployment-addresses-template.md` |
| Official Monad Testnet support | **CONFIRMED (Build 11) — primary source.** Cleanverse's live Gateway API docs (`docs.cleanverse.com`, Cooperate API, `generate_apass`'s `wallet.chain` enum) explicitly list `monad` as a supported chain. | The above | Live Cleanverse API reference (Cooperate API "A-Pass Management" module), viewed directly by the BitV team 2026-08-09 | None — the official PDFs' text is simply stale relative to the live API |
| Chain ID Cleanverse expects for Monad | **UNCONFIRMED still** — the API addresses chains by name (`"monad"`), not numeric chain ID, in every schema reviewed | Validator registration | Live Cooperate API docs | No action needed — registration in practice used the chain name, not a numeric ID, and succeeded |
| `CLEANVERSE_API_BASE_URL` (sandbox) | **CONFIRMED** — `https://uatapi.cleanverse.com/api/cooperate` | Every Cooperate API call | Live Cooperate API docs, "Environment" section | None. Production is `https://api.cleanverse.com/api/cooperate` — not used this milestone (sandbox only) |
| `api-id` / `api-key` credential model | **CONFIRMED** — two separate credentials: `api-id` (sent as a request header, identifies the app) and `api-key` (Base64-encoded, used only locally to derive the AES-CBC/PKCS5Padding encryption key with a fixed 16-zero-byte IV, never transmitted) | Every encrypted Cooperate API endpoint | Live Cooperate API docs, "Authentication"/"Encryption" sections | None — BitV has a sandbox `api-id`/`api-key` pair and used both successfully |
| `POST /generate_apass` (CVI/A-Pass issuance) | **CONFIRMED, used successfully (Build 11)** — issued a real sandbox A-Pass for the deployer wallet (`0xa26ee13a084c756a3a44dda68f0547a1e654fb81`) on chain `monad` | Giving a wallet a CVI so `complianceVerify` can ever return true for it | Live Cooperate API docs, "A-Pass Management" section; executed via the sandbox API, response `code: 0000` | None — this is how BitV (or any partner) issues a CVI in practice |
| `POST /validator/register` (pool/contract compliance registration) | **CONFIRMED, used successfully (Build 11)** — registered both `BitVPoolManager` and `BitVLendingManager` as compliance pools on `monad`, each with an initial unrestricted `Rule` object and an EIP-191 `owner_signature` over `chain + contract_address` | Making `complianceVerify(poolAddress, userAddress)` evaluate anything instead of always failing closed | Live Cooperate API docs, "Validator Compliance" section; executed via the sandbox API, response `code: 0000` for both contracts | None for these two contracts — repeat per additional compliance-gated contract (e.g. a future `BitVYieldVault`) |
| Compliance Rule object schema | **CONFIRMED** — `allowed_group`, `allowed_sub_group` (string, empty = unrestricted), `min_tier`, `min_sub_tier` (integer 0-99, 0 = unrestricted), `is_black_list` (bool, optional), `countries` (array of ISO 3166-1 alpha-2, optional) | `/validator/register`, `/validator/set_rule`, `/validator/add_rule` | Live Cooperate API docs | None |
| `IAPassComplianceValidator.complianceVerify` | **CONFIRMED**, implemented | The sole on-chain eligibility gate for every protected BitV action | CVI Integration Guide V2 §3.2, transcribed verbatim in `IAPassComplianceValidator.sol` | None — already correct |
| `RuleV2` struct / rule-management functions (CVI side) | **CONFIRMED**, implemented | Compliance rule configuration | CVI guide §3.1/§5.2/§6 | None — already correct |
| `BitVCVAAdapter` (BitV's own contract) | **CONFIRMED as implemented, unchanged this milestone** | Being the single boundary for any CVA-specific on-chain call | `docs/cva-integration-specification.md`, `contracts/src/core/BitVCVAAdapter.sol` | None required — this milestone did not touch it, per the instruction that the adapter must remain unchanged unless a confirmed official interface requires a correction (none surfaced) |
| `canTransfer` (CVA policy interface) | **CONFIRMED (Build 11)** — `function canTransfer(address token, address from, address to, uint256 amount) external view returns (bool);` | CVA transfer enforcement — still NOT implemented this milestone, per Build 11's explicit "do not implement CVA transfer enforcement" | CVA Integration Guide's `IATokenPolicy` interface listing (PDF supplied 2026-08-08), superseding the earlier "unconfirmed return type/visibility" note in `docs/cva-integration-specification.md` | Implementation is a decision for a future, explicitly-scoped build — not performed here despite the signature now being confirmed |
| `getRulesV2` (CVA policy interface) | **PARTIALLY CONFIRMED** | `BitVCVAAdapter.verifyInterface`'s read-only probe | Function name/role confirmed by the CVA guide; this specific signature (`getRulesV2(address token) external view returns (RuleV2[] memory)`) is a disclosed, reasonable inference by analogy to the CVI side's confirmed identical-shaped function, not independently confirmed by the CVA guide's own text | No action required to keep using it as a probe (already disclosed); ask Cleanverse to independently confirm the exact signature before relying on it for anything beyond a best-effort probe |
| CVA "official approval" query (an on-chain fact that Cleanverse has approved a specific token as a CVA) | **NOT AVAILABLE / structurally unconfirmed** | Any claim stronger than "this contract responds the way a CVA policy contract is expected to" | Neither guide describes an on-chain query for Cleanverse's own approval decision | None currently possible — `BitVRWACollateralRegistry`/`BitVCVAAdapter`/the dashboard already avoid ever claiming this (see `CVA_RECOGNITION_DISCLAIMER`, Build 08) |
| CVA freeze/revoke | **UNCONFIRMED** | Any future handling of a revoked/frozen CVA | Not described by either guide's confirmed interface surface | Ask Cleanverse; do not implement speculatively |
| CVA rule-management functions (`setRuleV2`/`addRuleV2`/`removeRuleV2` and the `FromToken` variants) | **CONFIRMED as names only** | The token issuer's own administration — not something BitV calls | CVA guide names them; full parameter/return signatures not confirmed, and BitV has no reason to call them (they belong to whoever issues the CVA token, not BitV) | None — out of BitV's authority/intent to call regardless of confirmation status |

## What did not change this milestone

- `BitVCVAAdapter.previewTransfer` still reverts unconditionally
  (`CVAErrors.TransferValidationUnconfirmed()`) — not touched, not
  bypassed.
- No new function was added to `IAPassComplianceValidator.sol` or
  `IATokenPolicy.sol`.
- No Cleanverse address (validator, CVA policy, or otherwise) was
  invented — every value in this table (validator address, chain
  support, API base URL, credential model, registration process) came
  either from the BitV team's direct confirmation or Cleanverse's own
  live API documentation, viewed and quoted directly.

## Sandbox compliance registrations on record (Build 11)

| Contract | Address | Cleanverse registration | Rule |
|---|---|---|---|
| `BitVPoolManager` | `0x46f89aeee3af4c77c2c77ad3b05412404100cc93` | Registered via `POST /validator/register`, sandbox, `monad` | Unrestricted (`min_tier: 0`, no group/country constraint) |
| `BitVLendingManager` | `0x9e1b4a5e49186b732265fea4388f3f16b303decf` | Registered via `POST /validator/register`, sandbox, `monad` | Unrestricted (`min_tier: 0`, no group/country constraint) |

Deployer wallet `0xa26ee13a084c756a3a44dda68f0547a1e654fb81` holds a
sandbox A-Pass (customer ID `BITVDEPLOYER01`) issued via
`generate_apass`. `complianceVerify` confirmed returning `true` for
this wallet against both registered contracts, directly via
`cast call` against the live Monad Testnet validator
(`0xaC7e5179C2C7f03f209136886c172eb34F161792`).

**This is a sandbox (UAT) registration, not production.** Before any
real-value deployment, equivalent registration must happen against
Cleanverse's production API (`https://api.cleanverse.com/api/cooperate`)
with production credentials, and real users need production A-Passes —
none of that is implied or covered by this sandbox setup.

## Prompt 15 status (2026-08-09)

Phase 6 of Prompt 15 asked for live re-verification of the configured
CVI validator, deployer CVI status, and PoolManager/LendingManager
registration against real Monad Testnet + Cleanverse sandbox state.
**Not executed** — this session's sandbox has confirmed-blocked network
egress to both `docs.cleanverse.com` and `uatapi.cleanverse.com`
(tested live this milestone, `403 CONNECT tunnel failed`), so no live
Cleanverse call could be made without fabricating a result. Every fact
in this document remains exactly as confirmed during Build 11 (by the
BitV team, executing directly against the real sandbox API from their
own terminal) — nothing here was re-verified or changed this session,
and nothing was invented to fill the gap.

## Where this table supersedes/consolidates

This table restates, in the exact format Build 10 Phase 8 asks for, facts
already established across `docs/cleanverse-integration.md`,
`docs/cleanverse-integration-todo.md`, and Build 09's
`docs/deployment-readiness.md` §5/§8 — it does not introduce any new
Cleanverse fact. Those documents remain the fuller narrative source; this
is the compact lock-file for deployment-readiness tracking going
forward.
