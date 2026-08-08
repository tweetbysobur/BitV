# BitV — Technical Architecture & Implementation Plan

**The Trust Layer for DeFi.**
Identity-native DeFi protocol on Monad, built on Cleanverse Verified Identity (CVI) and Cleanverse Verified Assets (CVA).

Status: pre-implementation design. No application code is written yet.

---

## 0. Assumptions requiring verification against Cleanverse API v3 docs

The `docs.cleanverse.com` reference is gated behind an invitation code and could not be read during this design pass. The following are working assumptions derived from Cleanverse's public material. **Each must be confirmed before contract interfaces are frozen** — they are the load-bearing external dependencies of the whole system.

| # | Assumption | Why it matters | Blast radius if wrong |
|---|---|---|---|
| A1 | CVI is exposed on-chain as a **non-transferable credential bound to a wallet address** (APASS model), queryable by a contract in a single `view` call. | Every gated action does an inline identity check. | If CVI is off-chain-only, every gate needs an attestation-signature path instead of a state read. Contained by the `ICVIRegistry` adapter (§14). |
| A2 | CVI carries **structured claims** — jurisdiction, entity type (individual/institution), accreditation tier, sanctions status, credential expiry. | Policy engine encodes rules over these claims. | Fewer claims ⇒ coarser policies; the `PolicyEngine` predicate set shrinks but the architecture holds. |
| A3 | CVA marks an asset as **origin-attested**, with attestation retrievable per token (and possibly per holder/lot). | Collateral eligibility and RWA lending depend on it. | If attestation is per-transfer rather than per-token, collateral accounting must track lots — significant, so verify early. |
| A4 | Cleanverse assets (A-token class) enforce **transfer restrictions at the token level** — transfers only between credentialed wallets. | Protocol contracts must themselves hold credentials, or be whitelisted, to custody user assets. | **Highest risk item.** If pool/vault contracts cannot hold A-tokens, the entire custody model changes (§14.4). Verify before anything else. |
| A5 | Cleanverse offers an **off-chain REST API** for credential status, attestation lookup, and Travel Rule payload exchange, authenticated per-institution. | Backend enrichment, compliance reporting, BitScore inputs. | Affects backend only. |
| A6 | Credentials can be **revoked**, and revocation is observable on-chain (event or status flip). | Positions held by revoked users need a defined lifecycle. | If revocation is off-chain-only, needs an oracle-pushed revocation feed — designed for in §14.3 either way. |
| A7 | Cleanverse supports Monad, or the credential registry can be **mirrored to Monad** via a Cleanverse-operated bridge/attestor. | Whole protocol is on Monad. | If not, BitV runs its own mirrored registry with Cleanverse as signing authority — designed for in §14.5. |

**Action:** before Milestone 1 closes, produce `docs/CLEANVERSE-INTEGRATION-SPEC.md` resolving A1–A7 with citations to the v3 docs, and adjust §14 accordingly.

---

## 1. Overall system architecture

BitV is a **four-plane system**. The separation is deliberate: each plane has a different trust model, a different failure mode, and a different upgrade cadence. Collapsing them is how protocols end up with off-chain components that are secretly consensus-critical.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ PRESENTATION PLANE            Next.js 15 App Router · TS · Tailwind ·    │
│                               shadcn/ui · Framer Motion                  │
│                               Trust: none. Read-only convenience +       │
│                               transaction construction.                  │
└───────────────┬──────────────────────────────────────┬───────────────────┘
                │ wagmi/viem (writes: user-signed)     │ tRPC (reads: cached)
                │                                      │
┌───────────────┴──────────────────────┐  ┌────────────┴───────────────────┐
│ SETTLEMENT PLANE (Monad)             │  │ SERVICE PLANE                  │
│  Authoritative. Holds all value.     │  │  Non-authoritative. Advisory,  │
│                                      │  │  analytical, compliance.       │
│  · Core: Pools, Lending, Vaults      │  │  · Indexer (Envio HyperIndex)  │
│  · Identity gates (CVI/CVA adapters) │  │  · BitScore compute service    │
│  · PolicyEngine                      │  │  · Risk simulation / stress    │
│  · RiskEngine (on-chain subset)      │  │  · Liquidation keeper network  │
│  · BitScoreOracle (attested writes)  │  │  · Travel Rule / reporting     │
│  · Liquidation, InterestRateModel    │  │  · Notification service        │
│  · Governance, Timelock, Guardian    │  │  Trust: signing authority for  │
│                                      │  │  BitScore attestations only.   │
└───────────────┬──────────────────────┘  └────────────┬───────────────────┘
                │                                      │
┌───────────────┴──────────────────────────────────────┴───────────────────┐
│ TRUST PLANE (external, Cleanverse)                                        │
│  CVI registry · CVA attestations · Travel Rule rails · revocation feed    │
│  Trust: root of identity truth. BitV never mints identity, only reads it. │
└───────────────────────────────────────────────────────────────────────────┘
```

### Governing principles

**P1 — Identity is a protocol primitive, not middleware.**
Every state-changing entry point in a permissioned market resolves an identity check *inside the contract*, not in the frontend, not in an API gateway. A user who bypasses the UI and calls the contract directly gets the same answer. This is the single non-negotiable invariant; it is what makes BitV a trust layer rather than a KYC'd frontend on top of ordinary DeFi.

**P2 — The chain is the only source of truth for value.**
The service plane may be down, wrong, or adversarial. No user can lose funds and no invariant can break as a result. Liquidations must be executable by anyone with public data. BitScore, the one place off-chain computation touches on-chain state, is constrained by on-chain bounds (§16.4) so a compromised scorer cannot mint arbitrary credit.

**P3 — Policy is data, code is mechanism.**
Jurisdictional rules change monthly; lending math does not. Policies live in an on-chain `PolicyEngine` as composable predicates over CVI claims, updatable under timelock. The lending engine asks "is this permitted?" and never knows what a jurisdiction is. This keeps the audited surface stable while compliance evolves.

**P4 — Design for Monad's execution model, not generic EVM.**
Monad executes optimistically in parallel and re-executes on conflict. Contention on a hot storage slot silently converts parallelism into serialization. BitV therefore shards state per market, avoids global counters touched on every transaction, and settles cross-market aggregates lazily (§15).

**P5 — Every privileged action is timelocked; every emergency action is pause-only.**
Guardians can stop the protocol. Only governance, after delay, can change it. There is no key in the system that can move user funds.

---

## 2. High-level product architecture

Four products over one shared identity+risk substrate. They share the substrate deliberately: a user's borrowing history in one market improves their BitScore, which improves their terms in another. That compounding is the product.

```
                    ┌───────────────────────────────┐
                    │      BitV Identity Layer      │
                    │  CVI adapter · CVA adapter ·  │
                    │  PolicyEngine · BitScore      │
                    └───────────────┬───────────────┘
        ┌───────────────┬───────────┴────┬────────────────┐
        ▼               ▼                ▼                ▼
  ┌───────────┐  ┌────────────┐  ┌─────────────┐  ┌──────────────┐
  │ Verified  │  │  Lending   │  │   Yield     │  │     RWA      │
  │   Pools   │  │   Market   │  │   Vaults    │  │   Lending    │
  │           │  │            │  │             │  │              │
  │ AMM with  │  │ Over- AND  │  │ Permissioned│  │ CVA-attested │
  │ gated LP  │  │ under-     │  │ strategy    │  │ real-world   │
  │ + gated   │  │ collateral │  │ vaults,     │  │ collateral,  │
  │ swap tiers│  │ borrowing  │  │ ERC-4626+   │  │ off-chain    │
  └───────────┘  └────────────┘  └─────────────┘  └──────────────┘
        └───────────────┴────────┬───────┴────────────────┘
                                 ▼
                    ┌───────────────────────────────┐
                    │   Risk & Settlement Layer     │
                    │ RiskEngine · Liquidation ·    │
                    │ Oracles · Compliance export   │
                    └───────────────────────────────┘
