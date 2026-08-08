# Cleanverse Integration

BitV's trust layer. This document covers setup, architecture, every Cleanverse
endpoint consumed, and how future protocol modules consume identity and asset
verification.

Built against **Cleanverse Cooperate API v5.6**. A local copy of the
specification is at [`cleanverse-api-v5.6-reference.txt`](./cleanverse-api-v5.6-reference.txt);
the canonical source is <https://docs.cleanverse.com> (invitation-gated).

---

## 1. Setup

### Credentials

Cleanverse issues two values. Both are **server-side only**.

| Variable | Purpose | Transmitted? |
| --- | --- | --- |
| `CLEANVERSE_API_ID` | Identifies BitV as an institution. Sent as the `api-id` header on every request. | Yes, as a header |
| `CLEANVERSE_API_KEY` | Base64-encoded AES key used to encrypt request bodies. | **Never** |

> **The `api-key` must never be sent to Cleanverse and must never reach the
> browser.** It is used locally as an encryption key. Adding a `NEXT_PUBLIC_`
> prefix to either value would inline it into the client bundle and leak
> BitV's institution credentials to every visitor.

`src/config/cleanverse.ts` imports `server-only`, so an accidental client
import is a build error rather than a silent leak.

### Environment

```bash
CLEANVERSE_API_ID=""
CLEANVERSE_API_KEY=""
CLEANVERSE_API_BASE_URL="https://uatapi.cleanverse.com/api/cooperate"
CLEANVERSE_REGISTRATION_URL="https://register.cleanverse.com/apass"
CLEANVERSE_VALIDATOR_POOL_ADDRESS=""
CLEANVERSE_TIMEOUT_MS="10000"
```

Environments:

- Sandbox (UAT): `https://uatapi.cleanverse.com/api/cooperate`
- Production: `https://api.cleanverse.com/api/cooperate`

BitV **defaults to sandbox** because it targets Monad Testnet. Pointing
testnet traffic at production would register real A-Pass records against test
wallets.

`CLEANVERSE_VALIDATOR_POOL_ADDRESS` stays empty until BitV's pools are
deployed and registered via `POST /validator/register` (an Issue Member
operation requiring an owner signature). Until then, pool checks report
`not_configured` rather than silently passing.

### Behaviour without credentials

The integration degrades honestly rather than crashing:

| Route | Response |
| --- | --- |
| `/api/cleanverse/identity` | `200` with `state: "unavailable"` |
| `/api/cleanverse/compliance` | `200`, all capabilities denied with reason `identity_unavailable` |
| `/api/cleanverse/assets` | `503` with `kind: "not_configured"` |
| `/api/cleanverse/eligibility` | `200` with `allowed: false`, reason `unavailable` |

`unavailable` is never conflated with `unregistered`. Telling a verified user
they are unverified because of an outage would misrepresent their compliance
standing — the distinction is enforced throughout.

---

## 2. Architecture

```
src/
├─ config/
│  └─ cleanverse.ts          Credentials, chain slug mapping (server-only)
├─ lib/cleanverse/
│  ├─ crypto.ts              AES/CBC encryption for encrypted endpoints
│  ├─ client.ts              Single HTTP client; envelope + error handling
│  ├─ errors.ts              CleanverseError taxonomy, sub-code extraction
│  ├─ types.ts               Zod schemas for every documented response
│  ├─ identity.ts            CVI — A-Pass query, verification state
│  ├─ assets.ts              CVA — A-Token discovery, eligibility, provenance
│  ├─ validator.ts           Validator pool compliance (read-only)
│  ├─ permissions.ts         Capability engine (pure, isomorphic)
│  └─ compliance.ts          Composition: context + transaction eligibility
├─ app/api/cleanverse/
│  ├─ identity/              GET  — credential state
│  ├─ compliance/            GET  — identity + permissions + alerts
│  ├─ assets/                GET  — verified assets + per-wallet eligibility
│  └─ eligibility/           POST — pre-flight transaction check
├─ hooks/
│  ├─ use-identity.ts        Compliance context
│  ├─ use-permissions.ts     Per-capability decisions
│  └─ use-verified-assets.ts CVA list
└─ components/identity/
   ├─ verification-badge.tsx IdentityBadge (5 states)
   ├─ verification-card.tsx  Primary identity surface
   ├─ compliance-alerts.tsx  Persistent inline alerts
   ├─ identity-gate.tsx      Capability-based route/section gating
   ├─ protocol-access.tsx    Feature availability list
   └─ verified-assets.tsx    CVA table + dashboard summary
```

