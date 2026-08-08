# BitV Cleanverse Dependency Lock (Build 10)

No new Cleanverse functionality is implemented by this milestone. This
is a final, consolidated lock-file of exactly what's confirmed, what
isn't, and what's needed next — built from the two official Cleanverse
PDFs already in hand (per `docs/cleanverse-integration.md`,
`docs/cleanverse-integration-todo.md`, and Build 09's audit), with no new
inference performed here.

| Requirement | Status | Required for | Source | Next action |
|---|---|---|---|---|
| CVI validator address (any network) | **BLOCKED** | Deploying `BitVPoolManager`/`BitVLendingManager`/`BitVYieldVault` for real | Not given by either official Cleanverse PDF | Ask Cleanverse directly for a Monad Testnet validator address |
| Official Monad Testnet support | **BLOCKED** | Everything above (a validator address is meaningless if Cleanverse doesn't support the chain) | CVA guide's network list ("Ethereum, Base, BSC, Arbitrum, Polygon, etc.") omits Monad; CVI guide gives no network list at all | Ask Cleanverse directly whether Monad Testnet is supported |
| Chain ID Cleanverse expects for Monad | **UNCONFIRMED** | Validator registration | Not given by either PDF for any network | Ask Cleanverse — do not assume `10143` is what their systems expect without confirmation, even though it is BitV's own verified value |
| Validator registration process (`POST /api/cooperate/validator/register`) | **CONFIRMED** exists (CVI guide §5.4), **UNCONFIRMED** in operational detail (auth, exact payload beyond what's transcribed) | Making any deployed BitV contract's `complianceVerify` return true for anyone | CVI Integration Guide V2 §5 | Obtain the operational detail from Cleanverse once a validator address/network is confirmed |
| `CLEANVERSE_API_KEY` format/provisioning | **UNCONFIRMED** | Calling any Cleanverse off-chain API | Not described by either guide | Ask Cleanverse how BitV obtains API credentials |
| `CLEANVERSE_API_BASE_URL` | **UNCONFIRMED** | Same as above | Not given | Ask Cleanverse |
| CVI registration/issuance flow (how a wallet gets a CVI) | **UNCONFIRMED** | Understanding the user-facing KYC flow BitV's users go through | Neither guide describes it — both start from "the user already has a CVI" | Ask Cleanverse or find separate documentation |
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
  invented or filled into any config file.

## Where this table supersedes/consolidates

This table restates, in the exact format Build 10 Phase 8 asks for, facts
already established across `docs/cleanverse-integration.md`,
`docs/cleanverse-integration-todo.md`, and Build 09's
`docs/deployment-readiness.md` §5/§8 — it does not introduce any new
Cleanverse fact. Those documents remain the fuller narrative source; this
is the compact lock-file for deployment-readiness tracking going
forward.
