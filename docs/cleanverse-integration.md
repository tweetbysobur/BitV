# Cleanverse Integration — BitV Compliance Foundation

**Status: compliance architecture only.** No financial logic, no BitScore
calculation, no live Cleanverse deployment. This document is the
implementation spec built during Build 02.

## Source-of-truth status (read this first)

This session could not directly fetch `docs.cleanverse.com` — every
attempt (this milestone and the prior one) returned
`EGRESS_BLOCKED: docs.cleanverse.com` from both the fetch tool and a raw
`curl` through this sandbox's proxy. It is a network-policy block, not a
transient failure or an auth problem the provided access code could fix.

Everything below that describes `IAPassComplianceValidator`,
`complianceVerify`, and `RuleV2` comes from the Build 02 task description
itself, which stated it was relaying the "Cleanverse Compliance Protocol
Integration Guide V2." That description gave:

- The exact function signature: `complianceVerify(address poolAddress, address userAddress) returns (bool)`
- The exact `RuleV2` field names: `allowedGroup`, `allowedSubGroup`, `minTier`, `minSubTier`, `poolCountryBitmap`
- The exact combination semantics: AND within a rule, OR across rules

It did **not** give: Solidity types for the `RuleV2` fields, any
rule-management/rule-lookup function signatures, the validator's deployed
address, CVA's exact mechanics, error/revert conventions, events, or an
off-chain API/SDK surface. Those are marked `UNCONFIRMED` throughout this
document and were not implemented. Anything marked `UNCONFIRMED` must be
verified against the primary documentation (directly, or via pasted
content) before it is relied on for a real deployment.

## 1. Cleanverse architecture (as relayed to BitV)

Cleanverse acts as BitV's compliance authority: a validator contract,
`IAPassComplianceValidator`, that BitV's protocol contracts call before
allowing a protected action, rather than BitV building its own KYC/identity
verification system. BitV's job is to *consume* that validator correctly,
not to reimplement identity or asset verification.

## 2. Identity — UNCONFIRMED

No identity primitive name, issuance flow, wallet-linking mechanism,
status/expiration/revocation model, or off-chain lookup API was given.
What compliance status a wallet has is presumed to be reflected in
whatever backs `complianceVerify`'s answer, but nothing about *how*
Cleanverse determines group/tier/country for a wallet was specified. Do
not implement identity issuance or lookup logic — `services/cleanverse`
stays a throwing stub for this.

## 3. Verified Assets (CVA) — UNCONFIRMED, evaluated conceptually only

No CVA asset list, verification method, provenance schema, or settlement
mechanism was given. Two integration *modes* were described conceptually
in the task, and BitV should plan for both without implementing either
yet:

1. **CVA automatic compliance** — an asset itself carries verified status
   (its provenance/attestation is checked once, by Cleanverse, at the
   asset level), so BitV wouldn't need a separate `complianceVerify` call
   for every interaction with that asset. Candidate use: RWA collateral
   whose provenance Cleanverse has already attested.
2. **Direct `complianceVerify` calls** — BitV explicitly checks a
   `(pool, user)` pair on each protected action. This is what's actually
   implemented in this milestone (`BitVComplianceGuard._requireCompliance`),
   since it's the only mechanism with a confirmed signature.

**Do not label any BitV asset as CVA** until Cleanverse's actual
verification of that asset is confirmed — this milestone introduces no
CVA-flagged assets, fake or real.

## 4. Authentication — UNCONFIRMED

No API key format, header names, wallet-signature scheme, or OAuth flow
was given for any off-chain Cleanverse API. On-chain, `complianceVerify`
is a `view` call requiring no authentication beyond the caller being a
contract Cleanverse has registered rules for (also unconfirmed how
registration works). `.env.example` keeps `CLEANVERSE_API_KEY` /
`CLEANVERSE_API_BASE_URL` as private, server-only placeholders — never
`NEXT_PUBLIC_`.

## 5. API — UNCONFIRMED

No REST/API endpoint table can be produced; none were given or fetched.

## 6. SDK — UNCONFIRMED

No package name was given. `services/cleanverse/client.ts` does not import
any `@cleanverse/*` (or similarly guessed) package.

## 7. Blockchain

| Item | Value | Status |
|---|---|---|
| Network | Monad Testnet | Matches BitV's own target network (`config/chains.ts`) |
| Contract | `IAPassComplianceValidator` | Interface only — see `contracts/src/interfaces/external/IAPassComplianceValidator.sol` |
| Deployed address | — | UNCONFIRMED — `NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS` left empty in `.env.example` |
| Functions | `complianceVerify(address,address) view returns (bool)` | Confirmed signature (task-relayed) |
| `RuleV2` fields | `allowedGroup, allowedSubGroup, minTier, minSubTier, poolCountryBitmap` | Confirmed names; **Solidity types are an assumption** (all `uint256`) — see interface file header |
| Rule-management functions | — | UNCONFIRMED — not declared in the interface |
| Events | — | UNCONFIRMED — none declared |
| ABI | — | Derived only from the interface above; not a real Cleanverse ABI |