### Layering rule

Credentials never cross the server boundary. The browser talks only to BitV's
own `/api/cleanverse/*` routes; those routes talk to Cleanverse. This is not
just hygiene — it is what makes the authorization model below possible.

### Authorization: address binding

Every route derives the wallet address from the **SIWE session**, never from a
query parameter or request body (`src/lib/auth/require-session.ts`).

This is the entire authorization model. Identity data — tier, KYC hash,
jurisdiction, credential status — is personal information about a real person.
If the address came from client input, any visitor could enumerate the
verification status and jurisdiction of arbitrary wallets by iterating
addresses. Binding to a signature-verified session means a caller can only
ever read their own.

`currentKycHash` is additionally stripped from all API responses. It is a
stable fingerprint of a person's KYC dossier, the UI has no use for it, and
shipping it to the browser would place a cross-service identifier for a real
person into client memory and any error-reporting payload.

---

## 3. Endpoints used

All are `POST` to `{base}/api/cooperate{path}` with `api-id` and
`X-Request-ID` headers. Every one BitV uses is **read-only** and accepts
**plain JSON** — no AES encryption required.

### Identity (CVI)

#### `POST /query_apass`

Retrieves an A-Pass record by wallet address.

```jsonc
// Request
{ "chain": "monad", "address": "0x…" }

// Response data
{
  "cvRecordId": "2",
  "tier": "26",              // string, despite being numeric
  "subTier": 1,
  "status": 1,               // 1 = active, 2 = frozen
  "expirationTime": 1863690034,  // Unix SECONDS
  "group": "aa",
  "subGroup": "zz",
  "currentKycHash": "…",
  "countries": ["SG", "US"]  // optional, added v5.5
}
```

Consumed by: `lib/cleanverse/identity.ts` → `queryAPass`.

**Two field traps handled explicitly:**

- `expirationTime` is Unix **seconds**. Comparing it directly against
  `Date.now()` (milliseconds) marks every credential expired.
- `tier` is a **string**. `Number()` on a non-numeric value yields `NaN`,
  which compares `false` against every threshold silently — normalised to
  `null` instead.

**Derived states** (`deriveVerificationState`) — richer than the API's
two-value `status`, because `status` alone cannot express every condition that
needs different remediation:

| State | Condition | Remediation |
| --- | --- | --- |
| `active` | `status = 1`, not past expiry | — |
| `expired` | `status = 1`, past expiry | Renew (self-service) |
| `frozen` | `status = 2` | Contact Cleanverse (no self-service) |
| `unregistered` | No record | Register |
| `unavailable` | Service unreachable | Retry |

`expired` and `frozen` are kept distinct: collapsing them would give a user
with a lapsed credential the same dead-end message as one under compliance
review, when the first is a two-minute fix.

### Assets (CVA)

#### `POST /query_deposit_atoken_list`

Lists supported A-Tokens and the origin tokens they wrap.

```jsonc
// Request
{ "chain": "monad" }

// Response data.tokens[]
{
  "origin_token": { "address": "…", "symbol": "usdc", "decimals": 6 },
  "atoken":       { "address": "…", "symbol": "ausdc", "decimals": 6 },
  "accesscore_address": "…",   // enforces transfer compliance on-chain
  "apass_address": "…"
}
```

Consumed by: `assets.ts` → `listVerifiedAssets`.

This is the authoritative source for which assets BitV may list as collateral.
Hardcoding a token list would let BitV offer an asset Cleanverse does not
actually gate — silently breaking the protocol's core guarantee.

#### `POST /verify_apass`

Verifies a wallet may receive/transfer a specific A-Token.

```jsonc
// Request
{ "chain": "monad", "atoken": "0x…", "address": "0x…" }

// Response data
{ "code": 4, "message": "apass verify success", "magickLink": "https://…" }
```

| `data.code` | Meaning | BitV mapping |
| --- | --- | --- |
| 1 | A-Token not found | `unsupported_asset` |
| 2 | No A-Pass | `no_identity` |
| 3 | A-Pass expired or frozen | `identity_not_transferable` |
| 4 | Valid, transfer allowed | `eligible` |