```

**Why under-collateralized borrowing is the anchor product.** It is the only one that *cannot* be built without identity. Verified pools and permissioned vaults are differentiated versions of existing primitives; under-collateralized credit is a category that doesn't exist in permissionless DeFi because there is no recourse against an anonymous defaulter. CVI provides a persistent, non-transferable, real-world-bound identity — which makes reputation costly to discard and therefore makes uncollateralized credit priceable. Build the protocol so this is the flagship, and let the other three feed it liquidity and reputation signal.

---

## 3. Feature hierarchy

```
BitV Protocol
│
├── 1. Identity & Access  ─────────────────────────────── FOUNDATIONAL
│   ├── 1.1 CVI credential resolution (address → claims)
│   ├── 1.2 CVA asset attestation resolution (token → origin proof)
│   ├── 1.3 Credential lifecycle (issue-observe, refresh, expiry, revocation)
│   ├── 1.4 PolicyEngine — composable predicates over claims
│   │   ├── Jurisdiction allow/deny lists
│   │   ├── Entity-type gating (retail / accredited / institutional)
│   │   ├── Sanctions screening enforcement
│   │   └── Per-market policy binding
│   ├── 1.5 Institutional sub-accounts (one CVI, many operator keys)
│   └── 1.6 Session keys / delegated execution under policy limits
│
├── 2. BitScore  ─────────────────────────────────────── DIFFERENTIATOR
│   ├── 2.1 On-chain behavioural component (repayment, liquidation, tenure)
│   ├── 2.2 Off-chain attested component (CVI tier, external credit signal)
│   ├── 2.3 Score attestation pipeline (signed, bounded, decaying)
│   ├── 2.4 Score → credit-limit and score → rate-discount curves
│   ├── 2.5 Score explainability (factor breakdown, per-user)
│   └── 2.6 Dispute & appeal path
│
├── 3. Verified Liquidity Pools
│   ├── 3.1 Concentrated-liquidity AMM, gated LP entry
│   ├── 3.2 Tiered swap access (open / verified-only / institutional-only)
│   ├── 3.3 CVA-only asset pools
│   ├── 3.4 LP position NFTs with transfer restrictions matching pool policy
│   └── 3.5 Fee tiers & protocol fee switch
│
├── 4. Lending Market
│   ├── 4.1 Isolated markets (per-collateral risk containment)
│   ├── 4.2 Over-collateralized borrowing
│   ├── 4.3 Under-collateralized borrowing (BitScore credit lines)
│   ├── 4.4 Dynamic interest-rate models (utilization × identity tier)
│   ├── 4.5 Credit-line lifecycle (draw, repay, renew, default)
│   ├── 4.6 Liquidation (partial, Dutch-auction, identity-aware grace)
│   └── 4.7 Default resolution & loss socialization
│
├── 5. Yield Vaults
│   ├── 5.1 ERC-4626 core with permissioned deposit/withdraw
│   ├── 5.2 Strategy registry & allocation (multi-strategy)
│   ├── 5.3 Withdrawal queue for illiquid strategies
│   ├── 5.4 Performance/management fee accounting
│   └── 5.5 Vault-level risk caps & circuit breakers
│
├── 6. RWA Lending
│   ├── 6.1 CVA-attested collateral registry
│   ├── 6.2 Off-chain asset valuation oracle + attestor set
│   ├── 6.3 Legal-wrapper reference (SPV / custodian linkage)
│   ├── 6.4 Redemption & enforcement workflow
│   └── 6.5 Maturity/amortization schedules
│
├── 7. Risk Engine
│   ├── 7.1 Account health computation
│   ├── 7.2 Oracle aggregation & staleness/deviation guards
│   ├── 7.3 Exposure caps (per-asset, per-market, per-identity, protocol-wide)
│   ├── 7.4 Correlation & concentration limits
│   ├── 7.5 Off-chain stress testing → parameter proposals
│   └── 7.6 Circuit breakers
│
├── 8. Compliance & Settlement
│   ├── 8.1 Travel Rule payload attachment on qualifying transfers
│   ├── 8.2 Auditable event stream & attestation archive
│   ├── 8.3 Institutional reporting exports
│   └── 8.4 Sanctions-hit handling (freeze → governed resolution)
│
├── 9. Governance
│   ├── 9.1 Token-weighted + timelocked parameter governance
│   ├── 9.2 Guardian pause council
│   ├── 9.3 Risk-committee delegated parameter bounds
│   └── 9.4 Treasury & fee distribution
│
└── 10. Developer Platform
    ├── 10.1 Public read API + subgraph-equivalent (Envio)
    ├── 10.2 TypeScript SDK (typed contract bindings + policy simulation)
    ├── 10.3 Webhook/event subscriptions
    └── 10.4 Contract deployment registry per network
```

---

## 4. Application sitemap

```
/                                   Landing — brand, thesis, live protocol stats
/markets                            Market directory (pools · lending · vaults · RWA)
  /markets/lending
    /markets/lending/[marketId]     Market detail: rates, utilization, caps, oracle
  /markets/pools
    /markets/pools/[poolId]         Pool detail: depth, fees, access tier, volume
  /markets/vaults
    /markets/vaults/[vaultId]       Vault detail: strategy, APY, capacity, queue
  /markets/rwa
    /markets/rwa/[assetId]          RWA detail: attestation, valuation, legal wrapper

/app                                Authenticated shell (wallet + CVI required)
  /app/dashboard                    Net position, health, BitScore, alerts
  /app/identity                     CVI status, claims, tier, refresh, revocation notice
  /app/bitscore                     Score, factor breakdown, history, improvement path
  /app/borrow
    /app/borrow/new                 Open position (collateralized or credit line)
    /app/borrow/[positionId]        Manage: draw, repay, add collateral, health
  /app/lend                         Supply assets to lending markets
  /app/pools
    /app/pools/[poolId]/provide     Add/remove liquidity, range selection
    /app/pools/positions            LP positions
  /app/vaults
    /app/vaults/[vaultId]/deposit   Deposit/withdraw, queue status
  /app/rwa
    /app/rwa/originate              Submit CVA-attested collateral (originator flow)
    /app/rwa/[dealId]               Deal management
  /app/portfolio                    Cross-product positions, PnL, exposure
  /app/history                      Transactions, statements, compliance exports
  /app/settings                     Sub-accounts, session keys, notifications, RPC

/institution                        Institutional console (entity-tier CVI)
  /institution/overview             Aggregated entity exposure
  /institution/accounts             Sub-account & operator key management
  /institution/limits               Internal limit configuration
  /institution/reporting            Travel Rule records, audit exports
  /institution/api-keys             Programmatic access

/liquidate                          Public liquidation console (open to all)
  /liquidate/opportunities          Underwater positions, expected profit
  /liquidate/auctions               Live Dutch auctions

/governance
  /governance/proposals
    /governance/proposals/[id]      Proposal detail & voting
  /governance/parameters            Live risk parameters, change history
  /governance/treasury

/risk                               Public transparency (unauthenticated)
  /risk/parameters                  All risk params per market
  /risk/oracles                     Feed health, staleness, deviation
  /risk/exposure                    Concentration, caps, utilization
  /risk/audits                      Audit reports, bug bounty, incident log

/developers
  /developers/docs
  /developers/sdk
  /developers/api
  /developers/contracts             Verified addresses per network