## 8. BitV Mapping

| Cleanverse primitive | BitV module | Purpose | Implementation this milestone |
|---|---|---|---|
| `IAPassComplianceValidator.complianceVerify` | `BitVComplianceGuard` (shared base) | Gate every protected action behind Cleanverse compliance | Implemented — `contracts/src/compliance/BitVComplianceGuard.sol` |
| `RuleV2` | Off-chain mirror in `services/cleanverse/types.ts` | UI/off-chain reasoning about eligibility criteria | Type mirror only, no reads yet |
| CVA (conceptual) | Future RWA collateral path in `BitVLendingManager` | Skip redundant per-tx checks for pre-verified assets | Not implemented — evaluated in §3 only |
| BitScore (BitV-native, **not** Cleanverse) | `BitScoreManager` | Borrowing limits, LTV, interest tier, pool eligibility, yield access | Skeleton only, explicitly out of scope this milestone |

## 9. BitV User Flow

```
Connect wallet
  → (UNCONFIRMED) Cleanverse identity verification / status lookup
  → BitV reads ComplianceStatus (loading → eligible | ineligible | verification-required | error)
  → BitV access decision: contract call to a protected action triggers
    IAPassComplianceValidator.complianceVerify(pool, user) on-chain
  → If false: revert ComplianceErrors.ComplianceCheckFailed(pool, user) — no state change
  → If true: BitScore (BitV-native, separate from Cleanverse) determines
    borrowing limits / tier / eligibility — NOT implemented this milestone
  → Protocol interaction (pool/lending/vault/RWA action) — NOT implemented,
    stubs revert NotImplemented after the compliance check passes
  → Verified asset settlement (CVA, if applicable) — NOT implemented
```

The sequence matches what was specified; nothing required reordering it,
because the only confirmed on-chain check (`complianceVerify`) is a
stateless read that naturally happens before any state-changing logic.

## 10. Security

- **Compliance check runs first, always.** Every protected function in
  `BitVPoolManager` / `BitVLendingManager` / `BitVVaultManager` calls
  `_requireCompliance(msg.sender)` as its first line — see
  `test/unit/BitVComplianceGuard.t.sol::test_ProtectedFunctionCannotBypassCompliance`.
- **Validator address is immutable.** Set once in each contract's
  constructor, rejects `address(0)`, no setter exists. This is BitV's own
  architectural choice (not a confirmed Cleanverse requirement) to prevent
  a privileged key from silently swapping the compliance authority.
- **API key handling / webhook verification / replay protection /
  signature verification** — UNCONFIRMED, not applicable yet since no
  off-chain API integration exists.
- **Identity spoofing / asset verification** — entirely Cleanverse's
  responsibility per the architecture; BitV only trusts
  `complianceVerify`'s boolean answer for the immutable validator address
  it was constructed with.
- **Server-side validation** — `CLEANVERSE_API_KEY` / `CLEANVERSE_API_BASE_URL`
  stay non-`NEXT_PUBLIC_`, so they're never bundled to the client.

## 11. Environment Variables

| Variable | Category | Notes |
|---|---|---|
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | Public frontend | WalletConnect/RainbowKit |
| `NEXT_PUBLIC_MONAD_TESTNET_RPC_URL` | Blockchain (public) | No hardcoded fallback in code |
| `NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS` | Blockchain (public) | Contract address, not a secret; UNCONFIRMED — leave empty |
| `CLEANVERSE_API_KEY` | Cleanverse credential (private) | UNCONFIRMED variable name; never expose client-side |
| `CLEANVERSE_API_BASE_URL` | Cleanverse credential (private) | UNCONFIRMED |

## 12. Single-Contract Mode vs. Factory Mode

BitV MVP uses **Single-Contract Mode**: each protocol contract
(`BitVPoolManager`, `BitVLendingManager`, `BitVVaultManager`) holds one
immutable reference to Cleanverse's validator and checks compliance
against itself as `poolAddress`. This is appropriate because:

- BitV's MVP has a small, known set of protocol contracts (six), not an
  open-ended number of independently registered pools.
- Single-Contract Mode is the simpler, more auditable starting point —
  fewer moving parts to get wrong in a compliance-critical path.
- Nothing in the relayed task material indicated Factory Mode is required
  for BitV's current scope.

**Factory Mode is not implemented.** If BitV later needs many
independently registered pools (e.g. permissionless pool creation), the
architecture stays extensible: `BitVComplianceGuard` already isolates
"how a contract proves compliance" from "what that contract does," so a
factory that deploys many `BitVPoolManager`-like contracts, each with its
own registered rules under the same validator, would not require changing
the compliance-check pattern itself — only how/where contracts get
deployed and registered.