> **`data.code` is an integer and is NOT the envelope's string `code`.** The
> envelope reports whether the *call* worked; this reports whether the *user*
> may transact. Conflating them is the easiest mistake to make against this
> API. Undocumented values map to `unavailable` — a compliance check must fail
> closed.

`magickLink` is a wallet-and-token-scoped registration deep link, preferred
over the statically configured registration URL when present.

#### `POST /query_institution_white_list`

Licensed institutions permitted to originate each asset — the provenance
signal. For RWA-backed lending this determines whether collateral is
acceptable under a counterparty's own compliance policy.

Consumed by: `assets.ts` → `getAssetProvenance`.

### Validator compliance

Read-only endpoints, all plain JSON:

| Endpoint | Purpose |
| --- | --- |
| `POST /validator/verify` | Evaluate a wallet against a pool's rules |
| `POST /validator/rules` | List a pool's configured rules |
| `POST /validator/is_paused` | Pool pause state |
| `POST /validator/is_register` | Whether a pool is registered |

> `POST /validator/verify` returns HTTP 200 + `code: "0000"` with
> `valid: false` when a user is **not** eligible. That is a successful call
> with a negative outcome, not an error. Treating it as a throw would conflate
> "checked and denied" with "could not check".

**Write endpoints are deliberately not wrapped.** `grant`, `register`,
`set_rule`, `add_rule`, `remove_rule`, and `set_paused` require Issue Member
role plus an EIP-191 signature from the pool contract's `owner()`. Exposing
them in the module the user-facing app imports would put pool administration
one careless call away from a request handler. They belong in a separate
operator tool with its own authorization.

### Rule semantics

```jsonc
{
  "allowed_group": "AB",      // "" = no restriction
  "allowed_sub_group": "",
  "min_tier": 5,              // 0 = no restriction, not "tier zero"
  "min_sub_tier": 0,
  "is_black_list": false,     // true inverts `countries` to a deny-list
  "countries": ["US"]
}
```

`describeRule()` renders these as human-readable requirements — `min_tier: 5`
means nothing to an end user; "Identity tier 5 or above" is actionable.

---

## 4. Encryption

`src/lib/cleanverse/crypto.ts` implements the documented scheme, required for
the write endpoints BitV does not currently call (and ready if it needs to):

```
Algorithm:   AES
Mode:        AES/CBC/PKCS5Padding
IV:          fixed 16 zero bytes
Key:         Base64-decoded api-key
Body:        {"data": "<Base64 ciphertext>"}
```

Two properties of this scheme are worth stating plainly, since both look like
defects and are neither BitV's choice nor compensable client-side:

1. **The IV is fixed**, not random-per-message. This is what the specification
   mandates, so it is what interoperates. It means identical plaintexts
   produce identical ciphertexts, leaking equality between requests. It does
   not weaken confidentiality of a single message's contents.
2. **CBC provides no authentication.** Ciphertext integrity rests entirely on
   TLS. The client therefore refuses non-HTTPS base URLs outside localhost.

PKCS5 and PKCS7 padding are identical for 16-byte block ciphers (Java says
PKCS5, Node says PKCS7); Node applies it by default, so no explicit padding
config is needed.

Verified by round-trip tests across AES-128/192/256, block alignment, UTF-8
plaintext, wrong-key rejection, and the deterministic-ciphertext property.

---

## 5. Error handling

`CleanverseError` classifies every failure by `kind`, so callers branch on
category rather than string-matching messages:

| Kind | Cause | Retryable |
| --- | --- | --- |
| `not_configured` | Credentials absent | No |
| `network` | DNS, TLS, timeout, reset | Yes |
| `auth` | Bad api-id, disallowed IP, decryption failure (403) | No |
| `invalid_request` | HTTP 400 or envelope code `0001` | No |
| `business` | Envelope code `0002` and module sub-codes | No |
| `malformed_response` | Response failed schema validation | No |
| `unknown` | Unclassified | No |

The API signals failure in three structurally different ways:

1. HTTP-level (403, 500, timeout)
2. Envelope-level: **HTTP 200 with `code` ≠ `"0000"`**
3. Bracketed sub-codes inside `message`: `[RM_007]`, `[12026]`, `[12027]`

The second is the trap. A caller checking `response.ok` alone would treat
"A-Pass frozen" as success. `extractSubCode()` parses the third so callers can
branch on the specific condition rather than on prose that could be reworded.