/legal                              Terms, privacy, disclosures, jurisdiction notices
/status                             Protocol + service-plane status
```

**Design note.** `/risk` and `/liquidate` are unauthenticated and un-gated on purpose. Liquidations must be permissionless for the protocol to be safe (P2), and risk transparency is what institutional allocators diligence first. Gating either would be a self-inflicted wound.

---

## 5. User journeys

### 5.1 Retail verified user — first borrow
1. Lands on `/`, connects wallet on `/markets/lending/[id]` while browsing (read-only, no gate).
2. Attempts "Borrow" → app resolves CVI: **none found**.
3. Verification interstitial explains what CVI is, what data leaves the app, and why. Deep-links to Cleanverse onboarding with a return URL.
4. Completes bank-verified onboarding at Cleanverse. Returns; app polls credential status until the on-chain credential resolves.
5. `/app/bitscore` shows an **initial score from CVI tier only** — no borrow history yet — with an explicit "how to improve" path.
6. Supplies collateral → `/app/borrow/new` shows two options: over-collateralized (available now) and credit line (locked, requires score threshold).
7. Borrows over-collateralized. Health factor and liquidation price shown pre-signature, with the exact price move required to liquidate.
8. Repays on time. Repayment event feeds BitScore behavioural component; score rises; credit line unlocks at threshold.

**Why staged.** A new identity with no history is exactly the profile an attacker constructs. Credit is earned through on-chain behaviour under a persistent identity, never granted at onboarding.

### 5.2 Under-collateralized borrower — credit line
1. `/app/bitscore` ≥ threshold → credit line offer appears with limit, rate, tenor, and the covenants attached.
2. Reviews terms: limit derived from score curve, rate = base + utilization + score discount, tenor with renewal, default consequences (score destruction, cross-market restriction, CVI-linked recourse).
3. Signs credit-line agreement — an on-chain commitment referencing an off-chain legal terms hash (§18.6).
4. Draws partially. Interest accrues only on drawn amount.
5. Approaching maturity: notifications at T-14/T-7/T-1 days via `/app/settings` channels.
6. Repays → line renews with a possible limit increase. Or misses → grace period (identity-aware, §17.5), then default: line frozen, score penalized, cross-product borrowing restricted, recourse workflow initiated off-chain via CVI linkage.

### 5.3 Liquidity provider — verified pool
1. `/markets/pools/[id]` shows access tier badge and current depth.
2. Connects; CVI check passes for the tier.
3. `/app/pools/[id]/provide`: selects range, sees projected fee APR and impermanent-loss simulation at ±10/25/50%.
4. Approves + adds liquidity in one batched flow. Receives a transfer-restricted LP position NFT (transferable only to wallets satisfying the same pool policy — otherwise the gate is trivially bypassed by selling the position).
5. Monitors fees; withdraws with a policy re-check at exit (§14.3 handles the revoked-user case).

### 5.4 Institutional allocator — permissioned vault
1. Diligences `/risk` and `/markets/vaults/[id]` unauthenticated: strategy, caps, oracle set, audits.
2. Entity CVI obtained through Cleanverse institutional onboarding.
3. `/institution/accounts`: registers operator keys as sub-accounts under one entity credential, with per-operator limits.
4. Treasury operator deposits within the sub-account limit; a second signer approves above threshold.
5. `/institution/reporting` exports positions, flows, and Travel Rule records for audit.
6. Withdrawal enters the queue if the strategy is illiquid; queue position and ETA are shown.

### 5.5 RWA originator
1. Entity CVI + originator role required.
2. `/app/rwa/originate`: submits asset with CVA attestation, valuation report, and legal wrapper reference (SPV, custodian, jurisdiction).
3. Attestor set verifies; risk committee assigns LTV, haircut, and cap.
4. Asset becomes eligible collateral in a **dedicated isolated market** — never cross-margined with crypto collateral, so an RWA valuation failure cannot cascade.
5. Borrows against it under an amortization schedule; repays per schedule; oracle revaluations trigger margin calls with a longer, governance-set grace window reflecting off-chain settlement latency.

### 5.6 Liquidator (permissionless, no CVI)
1. `/liquidate/opportunities` — public, no wallet gate to view.
2. Sees underwater positions, close factor, bonus, expected profit net of estimated gas.
3. Executes liquidation. **No CVI required to liquidate** — safety must never depend on a credentialed party showing up.
4. Receives collateral + bonus. If the seized collateral is a restricted CVA asset, it routes through a settlement adapter that either (a) delivers to a credentialed liquidator, or (b) auctions to credentialed bidders and pays the liquidator in an unrestricted asset (§17.6). This is a genuine design constraint of permissioned collateral and must be solved, not hand-waved.

### 5.7 Governance participant
Reviews proposal on `/governance/proposals/[id]` with the risk-simulation output attached → votes → timelock → execution. Parameter changes within pre-approved bounds may be made by the risk committee without full vote (faster response to market conditions, bounded blast radius).

### 5.8 Guardian (emergency)
Detects anomaly (oracle deviation, exploit signature) → pauses affected market or protocol-wide → **pause only, never parameter change or fund movement** → post-mortem → governance decides resumption.

### 5.9 Developer
`/developers` → installs SDK → reads contract registry → queries indexer → simulates a policy check locally against the same `PolicyEngine` logic before submitting a transaction.

---

## 6. Folder structure

Monorepo. The contracts, SDK, indexer, and app share types; a polyrepo would guarantee drift between ABI and frontend, which is where integration bugs live.

```
bitv/
├── apps/
│   ├── web/                          # Next.js 15 (App Router)
│   │   ├── app/
│   │   │   ├── (marketing)/          # /, /developers, /legal  — static, ISR
│   │   │   ├── (protocol)/           # /markets, /risk, /governance — public reads
│   │   │   ├── (app)/                # /app/* — wallet + CVI gated
│   │   │   ├── (institution)/        # /institution/* — entity CVI gated
│   │   │   ├── api/                  # route handlers: tRPC, webhooks, health
│   │   │   └── layout.tsx
│   │   ├── components/
│   │   │   ├── ui/                   # shadcn primitives (generated, unmodified)
│   │   │   ├── brand/                # Logo, GradientMesh, motion primitives
│   │   │   ├── data/                 # StatTile, DataTable, Sparkline, HealthBar
│   │   │   ├── forms/                # AmountInput, TokenSelect, SlippageControl
│   │   │   ├── identity/             # CVIBadge, VerificationGate, TierChip
│   │   │   ├── risk/                 # HealthFactor, LiquidationPrice, ExposureRing
│   │   │   └── tx/                   # TxButton, TxStatus, SimulationPreview
│   │   ├── features/                 # vertical slices — the real unit of code org
│   │   │   ├── lending/{hooks,components,lib,types}
│   │   │   ├── pools/
│   │   │   ├── vaults/
│   │   │   ├── rwa/
│   │   │   ├── bitscore/
│   │   │   ├── identity/
│   │   │   └── governance/
│   │   ├── lib/
│   │   │   ├── wagmi/                # config, connectors, chains
│   │   │   ├── query/                # TanStack Query client, key factory
│   │   │   ├── trpc/
│   │   │   ├── format/               # bigint/decimal formatting — NEVER float
│   │   │   └── analytics/
│   │   ├── styles/
│   │   └── config/                   # chain + contract addresses per env
│   │
│   ├── api/                          # Service plane (Node/Fastify or Nest)
│   │   ├── src/modules/
│   │   │   ├── bitscore/             # scoring engine + attestation signer
│   │   │   ├── risk/                 # stress testing, param proposals
│   │   │   ├── compliance/           # Travel Rule, reporting, exports
│   │   │   ├── cleanverse/           # CVI/CVA API client + cache
│   │   │   ├── notifications/
│   │   │   └── admin/
│   │   ├── src/jobs/                 # scheduled: score recompute, health sweep
│   │   └── prisma/
│   │
│   ├── keeper/                       # Liquidation + vault-harvest bots
│   │   └── src/{strategies,executors,monitoring}/
│   │
│   └── indexer/                      # Envio HyperIndex
│       ├── config.yaml
│       ├── schema.graphql
│       └── src/handlers/
│
├── packages/
│   ├── contracts/                    # Foundry
│   │   ├── src/
│   │   │   ├── core/
│   │   │   │   ├── BitVCore.sol              # registry / address book
│   │   │   │   ├── PolicyEngine.sol
│   │   │   │   ├── RiskEngine.sol
│   │   │   │   └── AccessController.sol      # roles
│   │   │   ├── identity/
│   │   │   │   ├── CVIAdapter.sol
│   │   │   │   ├── CVAAdapter.sol
│   │   │   │   ├── CredentialCache.sol
│   │   │   │   └── SubAccountRegistry.sol
│   │   │   ├── bitscore/
│   │   │   │   ├── BitScoreOracle.sol
│   │   │   │   ├── ScoreBounds.sol
│   │   │   │   └── CreditLimitCurve.sol
│   │   │   ├── lending/
│   │   │   │   ├── LendingPool.sol
│   │   │   │   ├── MarketFactory.sol
│   │   │   │   ├── InterestRateModel.sol
│   │   │   │   ├── CreditLineManager.sol
│   │   │   │   ├── LiquidationEngine.sol
│   │   │   │   └── DefaultResolver.sol
│   │   │   ├── pools/
│   │   │   │   ├── VerifiedPoolFactory.sol
│   │   │   │   ├── VerifiedPool.sol
│   │   │   │   ├── PositionManager.sol
│   │   │   │   └── SwapRouter.sol
│   │   │   ├── vaults/
│   │   │   │   ├── PermissionedVault.sol     # ERC-4626 + gates
│   │   │   │   ├── StrategyRegistry.sol
│   │   │   │   ├── WithdrawalQueue.sol
│   │   │   │   └── strategies/
│   │   │   ├── rwa/
│   │   │   │   ├── RWARegistry.sol
│   │   │   │   ├── RWAValuationOracle.sol
│   │   │   │   └── RWAMarket.sol
│   │   │   ├── oracles/
│   │   │   │   ├── OracleRouter.sol
│   │   │   │   └── adapters/
│   │   │   ├── governance/
│   │   │   │   ├── BitVGovernor.sol
│   │   │   │   ├── Timelock.sol
│   │   │   │   └── GuardianCouncil.sol
│   │   │   ├── settlement/
│   │   │   │   ├── SettlementAdapter.sol     # restricted-asset routing
│   │   │   │   └── TravelRuleAttacher.sol
│   │   │   ├── interfaces/
│   │   │   └── libraries/                    # WadRayMath, TickMath, SafeCast
│   │   ├── test/{unit,integration,invariant,fork}/
│   │   ├── script/                           # deploy + param scripts
│   │   └── foundry.toml
│   │
│   ├── sdk/                          # published TS SDK
│   ├── shared/                       # zod schemas, constants, shared types
│   ├── abi/                          # generated from contracts — build artifact
│   └── config/                       # eslint, tsconfig, tailwind preset
│
├── docs/
│   ├── ARCHITECTURE.md               # this file
│   ├── CLEANVERSE-INTEGRATION-SPEC.md
│   ├── RISK-PARAMETERS.md
│   ├── SECURITY.md
│   └── adr/                          # architecture decision records
└── turbo.json
```

**Why `features/` and not `pages/`-adjacent code.** Vertical slices keep a change to lending inside one directory. Layer-first structures (`hooks/`, `components/`, `utils/`) force every feature change to touch five directories and make ownership boundaries impossible to enforce in CODEOWNERS.

---

## 7. Frontend architecture

**Next.js 15 App Router, React Server Components by default.**

**Rendering strategy — chosen per route by data trust:**

| Route class | Strategy | Reason |
|---|---|---|
| Marketing | Static / ISR | No dynamic data; ship fast, cache at edge. |
| `/markets`, `/risk` | RSC + short-revalidate ISR | Public protocol data, identical for all viewers, SEO-relevant. Server-rendered from the indexer, not the RPC. |
| `/app/*` | Client components + RSC shell | Per-wallet data. The shell (nav, layout) is server-rendered; position data is client-fetched because it is wallet-scoped and must be live. |
| Any write flow | Client only | Requires a signer. |

**Hard rule: financial numbers are never floats.** All amounts are `bigint` end-to-end. Formatting happens once, at the display boundary, in `lib/format`. A `number` in a balance path is a review-blocking defect. Percentages and rates use a fixed-point convention mirroring the contracts (WAD 1e18 / RAY 1e27) so frontend and contract math agree exactly.

**Data flow for reads.** Two sources with different characteristics, and the app must not confuse them:
- **Indexer (via tRPC)** — historical, aggregated, cross-user data. Fast, cacheable, may lag by a block or two.
- **RPC (via wagmi/viem)** — live, authoritative, per-user state at head. Used for anything the user is about to transact against: health factor, balances, allowances, quotes.

Any number that gates a transaction is read from the RPC and re-validated by simulation immediately before signing. Indexer data is never used to compute a health factor shown next to a "Borrow" button.

**Transaction lifecycle — a first-class abstraction, not per-feature code.**
```
build → simulate (eth_call/estimateGas) → present exact outcome → sign
      → submit → optimistic UI → confirm → invalidate query keys → settle
```
Every write goes through one `useProtocolTransaction` hook that owns this pipeline, including error decoding (custom errors → human strings), gas-limit setting, nonce handling, and replacement/speed-up. Simulation failures must block signing with a decoded reason — a user should never sign a transaction the app already knows will revert.

**Monad-specific frontend behaviour:**
- Sub-second blocks make optimistic UI feel native, but the app must distinguish *executed* from *finalized*. Monad's deferred execution means receipts are available shortly after execution; the UI shows "executed" immediately and "finalized" on the finality signal. Large-value flows (institutional deposits, RWA settlement) display finality explicitly rather than treating first confirmation as done.
- Monad charges gas on the **gas limit**, not gas used. The app must set tight, empirically-calibrated gas limits per action rather than padding generously — over-padding directly costs users money. Gas limits per entry point are measured in CI and stored in config, with a small safety margin, refreshed whenever contracts change.
- Batch approvals with actions (EIP-7702 delegation where wallet support permits) to cut the two-transaction approve/act pattern.

**Design system.** Black canvas, orange as a *functional* accent only — it marks the primary action, the active state, and the single most important number on a screen. If orange appears more than a few times per view it stops meaning anything. Montserrat for display/headings, Poppins for UI and body; tabular numerals mandatory for all figures so columns align and digits don't jitter on live updates. Framer Motion used for state transitions and value changes, never for decoration; every animation respects `prefers-reduced-motion`. Contrast targets WCAG AA minimum, AAA for numeric data.

**Accessibility & i18n.** Full keyboard operability on every transaction flow (institutional users are keyboard-driven). Screen-reader announcements for tx state changes. Number and date formatting locale-aware from day one — retrofitting `Intl` into a financial UI is expensive.

---

## 8. Backend architecture

The backend is **deliberately non-authoritative**. It exists for three things the chain cannot do well: aggregate history, compute expensive analytics, and talk to Cleanverse's off-chain APIs.

**Services:**

| Service | Responsibility | Failure mode if down |
|---|---|---|
| **Indexer** (Envio HyperIndex) | Consume Monad events → normalized Postgres | Historical views degrade; transacting still works via RPC. |
| **BitScore service** | Compute scores, sign attestations | Scores go stale; existing limits persist; no new limit increases. |
| **Risk service** | Stress tests, exposure analytics, param proposals | Governance loses tooling; on-chain guards unaffected. |
| **Compliance service** | Travel Rule payloads, reporting, attestation archive | Reporting delayed; settlement unaffected unless a policy requires synchronous Travel Rule (verify A5). |
| **Cleanverse gateway** | Authenticated client + cache for CVI/CVA APIs | Enrichment degrades; on-chain gates unaffected (they read on-chain credentials). |
| **Notification service** | Health alerts, maturity reminders, governance | Users lose warnings — treat as high-severity, since liquidation warnings are user-protective. |
| **Keeper network** | Liquidations, vault harvests, oracle nudges | Liquidations delayed — mitigated by keeping liquidation permissionless and incentivized so third parties fill the gap. |

**API surface.** tRPC for the first-party web app (end-to-end types, no schema drift), REST + OpenAPI for third parties and institutions (stable contract, tooling ecosystem), GraphQL only from the indexer. Three protocols is a choice, not an accident: each serves a consumer with different stability requirements.

**Idempotency and replay.** Every indexer handler is idempotent and keyed by `(txHash, logIndex)`. Reorg handling: Monad has fast single-slot finality, but the indexer must still handle reorgs before finality — it tracks finalized height and only marks data authoritative past it.

**Secrets.** The BitScore attestation signing key is the most sensitive off-chain secret in the system. It lives in an HSM/KMS, is never in application memory in raw form, signs only well-formed bounded payloads, and is rotatable on-chain under timelock without redeploying contracts.

---

## 9. Smart contract architecture

Solidity 0.8.2x, Foundry, EVM-bytecode-compatible target (Monad).

### 9.1 Contract map

```
                        ┌──────────────┐
                        │  BitVCore    │  address registry, version pointers
                        └──────┬───────┘
      ┌────────────┬───────────┼───────────┬─────────────┐
      ▼            ▼           ▼           ▼             ▼
┌───────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐ ┌────────────┐
│PolicyEngine│ │RiskEngine│ │BitScore │ │Oracle  │ │AccessCtrl  │
│           │ │          │ │ Oracle  │ │Router  │ │            │
└─────┬─────┘ └────┬─────┘ └────┬────┘ └───┬────┘ └────────────┘
      │            │            │          │
      │   ┌────────┴────────────┴──────────┴────────┐
      │   ▼                                          ▼
┌─────┴────────┐  ┌──────────────┐  ┌──────────┐  ┌──────────┐
│ LendingPool  │  │ VerifiedPool │  │Permission│  │RWAMarket │
│ (per market) │  │ (per pair)   │  │ edVault  │  │          │
└──────┬───────┘  └──────────────┘  └──────────┘  └──────────┘
       │
  ┌────┴─────────────┬──────────────────┐
  ▼                  ▼                  ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│CreditLineMgr │ │LiquidationEng│ │DefaultResolvr│
└──────────────┘ └──────────────┘ └──────────────┘

  Identity substrate, read by everything above:
  CVIAdapter · CVAAdapter · CredentialCache · SubAccountRegistry
```

### 9.2 Upgradeability

**UUPS proxies for stateful core contracts** (LendingPool, Vault, RWAMarket) — a protocol that will run for years and integrate an evolving external identity standard cannot be immutable without guaranteeing a painful migration. UUPS over Transparent: cheaper calls, upgrade logic in the implementation where it can be audited and eventually removed.

**Immutable for value-critical leaf logic** — `InterestRateModel`, `CreditLimitCurve`, oracle adapters, and math libraries are immutable and swapped by pointer under timelock. This gives the auditability of immutability (the deployed math cannot change under you) with the flexibility of upgrade (governance can point to new, separately audited math). Users can verify exactly which math their position is subject to.

**Never upgradeable:** Timelock, GuardianCouncil pause path. The emergency mechanism must not itself be an attack surface.

All upgrades: 48h minimum timelock, on-chain proposal with implementation address published in advance, guardian veto window.

### 9.3 Key interfaces (design sketch — not final)

```solidity
interface ICVIAdapter {
    struct Credential {
        bool     valid;
        uint16   jurisdiction;      // ISO-3166 numeric
        uint8    entityType;        // individual | accredited | institution
        uint8    tier;
        uint64   issuedAt;
        uint64   expiresAt;
        bool     sanctioned;
        bytes32  credentialId;      // Cleanverse-side reference
    }
    function credentialOf(address account) external view returns (Credential memory);
    function isValid(address account) external view returns (bool);
}

interface IPolicyEngine {
    // Reverts with a typed reason so the UI can explain the exact failure.
    function check(bytes32 policyId, address account, bytes calldata context) external view;
    function isPermitted(bytes32 policyId, address account, bytes calldata context)
        external view returns (bool, uint8 reasonCode);
}

interface IBitScoreOracle {
    function scoreOf(address account) external view returns (uint16 score, uint64 updatedAt);
    function creditLimitOf(address account, address asset) external view returns (uint256);
}
```

`check` reverting with a typed reason rather than returning a bool is intentional for the enforcement path — it makes it impossible to ignore the result at a call site. The `isPermitted` view exists purely so the frontend can render *why* an action is unavailable without simulating a revert.

### 9.4 Monad-aware contract design

- **Storage layout for parallelism.** Per-market state lives in per-market contracts (`MarketFactory` deploys one `LendingPool` per collateral asset) rather than a single monolithic pool with a mapping. Two users acting on different markets touch disjoint storage and execute in parallel. A monolithic design would make every borrow contend on shared slots and serialize under Monad's optimistic execution — losing exactly the property the chain is chosen for.
- **No global per-transaction counters.** Protocol-wide TVL and volume are derived by the indexer, not maintained on-chain. A single `totalProtocolTVL` slot updated by every action would be the worst possible contention point.
- **Interest accrual is lazy and per-market.** Accrue on interaction with per-market index variables, standard Aave/Compound-style, which keeps the write set small and market-local.
- **Gas-limit discipline.** Because Monad charges on gas limit, entry points are designed for *predictable* gas: bounded loops only, no unbounded array iteration, no dynamic-length liquidation batches. Every external function has a measured worst-case gas cost asserted in CI.
- **Events are the integration surface.** Rich, indexed events on every state change, designed alongside the indexer schema rather than after it.

---

## 10. Database schema (service plane, Postgres)

Not authoritative for value — a normalized projection of chain state plus off-chain-only data. Money amounts are `NUMERIC(78,0)` (raw base units, exact) and never floats.

```
-- Identity projection
identities(address PK, credential_id, jurisdiction, entity_type, tier,
           issued_at, expires_at, sanctioned, revoked_at, last_synced_at)
sub_accounts(id PK, entity_address FK, operator_address, role, limits JSONB, active)

-- BitScore
bitscore_snapshots(id PK, address FK, score, computed_at, model_version,
                   factors JSONB, attestation_sig, attested_onchain_at)
bitscore_events(id PK, address, event_type, weight, occurred_at, tx_hash)
  -- event_type: repayment_ontime | repayment_late | liquidated | default
  --             tenure_tick | volume_tier | cvi_tier_change
bitscore_disputes(id PK, address, snapshot_id, reason, status, resolved_at)

-- Markets (projection)
markets(id PK, chain_id, address, kind, collateral_asset, debt_asset,
        ltv, liquidation_threshold, liquidation_bonus, reserve_factor,
        supply_cap, borrow_cap, policy_id, paused, created_at)
market_state_hourly(market_id, ts, total_supply, total_borrow, utilization,
                    supply_rate, borrow_rate, index_supply, index_borrow)
  -- hypertable / time-partitioned

-- Positions (projection)
positions(id PK, address, market_id, collateral_amount, debt_amount,
          health_factor, opened_at, updated_at, block_number)
position_events(id PK, position_id, kind, amount, tx_hash, log_index UNIQUE, ts)
credit_lines(id PK, address, asset, limit_amount, drawn_amount, rate,
             opened_at, matures_at, status, terms_hash)

-- Pools
pools(id PK, address, token0, token1, fee_tier, access_tier, policy_id)
lp_positions(id PK, token_id, pool_id, owner, tick_lower, tick_upper, liquidity)

-- Vaults
vaults(id PK, address, asset, policy_id, total_assets, total_shares,
       share_price, capacity, mgmt_fee_bps, perf_fee_bps)
vault_strategies(id PK, vault_id, strategy_address, allocation_bps, cap, active)
withdrawal_queue(id PK, vault_id, address, shares, requested_at, fulfilled_at)

-- RWA
rwa_assets(id PK, asset_id, originator, cva_attestation_id, asset_class,
           jurisdiction, legal_wrapper_ref, custodian, status)
rwa_valuations(id PK, rwa_asset_id, value, currency, valued_at, attestor,
               attestation_sig)

-- Risk
oracle_readings(id PK, feed_id, price, published_at, source, deviation_bps)
risk_alerts(id PK, severity, market_id, kind, payload JSONB, ts, acknowledged_at)
stress_scenarios(id PK, name, params JSONB, created_by)
stress_results(id PK, scenario_id, market_id, metrics JSONB, run_at)

-- Compliance
travel_rule_records(id PK, tx_hash, originator_ref, beneficiary_ref,
                    payload_ref, status, submitted_at)
  -- payload_ref points to encrypted external storage, NOT inline PII
audit_log(id PK, actor, action, target, payload JSONB, ts)   -- append-only
compliance_exports(id PK, entity_address, period_start, period_end,
                   format, file_ref, generated_at)

-- Infra
indexer_cursor(chain_id PK, last_block, last_finalized_block, updated_at)
notifications(id PK, address, kind, payload JSONB, channel, sent_at, read_at)
```

**PII rule.** No raw personal data is stored by BitV. `identities` holds a Cleanverse credential *reference* and derived claims (jurisdiction, tier) — never names, documents, or account numbers. Travel Rule payloads live encrypted in dedicated storage with a pointer here. This keeps BitV's data-protection obligations minimal and means a database breach does not become an identity breach. Cleanverse remains the custodian of identity data; BitV consumes assertions about it.

**Retention & GDPR.** On-chain data is immutable and cannot be erased; therefore nothing erasable-by-right is ever put on-chain. Off-chain PII references support deletion, with the audit log retaining only pseudonymous references for the statutory period.

---

## 11. State management

Four categories, each with exactly one owner. Most frontend state bugs come from a value being managed in two places.

| State | Owner | Rationale |
|---|---|---|
| Server/chain data | **TanStack Query** | Caching, revalidation, dedup, background refresh — purpose-built. Never mirror it into a global store. |
| Wallet/connection | **wagmi** | Connector lifecycle, chain switching, account changes. |
| Ephemeral UI (modals, steps, form drafts) | **React local state / URL** | Shareable and back-button-correct when in the URL (`nuqs` for typed search params) — filters, selected market, ranges belong in the URL. |
| Cross-cutting client state (tx queue, notifications, prefs) | **Zustand**, small slices | Genuinely global, genuinely client-owned. |

**Query key factory** — centralized, hierarchical, so invalidation after a transaction is surgical:
```
['market', chainId, marketId]
['market', chainId, marketId, 'rates']
['position', chainId, address, marketId]
['bitscore', chainId, address]
```
A borrow invalidates `['position', chainId, address, marketId]` and `['market', chainId, marketId]` — not everything.

**Optimistic updates** are applied only to values the client can compute deterministically (own balance after a known transfer). Health factor, share price, and rates are **never** optimistically updated — they depend on other users' concurrent actions, and a wrong optimistic health factor is a number that gets someone liquidated while their screen says they're safe.

**Polling.** Sub-second blocks make naive polling expensive. Use WebSocket subscriptions for new heads and event logs; poll only as fallback. Stale times tuned per data class: prices 5s, rates 15s, positions on-event, historical 5min.

---

## 12. Authentication flow

BitV has **three distinct notions of "who"**, and conflating them is a common and serious design error:

1. **Wallet control** — proves key custody. Established by signature.
2. **Identity (CVI)** — proves who the key-holder is. Established by Cleanverse.
3. **Authorization** — proves this identity may do this action here. Established by PolicyEngine.

```
User connects wallet
   │
   ├─ Read-only browsing ────────────────────────► allowed, no auth at all
   │
   ├─ Session establishment (for backend reads: portfolio, score, exports)
   │    SIWE (EIP-4361) message, domain-bound, nonce'd, short expiry
   │    → backend verifies signature → issues HttpOnly, SameSite=Strict,
   │      Secure session cookie scoped to the address
   │    → session invalidated on account or chain change
   │
   ├─ Identity resolution
   │    CVIAdapter.credentialOf(address)   ← on-chain, authoritative
   │    backend enriches from Cleanverse API  ← display only, never gating
   │    ├─ no credential   → verification interstitial → Cleanverse onboarding
   │    ├─ expired         → refresh flow
   │    ├─ revoked         → restricted mode (§14.3)
   │    └─ valid           → proceed
   │
   └─ Authorization (per action, on-chain)
        PolicyEngine.check(policyId, account, context)
        UI pre-checks with isPermitted() for good UX;
        the contract enforces regardless.
```

**The critical property:** the SIWE session grants access to *BitV's backend reads*. It grants nothing on-chain. On-chain permission is derived solely from the credential attached to the address, evaluated inside the contract at execution time. There is no path where an authenticated API session influences a settlement decision — that separation is what makes the frontend untrusted (P2).

**Institutional multi-key.** `SubAccountRegistry` maps operator addresses to a parent entity credential with per-operator caps. Operators inherit the entity's CVI claims for policy purposes but carry independent limits. Registration and revocation of operators are on-chain, entity-signed, and event-logged for audit.

**Session keys.** For high-frequency institutional operations, scoped session keys (bounded by asset, amount, action, and expiry) avoid hot-walleting the master key. Enforced on-chain in `SubAccountRegistry`, not by the client.

---

## 13. Wallet connection flow

```
Connect → wagmi connector (injected, WalletConnect v2, Coinbase, Safe, embedded)
   │
   ├─ Chain check: Monad Testnet (10143) / Mainnet
   │    wrong chain → wallet_switchEthereumChain
   │    unknown chain → wallet_addEthereumChain with canonical params
   │
   ├─ Capability detection: EIP-5792 batching? EIP-7702 delegation?
   │    → if available, collapse approve+action into one user confirmation
   │
   ├─ Balance & allowance prefetch (multicall, one RPC round-trip)
   ├─ Credential resolution (§12)
   └─ Ready
```

**Connector rationale.** Safe support is mandatory, not optional — institutional treasuries operate through multisigs, and a protocol targeting institutional allocators that only supports EOAs excludes its primary market. Embedded wallets (Para or equivalent) matter for the retail on-ramp: a user completing bank-verified Cleanverse onboarding is unlikely to already hold a self-custodied wallet, and forcing seed-phrase management at that moment is where funnels die. The embedded path and the self-custody path converge on the same address-based credential model, so no protocol code branches on wallet type.

**Account/chain change handling.** Any account or chain change immediately: clears the SIWE session, invalidates all address-scoped queries, cancels pending transaction UI, and re-resolves credentials. Silent staleness here means showing one account's position while transacting from another.

---

## 14. Cleanverse integration points

> Subject to A1–A7 (§0).

### 14.1 Integration surface

| Point | Layer | Purpose |
|---|---|---|
| `CVIAdapter` | Contract | Resolve address → credential claims. Single choke point. |
| `CVAAdapter` | Contract | Resolve token/lot → origin attestation. Collateral eligibility. |
| `SettlementAdapter` | Contract | Route restricted-asset transfers so protocol flows respect token-level rules. |
| `TravelRuleAttacher` | Contract | Emit the reference data qualifying transfers require. |
| Cleanverse gateway | Backend | Authenticated REST client: credential detail, attestation lookup, Travel Rule submission. |
| Onboarding deep-link | Frontend | Hand-off to Cleanverse KYC with return URL and state. |
| Revocation listener | Backend + contract | Observe revocation, propagate to restricted mode. |

### 14.2 The adapter pattern is the whole point

Every Cleanverse touchpoint goes through an adapter interface owned by BitV. No core contract imports a Cleanverse type directly. Reasons: (a) A1–A7 are unverified and the adapter absorbs whatever the real API turns out to be; (b) Cleanverse will version its interfaces and BitV must upgrade one small audited contract rather than every market; (c) it permits a mocked adapter in tests and a mirrored adapter if Cleanverse is not natively on Monad (§14.5).

### 14.3 Credential lifecycle — the hard cases

The easy case is a valid credential. The design decisions live in the failure cases:

| Event | Policy | Reasoning |
|---|---|---|
| **Expiry** | Grace period (governance-set, e.g. 30d). Existing positions maintainable; new risk-increasing actions blocked. Repay/withdraw always allowed. | Expiry is usually administrative, not adverse. Force-closing positions over a paperwork lapse is user-hostile and creates a liquidation cascade risk from a non-market event. |
| **Revocation (non-sanctions)** | Immediate restricted mode: no new positions, no increases. Repay, close, withdraw permitted. | Revocation may be adverse, but trapping user funds is both a legal and reputational catastrophe. Exit must always be open. |
| **Sanctions hit** | Freeze all account actions; route to governed resolution; assets remain custodied pending lawful instruction. | This is the one case where exit cannot be automatic — releasing funds to a sanctioned party is a legal violation. Requires an explicit, auditable, governance/legal-controlled path. **Confirm required handling with counsel and Cleanverse.** |
| **Tier downgrade** | New actions at new tier; existing positions grandfathered until close. | Retroactive repricing of live positions breaks the terms the user agreed to. |

**Non-negotiable invariant across all of the above: a user can always repay debt and always withdraw non-encumbered assets, except under a lawful sanctions freeze.** Any policy that can trap solvent user funds for administrative reasons is rejected.

### 14.4 The restricted-asset custody problem (assumption A4)

If Cleanverse A-tokens only transfer between credentialed wallets, then BitV's pool and vault contracts must themselves hold credentials, or be explicitly whitelisted as protocol contracts. This affects:
- Pool/vault custody of user deposits.
- Liquidators receiving seized collateral (§5.6, §17.6).
- Flash-loan-style atomic flows, which may be impossible for restricted assets.

**This is the single highest-risk unknown.** Resolve it in Milestone 0 by direct confirmation with Cleanverse. If contracts cannot be credentialed, the fallback is a custody model where restricted assets are held in per-user credentialed escrow contracts with the pool holding claims rather than tokens — materially more complex, so it must be known before contract work begins, not discovered during it.

### 14.5 If Cleanverse is not natively on Monad (A7)

Fallback: BitV deploys a `MirroredCVIRegistry` on Monad, written by a Cleanverse-operated attestor set (threshold-signed), with credential state mirrored from the canonical chain. This introduces a trust assumption (the attestor set) and latency (mirror lag), both of which must be disclosed prominently on `/risk`. Prefer native.

---

## 15. Monad integration points

**Why Monad for this protocol specifically.** Identity-gated DeFi does strictly more work per transaction than permissionless DeFi — every action carries credential resolution and policy evaluation on top of the financial math. On a chain with expensive execution that overhead is prohibitive; Monad's high throughput and low fees make identity-as-a-primitive economically viable rather than a tax. Fast finality additionally matters for a protocol targeting institutional settlement, where sub-second finality is closer to the settlement guarantees institutions expect.

| Monad property | How BitV uses it | Design consequence |
|---|---|---|
| **Parallel optimistic execution** | Per-market contract sharding; disjoint write sets | No global counters; no monolithic pool; no shared hot slot. Contention silently serializes. |
| **~sub-second blocks, fast finality** | Responsive UX; real-time liquidations | UI distinguishes executed vs finalized; large flows wait for finality. |
| **Deferred execution (state root lags)** | Reads at head are correct; root-based proofs are not | Don't build anything on state-root-at-head assumptions; indexer tracks finalized height separately. |
| **Gas charged on gas limit** | Tight, measured gas limits per entry point | Predictable-gas contract design; CI asserts worst-case gas; frontend never over-pads. |
| **Full EVM bytecode compatibility** | Foundry, viem, wagmi, OpenZeppelin work unmodified | No custom toolchain risk. Standard audit firms can review. |
| **Low fees** | Frequent health checks, granular liquidations, fine-grained events | Partial liquidations become economical, which is better for borrowers. |

**Operational integration:** multiple RPC providers with automatic failover (single-provider dependency is an availability risk for a protocol); WebSocket subscriptions for heads and logs; multicall aggregation for read batching; a canonical `contracts.json` registry per chain published in the SDK and on `/developers/contracts`.

---

## 16. BitScore architecture

BitScore is the mechanism that makes under-collateralized lending safe. Its design must survive an adversary who wants to farm a high score cheaply and then default.

### 16.1 Hybrid model, and why

| Component | Source | Weight (initial) | Why |
|---|---|---|---|
| Repayment history | On-chain | 35% | The strongest predictor. Costly to fake — requires real capital and real time. |
| Credit utilization | On-chain | 15% | Consistently over-drawn lines predict distress. |
| Protocol tenure & activity | On-chain | 15% | Sybil resistance through time cost. |
| CVI tier & attributes | Cleanverse | 20% | Real-world identity strength; institutional vs retail. |
| Collateral quality & diversity | On-chain | 10% | Behavioural risk appetite signal. |
| Liquidation/default history | On-chain | -∞ (penalty) | Asymmetric: defaults must dominate. |

Weights are governance parameters, versioned, and every score records the `model_version` that produced it — a score is not comparable across model versions, and pretending otherwise corrupts historical analysis.

### 16.2 Compute pipeline

Off-chain, because the model must evolve and on-chain computation of a multi-factor decaying model is neither affordable nor upgradeable at the required cadence.

```
Indexer events + Cleanverse claims
   → feature extraction (windowed, decayed)
   → scoring model (versioned, deterministic, reproducible from inputs)
   → bounds check against on-chain constraints
   → sign attestation (HSM key)
   → submit to BitScoreOracle (batched)
   → contracts read score
```

**Determinism requirement:** given the same inputs and model version, the score must be byte-identical. Scores are reproducible by third parties from public event data plus the (public) model spec — the only non-public input is the Cleanverse tier component. This is what makes the score auditable and the dispute process meaningful.

### 16.3 Decay and recency

Positive signal decays (a perfect record from two years ago with no activity since is weak evidence today). Negative signal decays more slowly, and defaults decay slowest — asymmetry is correct here, because the cost of under-weighting a default is a loss and the cost of over-weighting it is a missed loan.

### 16.4 On-chain bounds — the critical security control

The scorer is off-chain and therefore compromisable. `BitScoreOracle` enforces, in the contract, constraints a compromised signer cannot exceed:

- **Rate limit:** max score increase per update per account (e.g. +25 points).
- **Cooldown:** minimum interval between updates per account.
- **Global cap:** max aggregate credit extended protocol-wide, independent of scores.
- **Per-account absolute cap:** credit limit ceiling regardless of score.
- **Staleness:** scores older than N hours are treated as their floor value, not their last value.
- **Signer set:** threshold multi-sig over score batches, not a single key.
- **Guardian kill-switch:** freeze all score updates and fall back to last-known-good.

Score *decreases* are not rate-limited — a compromised signer lowering scores is a denial-of-service, not a theft, and the reverse asymmetry would let an attacker delay the recording of a real default.

**The security property:** a fully compromised BitScore service cannot drain the protocol. It can, at worst, extend somewhat more credit than deserved, bounded by the global cap and rate limits, over a period long enough for guardians to intervene.

### 16.5 Score → terms

Credit limit and rate discount are **monotonic, continuous, on-chain curves** (`CreditLimitCurve`, immutable, swappable under timelock). Continuity matters: a step function creates a cliff where one point of score changes a user's limit discontinuously, which invites gaming right at the boundary and produces terrible user experience.

### 16.6 Explainability and dispute

Every score shows its factor breakdown and the specific events driving it. Users can dispute via `/app/bitscore`; disputes are logged, reviewed, and resolvable with a corrective attestation. This is not a nicety — a credit-scoring system that affects access to capital and cannot explain itself is a regulatory problem in most jurisdictions BitV would operate in.

---

## 17. Lending engine architecture

### 17.1 Isolated markets

One `LendingPool` per collateral asset, deployed by `MarketFactory`. Rationale: (a) risk containment — a bad collateral asset cannot contaminate the whole protocol; (b) Monad parallelism — disjoint state per market; (c) governance velocity — new collateral requires deployment and parameters, not modification of a shared contract; (d) auditability — one market's parameters are legible in isolation.

Cost: fragmented liquidity. Mitigated by a shared supply layer for the debt asset across markets, with per-market borrow caps controlling exposure.

### 17.2 Accounting

Index-based, Aave/Compound lineage — well-understood, extensively audited patterns. Interest accrues lazily on interaction. Supply and borrow indices are RAY (1e27) precision; balances are scaled by index. **Rounding always favours the protocol** — every rounding direction is asserted in tests, because rounding-direction bugs are a standard drain vector.

### 17.3 Interest rate model

Two-slope utilization curve (base + slope1 below optimal, steep slope2 above) providing strong incentive to restore liquidity above the kink, **plus an identity-tier discount** applied at the account level, not the market level. Market rates remain a clean function of utilization (so suppliers can reason about yield); the discount is a per-borrower adjustment funded by the reserve factor. Keeping these separate prevents the identity discount from distorting market-level rate signals.

### 17.4 Under-collateralized credit lines

Distinct from collateralized borrowing, in `CreditLineManager`:

- **Limit** = `CreditLimitCurve(score)` ∩ per-account cap ∩ global uncollateralized cap.
- **Revolving:** draw and repay freely up to the limit; interest on drawn balance only.
- **Tenor:** fixed maturity with renewal on good standing. Perpetual uncollateralized debt with no maturity has no forcing function for repayment.
- **Covenants:** on-chain checks (utilization ceilings, minimum score maintenance) that trigger freeze-on-breach — the line stops extending new credit before it becomes a loss.
- **Under-collateralized ≠ uncollateralized:** partial collateral tiers exist between 0% and 100%, and most credit lines should sit there. The score determines how far below 100% a borrower may go.
- **Global cap:** total uncollateralized exposure is capped protocol-wide as a fraction of TVL, hard-coded as a bound and adjustable only under timelock. This is the ultimate backstop on the entire credit thesis.

### 17.5 Liquidation

- **Partial by default** — close factor caps the fraction liquidatable in one call. Full liquidation on a small breach is punitive and unnecessary; Monad's low fees make partial liquidation economically viable where it isn't on expensive chains.
- **Dutch-auction bonus** — liquidation incentive starts small and increases with time/severity, rather than a fixed fat bonus. Minimizes borrower loss while guaranteeing liquidation eventually clears.
- **Identity-aware grace** — verified borrowers in good standing get a short, governance-parameterized grace window with notification before liquidation, applied **only** when the position is marginally underwater and market conditions are not fast-moving. Hard-bounded: grace is disabled below a severity threshold and during oracle-flagged volatility. Grace that can grow bad debt is a bug, not a feature; this must be modelled in stress tests before enabling.
- **Permissionless execution** — anyone can liquidate (§5.6). Non-negotiable.

### 17.6 Restricted-collateral liquidation

Where seized collateral is a transfer-restricted CVA asset and the liquidator lacks the required credential, `SettlementAdapter` runs a secondary auction to credentialed bidders and pays the original liquidator in an unrestricted asset. This preserves permissionless liquidation despite permissioned collateral. It adds latency, so restricted collateral carries a higher liquidation-bonus parameter and a lower LTV to compensate.

### 17.7 Default & loss

`DefaultResolver`: mark default → freeze account across products → BitScore penalty → off-chain recourse via CVI identity linkage (the actual value of identity-based lending: there is a real party to pursue) → residual loss absorbed by market reserves, then a protocol backstop, then socialized as a last resort with explicit, pre-disclosed waterfall ordering. Suppliers must be able to read this waterfall on `/risk` before depositing.

---

## 18. Yield vault architecture

**ERC-4626 with permissioned entry.** Standard-compliant so the vault composes with existing tooling, wrapped with policy gates on `deposit`/`mint`/`withdraw`/`redeem`. Note the deliberate tension: strict ERC-4626 assumes permissionless transfer. BitV vault shares are transfer-restricted to policy-satisfying addresses — documented as an intentional deviation, because unrestricted shares would let anyone buy exposure to a permissioned vault on the secondary market and void the permission entirely.

**Multi-strategy allocation** via `StrategyRegistry`: each strategy has an allocation target, a hard cap, and independent pause. Strategies are separately audited contracts, added under timelock. A vault is an allocator, not a strategy — this separation means adding a strategy never touches vault accounting code.

**Withdrawal queue** for strategies with non-instant liquidity (notably RWA). Users request, receive a queue position and ETA, and are fulfilled FIFO as liquidity returns. The alternative — first-mover-advantage bank runs — is how vaults with illiquid backing fail.

**Share price manipulation defence:** virtual shares/assets offset on the first deposit (standard ERC-4626 inflation-attack mitigation), plus a minimum initial deposit burned to the zero address at vault creation.

**Fees:** management fee accrued continuously against assets, performance fee on realized gains above a high-water mark. High-water mark is mandatory — without it, a strategy that loses and recovers charges performance fees on recovering the investor's own money.

**Circuit breakers:** per-vault loss thresholds that auto-pause deposits and strategy allocation when share price drops beyond a bound in a window.

---

## 19. Liquidity pool architecture

**Concentrated liquidity (Uniswap v3 lineage).** Capital efficiency matters more here than elsewhere: gated pools have a structurally smaller LP set than permissionless pools, so each unit of liquidity must work harder to achieve competitive depth. Full-range AMMs would make verified pools uncompetitively thin.

**Three access tiers**, bound per-pool to a `policyId`:
- **Open** — anyone may swap; LP gated. Bootstraps volume while keeping LPs verified.
- **Verified** — swap and LP both require CVI.
- **Institutional** — entity-tier CVI required for both.

**LP position NFTs carry the pool's transfer policy.** If a position in a verified pool can be sold to an unverified party, the gate is decorative. Transfer restrictions on the position NFT mirror the pool policy exactly.

**CVA-only pools** where both assets must carry origin attestation — the "clean liquidity" product, and the pools institutional counterparties can actually route through.

**Fee tiers** per pair volatility (stable / standard / exotic), with a governance-controlled protocol fee switch on a portion of LP fees.

**Oracle:** TWAP available from pool observations, but **never used as a sole price source for liquidations**. Pool TWAPs on a low-liquidity gated pool are manipulable; the `OracleRouter` requires an independent primary feed with the TWAP serving only as a deviation sanity check.

**Monad note:** swaps in a concentrated-liquidity pool contend on tick and liquidity state, so swaps in the *same* pool serialize regardless. Parallelism is realized across different pools — another reason for per-pool contracts rather than a singleton.

---

## 20. Risk engine architecture

Split by necessity: enforcement must be on-chain (P2), analysis is too expensive to be.

### 20.1 On-chain (`RiskEngine`) — enforcement
- Account health: `Σ(collateral × price × liqThreshold) / Σ(debt × price)`.
- Borrow/supply caps per market.
- Per-identity exposure caps (aggregate across markets, keyed to the CVI credential — this is only possible *because* identity is a primitive; permissionless protocols cannot cap per-person exposure at all).
- Oracle staleness and deviation rejection.
- Global uncollateralized-exposure cap.
- Pause states per market and protocol-wide.

### 20.2 Oracles (`OracleRouter`) — the most common exploit vector
- Multiple independent sources per asset with median aggregation.
- Staleness bounds: reject readings older than a per-asset threshold; **fail closed** (block new borrows) rather than open.
- Deviation circuit breaker: reject readings deviating beyond a bound from the previous, pause the market, alert guardians.
- Fallback hierarchy per asset, explicitly ordered and published on `/risk/oracles`.
- RWA valuations from an attestor set with threshold signatures, longer validity windows reflecting genuine off-chain valuation cadence, and correspondingly conservative haircuts.

### 20.3 Off-chain (Risk service) — analysis
- Continuous health sweeps and pre-liquidation alerting to users.
- Monte Carlo stress testing across correlated price shocks, producing expected bad debt per scenario.
- Correlation and concentration monitoring (e.g. many "distinct" borrowers with correlated collateral).
- Parameter proposals with simulation output attached to governance proposals — no risk-parameter change ships without a published simulation.
- Under-collateralized portfolio surveillance: cohort default rates by score band, used to validate and recalibrate the BitScore model against realized outcomes. **If realized defaults by score band don't match model predictions, the credit thesis is wrong and the global cap must come down.** This feedback loop is the most important thing the risk service does.

### 20.4 Circuit breakers
Layered and independent: per-market pause, per-asset oracle breaker, vault loss breaker, score-update freeze, protocol-wide pause. Each triggerable by guardians without governance delay, each requiring governance to *un*-trigger. Asymmetry is intentional — stopping should be fast and easy, restarting should be deliberate.

---

## 21. Security considerations

### 21.1 Threat model

| Threat | Vector | Mitigation |
|---|---|---|
| Oracle manipulation | Thin gated-pool TWAP, flash-loan price moves | Multi-source median, deviation breakers, no sole-TWAP pricing, fail-closed staleness |
| BitScore compromise | Signer key theft, model gaming | On-chain bounds (§16.4), threshold signing, HSM, global caps, kill-switch |
| Sybil credit farming | Many identities farming small lines | CVI is bank-verified and non-transferable; per-identity aggregate caps; tenure weighting; global uncollateralized cap |
| Credential bypass | Selling a position/share to an unverified party | Transfer restrictions on LP NFTs and vault shares matching pool/vault policy |
| Reentrancy | Callback tokens, strategy hooks | CEI ordering, reentrancy guards, no untrusted external calls mid-state-update, strategies allowlisted |
| Rounding drain | Repeated favourable-rounding operations | All rounding favours protocol; asserted in invariant tests |
| Governance capture | Token accumulation | Timelock, guardian veto, hard-bounded parameter ranges in code, quorum requirements |
| Upgrade abuse | Malicious implementation | UUPS with 48h timelock, published implementation, guardian veto, immutable emergency path |
| First-depositor inflation | Empty-vault share manipulation | Virtual offsets, burned initial deposit |
| Bad debt cascade | Correlated collapse | Isolated markets, exposure caps, partial liquidation, disclosed loss waterfall |
| PII exposure | Backend breach | No raw PII stored; references only; encrypted Travel Rule storage |
| Frontend compromise | DNS/supply-chain, malicious tx injection | Simulation before signing with decoded outcome, SRI, CSP, dependency pinning, published contract addresses, IPFS mirror of the app |

### 21.2 Practices
- **Invariant testing (Foundry) is mandatory**, not optional: solvency (`Σ supplied ≥ Σ borrowed + reserves`), share price monotonicity absent losses, health-factor consistency, index monotonicity, no-negative-balance. Invariants catch the class of bug that unit tests structurally cannot.
- Fork testing against Monad testnet state for every integration.
- Two independent audits before mainnet; a third for the credit-line and BitScore path specifically, since that is novel and unbattle-tested.
- Public bug bounty scaled to TVL, live before mainnet.
- Formal verification of the core accounting library and `BitScoreOracle` bounds.
- Staged mainnet rollout with TVL caps that lift on a schedule tied to observed behaviour, not calendar dates.
- Incident response runbook with named on-call, guardian key ceremony documented, and a rehearsed pause drill.
- Monitoring: on-chain invariant watchers alerting in real time, separate from the app's own metrics.

### 21.3 The honest risk statement
Under-collateralized lending is a genuinely novel risk that no amount of architecture eliminates. Identity gives recourse; it does not give repayment. The protocol's defence is layered caps — per-account, per-identity, global — such that a *complete* failure of the credit thesis is a bounded, survivable loss to the reserve and backstop rather than an insolvency. That bound should be set conservatively at launch and raised only against realized cohort performance data (§20.3). This should be stated plainly in public documentation; sophisticated allocators will trust the protocol more for saying it, not less.

---

## 22. Scalability strategy

**Contracts.** Per-market and per-pool sharding for parallel execution; no global mutable counters; O(1) or bounded-loop operations only; lazy accrual; events over storage for anything derivable.

**Indexer.** Envio HyperIndex for throughput on a fast chain; time-partitioned tables for state history; materialized views for expensive aggregates; idempotent handlers keyed by `(txHash, logIndex)`; finality-aware cursors.

**Backend.** Stateless services behind a load balancer; Redis for hot reads and rate limiting; BullMQ for background jobs; horizontal scale on the scoring and risk services (both are embarrassingly parallel per-account).

**Frontend.** RSC and edge caching for public data; aggressive multicall batching; WebSocket over polling; route-level code splitting; per-route revalidation tuned to data volatility.

**Data.** Read replicas for analytics; hot/cold partitioning of position history; archival of finalized historical state to cheaper storage with on-demand rehydration.

**Organizational scalability** — often the binding constraint: the monorepo with generated ABIs and shared types means a contract interface change surfaces as a TypeScript compile error in the app rather than a runtime failure in production. CODEOWNERS per feature slice. ADRs in `docs/adr/` so a decision made in month two is legible in month twenty.

---

## 23. Development milestones

**M0 — Foundations & de-risking (2 weeks)**
Resolve A1–A7 with Cleanverse; produce `CLEANVERSE-INTEGRATION-SPEC.md`. Monorepo, CI, Foundry harness, design system tokens, `contracts.json` registry. **Gate: A4 (restricted-asset custody) resolved before any custody contract is written.**

**M1 — Identity substrate (3 weeks)**
`CVIAdapter`, `CVAAdapter`, `PolicyEngine`, `AccessController`, `SubAccountRegistry`, mock adapters for testing. Wallet connection, SIWE, credential resolution, verification gate UI. **Gate: a policy-gated action provably unbypassable via direct contract call.**

**M2 — Lending core, over-collateralized (4 weeks)**
`MarketFactory`, `LendingPool`, `InterestRateModel`, `OracleRouter`, `RiskEngine`, `LiquidationEngine`. Full invariant suite. Supply/borrow/repay/liquidate UI. Indexer for lending events. **Gate: solvency invariants pass under fuzzing; permissionless liquidation demonstrated.**

**M3 — BitScore (3 weeks)**
Scoring service, attestation pipeline, `BitScoreOracle` with full bounds, `CreditLimitCurve`. Score UI with factor explainability. **Gate: a simulated compromised signer cannot exceed on-chain bounds.**

**M4 — Under-collateralized credit (3 weeks)**
`CreditLineManager`, `DefaultResolver`, covenants, global caps, maturity and renewal. Credit line UI and notifications. **Gate: stress-tested bad-debt bound under the global cap; disclosed loss waterfall published.**

**M5 — Verified pools (3 weeks)**
`VerifiedPoolFactory`, `VerifiedPool`, `PositionManager`, `SwapRouter`, restricted LP NFTs, tiered access. Swap and LP UI. **Gate: position-NFT transfer restrictions verified against pool policy.**

**M6 — Permissioned vaults (3 weeks)**
`PermissionedVault`, `StrategyRegistry`, `WithdrawalQueue`, fee accounting with high-water mark, first strategies. Vault UI. **Gate: inflation-attack and bank-run scenarios tested.**

**M7 — RWA lending (4 weeks)**
`RWARegistry`, `RWAValuationOracle`, attestor set, `RWAMarket` (isolated), legal wrapper references, amortization. Originator and deal UI. **Gate: legal review of wrapper linkage complete.**

**M8 — Institutional & compliance (3 weeks)**
Institutional console, sub-accounts, session keys, `TravelRuleAttacher`, reporting exports, `SettlementAdapter` restricted-asset routing. **Gate: end-to-end compliance export accepted by a design-partner institution.**

**M9 — Governance & risk ops (2 weeks)**
`BitVGovernor`, `Timelock`, `GuardianCouncil`, risk committee bounds, `/risk` and `/governance` surfaces, monitoring and alerting, incident runbook + rehearsed pause drill.

**M10 — Hardening & launch (4+ weeks)**
Two audits + credit-path third audit, formal verification of accounting and score bounds, bug bounty live, testnet incentivized program, staged mainnet with TVL caps.

Roughly 34 weeks of critical path; M5/M6 can parallelize with M3/M4 given separate contract and frontend workstreams.

---

## 24. Recommended implementation order

**Sequenced by dependency and by risk-retired-per-week**, not by visible progress. The unusual choice is putting Cleanverse verification before everything: A4 alone can invalidate the custody model, and discovering that during M6 costs months.

1. **Verify Cleanverse assumptions A1–A7.** Blocking. Nothing downstream is safe to build until A4 is answered.
2. **Monorepo, CI, Foundry harness, ABI codegen pipeline.** Cheap, and every later step compounds on it.
3. **Design system + brand tokens.** Before feature UI, so nothing needs retrofitting.
4. **Identity substrate contracts + mock adapters.** The primitive everything else calls.
5. **Wallet connection, SIWE, credential resolution.** Unblocks all authenticated UI.
6. **Oracle router + risk engine skeleton.** Lending cannot be written safely without pricing and health.
7. **Lending core, over-collateralized, with full invariant tests.** The financial nucleus. Do not proceed until invariants hold under fuzzing.
8. **Indexer + tRPC read layer.** Now that there are meaningful events.
9. **Lending UI end-to-end, including liquidation console.** First complete user journey; validates the whole stack.
10. **BitScore service + oracle with bounds.** Only meaningful once there is repayment history to score.
11. **Credit lines.** The flagship. Requires 7 and 10.
12. **Verified pools** (parallelizable with 10–11).
13. **Permissioned vaults** (parallelizable).
14. **RWA lending.** Highest external dependency and legal surface; sequence after the core is stable.
15. **Institutional console + compliance export.**
16. **Governance, guardians, risk operations.**
17. **Audits, formal verification, bounty, staged launch.**

**The one thing to get right first:** step 4, the identity substrate. Every gate, every policy, every credit decision reads from it. If that interface is wrong, every contract above it is wrong — and unlike a parameter, an interface change late in the build is a rewrite.