`error.userMessage` never surfaces raw gateway text — those messages reference
api-ids, encryption, and internal sub-codes, and are alarming and
unactionable in a product UI.

Responses are **parsed with Zod, not cast**. At a third-party boundary an
unvalidated cast means a changed field surfaces as `undefined` deep inside a
compliance decision instead of as an explicit error at the edge.

---

## 6. Permission engine

`src/lib/cleanverse/permissions.ts` is pure and isomorphic — no `server-only`.
The server computes permissions authoritatively; the client re-derives the
same result from the same inputs for rendering. One implementation means the
UI can never show an action as available that the server would reject.

### Tier ladder

| Capability | Min tier | Pool-gated |
| --- | --- | --- |
| `view_markets` | 0 | No |
| `lend` | 1 | Yes |
| `join_pools` | 1 | Yes |
| `access_vaults` | 1 | No |
| `settle_verified_assets` | 1 | Yes |
| `borrow` | 10 | Yes |
| `institutional_vaults` | 50 | No |
| `governance` | — | Not yet available |

Rationale: reading market data requires no credential — gating public market
information behind KYC would make the protocol opaque to exactly the people
evaluating whether to use it. Supplying capital requires a verified
counterparty. **Borrowing requires a higher tier because the protocol is
extending trust rather than custodying it.** Institutional vaults sit highest
because they carry custody-grade compliance obligations.

These are BitV protocol policy, deliberately separate from the on-chain
Validator rules Cleanverse enforces independently. Both must pass — not
redundancy, since the Validator is authoritative on-chain while this ladder
additionally encodes BitV's own (potentially stricter) risk appetite.

### Denial reasons

Each maps to its own message and single next action, so a user is never told
"access denied" without also being told what would grant it:

`wallet_not_connected`, `not_authenticated`, `identity_unregistered`,
`identity_expired`, `identity_frozen`, `identity_unavailable`, `tier_too_low`,
`pool_ineligible`, `pool_paused`, `not_yet_available`.

---

## 7. Compliance layer

`compliance.ts` answers the two questions the protocol actually asks.

### `getComplianceContext()` — "what may this account do?"

Runs identity and pool checks concurrently (independent; serialising would
double dashboard first-paint latency) and returns identity, permissions,
overall status, and alerts from **one consistent snapshot**. Three independent
client fetches could interleave and produce a UI that contradicts itself —
permissions evaluated against a stale credential while alerts reflect a fresh
one.

### `checkTransactionEligibility()` — "may this transaction proceed?"

Pre-flight check combining identity + asset + pool. Called before a
transaction is built, so a compliance failure surfaces as a clear message
rather than an opaque on-chain revert from AccessCore — **and the user pays no
gas to discover they were ineligible.**

**Fails closed.** If eligibility cannot be established, the transaction does
not proceed. For a read-only dashboard, degrading to "unknown" is acceptable;
for moving value it is not.

---

## 8. UI integration points

| Surface | Component | Shows |
| --- | --- | --- |
| Dashboard | `ComplianceAlerts`, `VerificationCard`, `ProtocolAccessList`, `VerifiedAssetsSummary` | Alerts, credential, unlocked features, eligible assets |
| Lending / Borrow / Pools / Vaults | `ComplianceAlerts`, `IdentityGate` | Alerts + capability gating on the action, not the data |
| BitScore | `BitScoreIdentityStatus`, `ScoreFactors` | Real credential state; identity and asset factors backed by live data |
| Settings | `VerificationCard`, `ProtocolAccessList`, `VerifiedAssetsTable` | Full identity management |
| Sidebar / profile | `WalletProfileCard`, `IdentityBadge` | Tier and jurisdiction at a glance |

**Market data stays visible regardless of verification.** Rates, liquidity,
and TVL are public protocol information. `IdentityGate` wraps only the *act*
of supplying or borrowing — hiding market data would make BitV opaque to
anyone deciding whether verification is worth it.

`VerificationCard` includes an explicit **Refresh** control because
verification completes on Cleanverse's hosted flow in a separate tab. Without
it, users return to a card still reading "unverified" and reasonably conclude
it failed.

### On fabricated data

BitScore still shows no score. The identity and asset-verification factors are
real; repayment history requires lending activity in markets that are not
deployed. It reads "Pending activity" rather than showing zero — **a zero bar
implies a bad repayment record rather than an absent one**, which would
misrepresent a new user's standing.

---

## 9. How future modules consume this

The integration is deliberately shaped so lending, pools, vaults, and
settlement plug in without reworking it.

### Lending / borrowing engine

```ts
// Gate the action, not the market data
<IdentityGate capability="borrow">
  <BorrowForm />
</IdentityGate>

// Pre-flight before building the transaction
const eligibility = await fetch('/api/cleanverse/eligibility', {
  method: 'POST',
  body: JSON.stringify({ atoken: market.atokenAddress }),
});
if (!eligibility.allowed) return showReason(eligibility);
```

Add a capability to `ProtocolCapability` and its tier to
`CAPABILITY_TIER_REQUIREMENTS`; gating, messaging, and remediation come for
free.

### Liquidity pools

Once BitV pools deploy, register each via `POST /validator/register` and set
`CLEANVERSE_VALIDATOR_POOL_ADDRESS`. `verifyPoolCompliance` then returns
`eligible` / `ineligible` instead of `not_configured`, and the
`pool_ineligible` branch in `permissions.ts` — already written — becomes
operative. **No permission-engine changes required.**

For per-pool rules, pass `poolAddress` explicitly rather than relying on the
configured default; `getPoolRules` + `describeRule` render requirements to
users.

### Yield vaults

Institution-only vaults already have a capability
(`institutional_vaults`, tier 50). Vault listings filter on
`usePermission('institutional_vaults').allowed`.

### Settlement

`checkTransactionEligibility` is the settlement gate. Counterparties must pass
before verified collateral moves, or the on-chain transfer reverts at
AccessCore anyway. `listVerifiedAssets` supplies which assets are settleable;
`getAssetProvenance` supplies the issuer attestation RWA collateral needs.

### BitScore

`identity.tier`, `subTier`, `group`, `countries`, and credential age are
already exposed as scoring inputs. When repayment history exists, it joins
`ScoreFactors` alongside the two live factors.

### Risk engine

`IdentityProfile` supplies the identity-derived component of risk:
tier, jurisdiction (`countries`), credential expiry proximity
(`expiringSoon`), and pool compliance. Consume `getComplianceContext` rather
than calling Cleanverse directly, so risk decisions and UI permissions derive
from the same snapshot.

---

## 10. Operational notes

- **Chain slug ≠ chain ID.** Cleanverse uses lowercase slugs (`monad`), not
  EIP-155 IDs. `toCleanverseChainSlug()` returns `null` for unsupported chains
  rather than defaulting — silently coercing would query the wrong network and
  could report an A-Pass that does not exist on the chain the user is on.
- **Amounts are decimal strings**, never JS numbers. `query_txs` returns
  base-unit strings; parsing them as floats loses precision above 2^53.
- **No caching.** All routes send `Cache-Control: no-store` and the client
  uses `cache: 'no-store'`. Identity state is per-user and security-relevant;
  serving it from a shared cache would be a cross-user data leak.
- **Timeouts.** 10s default, own `AbortController`, so a hung gateway cannot
  hold a Next.js request handler open indefinitely.
- **Rate limits.** Not documented in v5.6. `staleTime` is 60s for identity and
  5min for assets to keep call volume low.

---

## 11. Verification performed

- **AES scheme** — 10/10 checks: round-trip at AES-128/192/256, block
  alignment, Base64 stability, deterministic ciphertext (per spec), wrong-key
  rejection, `{data}` envelope shape, empty object, UTF-8 plaintext.
- **Routes, unauthenticated** — all four return `401`.
- **Routes, authenticated via real SIWE session** — identity returns
  `unavailable` (not `unregistered`); compliance denies with
  `identity_unavailable`; assets returns `503 not_configured`; eligibility
  fails closed with `allowed: false`; malformed `atoken` rejected `400` before
  reaching Cleanverse.
- **Build** — typecheck, lint (0 warnings), production build all pass.

**Not yet verified against a live gateway.** All calls above exercised the
`not_configured` path because no `api-id`/`api-key` has been issued to this
environment. Request/response shapes are transcribed from the v5.6
specification and validated with Zod at runtime — a mismatch surfaces as an
explicit `malformed_response` error rather than silent corruption. Once
credentials are available, re-run against sandbox and confirm the A-Pass
field shapes, particularly `tier` (string) and `countries` (optional).
