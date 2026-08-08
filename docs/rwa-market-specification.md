# BitV RWA-Backed Market Specification (Build 06)

**Status: design specification only. No Solidity has been written or
modified for this milestone.** Every existing contract
(`BitVPoolManager`, `BitVLendingManager`, `BitVComplianceGuard`,
`BitScoreManager`, `BitVYieldVault`, `BitVTreasury`,
`BitVAccessManager`) is unmodified.

This document is deliberately conservative about Cleanverse, per the
same discipline established in `docs/cleanverse-integration.md`: every
CVI claim traces to the CVI Integration Guide V2 already implemented;
every CVA claim traces to the CVA Integration Guide already summarized
in §3 of that document. Nothing here invents a CVA contract address, a
CVA API, or an RWA-verification field Cleanverse hasn't documented. Where
Cleanverse doesn't expose something on-chain, this spec designs a
BitV-controlled registry boundary instead of pretending otherwise.

---

## 1. Purpose

Extend BitV's permissioned lending engine so verified users can post
**verified real-world-asset (RWA) tokens** as collateral, subject to the
same identity gating (CVI) and an additional BitV-controlled asset
verification/freeze layer, and borrow BitV's existing approved debt
assets (e.g. the debt-side pools already implemented) against that
collateral — reusing the existing pool/lending/liquidation engine rather
than building a parallel one.

Out of scope for this milestone: Solidity implementation, deployment,
and issuing BitV's own CVA (BitV is a *consumer* of verified assets
here, not an issuer, mirroring the existing conclusion in
`docs/cleanverse-integration.md` §3 that "BitV isn't issuing a CVA this
milestone").

## 2. RWA market architecture

**Architecture decision: (B) a dedicated `BitVRWACollateralRegistry`
contract, connected to the existing `BitVLendingManager` via a narrow,
optional, fail-safe interface — not (A) extending
`BitVLendingManager` directly.**

**Option A — extend BitVLendingManager directly** (add RWA-specific
fields/logic inline: asset-verification checks, freeze flags, oracle
staleness handling, all inside the existing collateral/borrow/repay/
liquidate functions).
- *Benefit*: no new contract, no new cross-contract call surface.
- *Risk*: `BitVLendingManager` is already the most complex, most
  security-critical contract in the protocol (cross-margin, multi-asset,
  health-factor, BitScore integration). Inlining RWA-specific
  verification/freeze/staleness logic directly into it grows that
  complexity further and risks destabilizing already-tested lending
  paths for collateral types that were never RWA to begin with. It also
  duplicates exactly the kind of "narrow optional dependency" pattern
  BitScore already established successfully as a *separate* contract —
  reversing that pattern here would be inconsistent with the codebase's
  own precedent.

**Option B — dedicated `BitVRWACollateralRegistry`, connected via
interface** (this specification's choice).
- *Benefit*: mirrors the `BitScoreManager` integration pattern exactly
  (Build 04) — a narrow interface (`IRWACollateralRegistry`,
  §6), optional (`address(0)`-disableable), `try`/`catch`-wrapped at
  every call site, fail-safe to the most conservative outcome on any
  failure. `BitVLendingManager`'s own already-tested collateral/borrow/
  liquidate logic is **reused unmodified** — an RWA asset is still just
  a `BitVPoolManager` pool with `isCollateralEnabled = true`, subject to
  the exact same LTV/health-factor/liquidation math every other
  collateral asset uses. The registry only adds a **gate in front of**
  that existing machinery: is this specific asset currently a
  registered, verified, non-frozen RWA collateral, and is its oracle
  fresh? A "no" answer forces `BitVLendingManager` to treat that
  asset's collateral value as unavailable for *new* borrowing capacity
  (§9, §12) without touching how collateral/debt accounting itself
  works for every other asset.
- *Risk*: one more contract, one more cross-contract call per protected
  action. Mitigated the same way BitScore's equivalent risk was
  mitigated: the call is a bounded, `try`/`catch`-wrapped `view`/light
  call, not a re-entrant economic action.

**Why B is the smallest architecture that avoids duplication**: it does
NOT create a second lending engine, a second collateral-accounting
system, or a second liquidation engine — those are still 100%
`BitVPoolManager`/`BitVLendingManager`. It adds exactly one new
responsibility (asset verification + freeze + oracle-staleness gating)
in exactly one new, narrowly-scoped contract, following the same
integration shape the codebase already validated with BitScore.

```
User
  │
  ▼
BitVComplianceGuard (CVI — unchanged, existing)
  │
  ▼
BitVLendingManager (unchanged core logic)
  │  consults, optionally, try/catch, fail-safe
  ▼
BitVRWACollateralRegistry (NEW)
  │  "is this asset's collateral currently usable for NEW borrowing capacity?"
  │  — registration, verification status, freeze state, oracle staleness
  ▼
BitVPoolManager (unchanged — the RWA asset is just another pool)
```

## 3. Cleanverse integration

Two, deliberately separate, Cleanverse touchpoints — exactly matching
this task's stated principle:

- **CVI** (`IAPassComplianceValidator.complianceVerify`, via the
  existing `BitVComplianceGuard`) — answers "is this participant
  eligible to use the protocol at all." Unchanged from every other BitV
  contract; the RWA market is compliance-gated exactly like pools/
  lending/vaults (§14).
- **CVA** (per `docs/cleanverse-integration.md` §3) — a confirmed
  Cleanverse primitive for *issuing* a compliant token, whose transfers
  are automatically compliance-gated at the token level (`_update`
  calling `IATokenPolicy.canTransfer`). **BitV does not issue CVA in
  this milestone.** Where an RWA collateral token happens to *be* a
  Cleanverse-issued CVA, BitV's registry records that fact (§7) but does
  not re-implement CVA's own compliance gating — per the CVI guide's
  §4.5 "CVA automatic compliance" mode already documented in
  `docs/cleanverse-integration.md`, a CVA token's own transfer hook
  already handles that leg, and BitV would only need to ensure the
  relevant pool/registry contract is itself registered with Cleanverse
  (`registerApass`) to hold/transfer it — an off-chain operational step,
  not new Solidity logic.

**No RWA collateral token in this specification is assumed to be a CVA
by default.** Whether a given registered RWA asset is a CVA is a
per-asset fact recorded in the registry (§6's `AssetConfig.isCVA` field)
and only ever set `true` when Cleanverse confirms that specific token's
CVA registration — mirroring the yield-vault specification's identical
discipline (`docs/yield-vault-specification.md` §5/§10) for exactly the
same reason: this repository cannot self-certify a Cleanverse fact.

## 4. CVI integration

Unchanged. Every protected RWA action (§14) calls
`BitVComplianceGuard._requireCompliance(msg.sender)` — the *same*
compliance guard instance `BitVLendingManager` already uses (the RWA
market does not introduce a second, parallel compliance validator or
rule set). No new CVI fields are invented; `RuleV2`
(`allowedGroup`/`allowedSubGroup`/`minTier`/`minSubTier`/
`poolCountryBitmap`) is used exactly as documented.

## 5. CVA integration

Per §3 above: **evaluated for RWA collateral, loan settlement,
repayment, liquidation, and recovery — not implemented beyond an
adapter boundary, since Cleanverse's documented CVA mechanics only
confirm token-issuance-time compliance gating, not a lending-specific
settlement/recovery protocol.**

| Use case | CVA relevance | Resolution |
|---|---|---|
| RWA collateral | If the collateral token is itself a Cleanverse-issued CVA, its own transfer hook already compliance-gates every `transferFrom` the pool performs (deposit/withdrawal/liquidation seizure) — confirmed per §4.5 of the CVI guide. BitV's registry records `isCVA` per asset (§6) purely as metadata; it changes nothing about how `BitVPoolManager` moves the token. | No new BitV logic needed — CVA's own hook does the work, if and when a specific registered asset is confirmed to be one. |
| Loan settlement / repayment | Nothing in either guide describes a CVA-specific settlement or repayment mechanic distinct from a normal ERC-20 `transfer`/`transferFrom`. | Repayment uses the existing debt-asset transfer path unchanged; no CVA-specific repayment logic is invented. |
| Liquidation | Seizing CVA collateral during liquidation is, per the same automatic-compliance mode, just a `transferFrom` that the CVA token itself compliance-gates on the *recipient* (the liquidator) — meaning **a liquidator who is not CVI-compliant could have a CVA-backed liquidation revert at the token level**, a real RWA-specific liquidation consideration flagged in §12. | Documented as an integration dependency requiring confirmation of exact CVA transfer-hook revert behavior before implementation — not fabricated here. |
| Recovery (bad debt / insolvency) | Not addressed by either Cleanverse guide at all — recovery of value from a frozen or delisted RWA asset after bad debt is entirely a BitV-internal problem (§13). | No CVA mechanism invoked; BitV's own bad-debt accounting (reused from the existing liquidation engine, §11) applies unchanged. |

**Adapter boundary, not fabricated behavior**: the registry's `isCVA`
flag and the liquidation-path awareness above are the full extent of
CVA-specific logic this specification proposes. No CVA contract
address, no CVA API call, and no CVA-specific settlement function is
invented.

## 6. Asset registry

`BitVRWACollateralRegistry` (new contract, `BitVRoleConsumer`-based,
mirroring `BitScoreManager`'s access pattern):

```solidity
enum AssetStatus { Unregistered, Verified, Suspended, Frozen, Delisted }

struct AssetConfig {
    AssetStatus status;
    address underlyingPool;      // the BitVPoolManager pool this RWA asset already has
    uint16 ltvBps;                // must mirror / never exceed the pool's own ltvBps
    uint16 maxLtvWithScoreBps;    // must mirror / never exceed the pool's own maxLtvWithScoreBps
    uint16 liquidationThresholdBps;
    uint16 liquidationBonusBps;
    uint256 collateralCap;        // this asset's own cap, independent of BitVPoolManager's supplyCap
    address oracle;                // IPriceOracle — see §8; may differ from the pool's configured oracle
    uint32 maxOracleStalenessSeconds;
    bool isCVA;                    // metadata only, per §5 — never assumed true by default
    bytes32[] allowedDebtAssetKeys; // which debt assets this collateral may be borrowed against, §10
}

mapping(address asset => AssetConfig) private _assets;
uint256 public totalRwaCollateralCapUsd; // protocol-wide RWA collateral value cap, §15
```

**Only registered assets may become RWA collateral** — the registry is
the single source of truth for "is `asset` an approved RWA collateral
type," queried by `BitVLendingManager` (§9) before any *new* collateral
value from that asset counts toward borrowing capacity. This does not
duplicate `BitVPoolManager.Pool`'s own `ltvBps`/`liquidationThresholdBps`
storage — it *references* the same asset's pool (`underlyingPool`) and
requires the registry's own risk fields never exceed the pool's
configured values (validated at registration time), so the two
configurations cannot silently drift apart and produce an inconsistency
an attacker could exploit.

**RISK_MANAGER_ROLE / RWA_ADMIN_ROLE** (§13) functions:
`registerAsset`, `updateAssetConfig`, `setAssetStatus` (the only path to
`Suspended`/`Frozen`/`Delisted`, §12), `setCollateralCap`,
`setTotalRwaCollateralCap`.

## 7. Collateral verification

**Exactly how BitV determines an asset is "verified," evaluated per the
task's five angles:**

1. **Cleanverse CVA verification** — Cleanverse's CVA guide confirms
   *issuance-time* verification (an issuer registers/launches a CVA
   through Cleanverse's own process) but does not document an on-chain
   query BitV could call to ask "is address X a currently-valid,
   currently-compliant CVA" as a standalone fact independent of transfer
   attempts. **This is the core "Cleanverse doesn't expose the required
   information on-chain" case the task anticipates** — resolved by NOT
   pretending such a query exists. BitV's registry instead records
   `isCVA` as an admin-attested fact (set by `RWA_ADMIN_ROLE`, based on
   off-chain confirmation from Cleanverse), not as something derived
   from an on-chain CVA verification call.
2. **Asset registry** (this specification's own contract, §6) — the
   actual mechanism BitV uses: `RWA_ADMIN_ROLE` explicitly registers an
   asset with its full `AssetConfig` before it can be used as
   collateral. This is the controlled registry boundary the task asks
   for when a Cleanverse primitive isn't confirmed on-chain.
3. **Issuer verification** — not a Cleanverse on-chain primitive either
   (per the CVA guide, issuers register/launch CVAs through Cleanverse's
   *off-chain* API, §3). BitV does not attempt to verify an issuer
   on-chain; `RWA_ADMIN_ROLE`'s registration action is itself the
   issuer-verification step, performed off-chain by BitV's own
   operational process before the on-chain `registerAsset` call.
4. **On-chain provenance** — the registry stores the asset's
   `underlyingPool` reference and the registering admin's action is
   itself an on-chain, auditable event (`AssetRegistered`), giving a
   verifiable provenance trail for *when and by whom* an asset was
   approved — this is the extent of "on-chain provenance" BitV can
   itself provide; it is not a claim about the RWA's own real-world
   provenance (e.g. the physical asset's chain of custody), which is
   outside any blockchain's ability to verify directly and is assumed to
   be handled by the (Cleanverse-verified, per point 1) issuer.
5. **Asset status** — the `AssetStatus` enum (§6) is the single
   authoritative on-chain signal for whether a registered asset is
   currently usable; §12 defines exactly how each status value affects
   protocol behavior.

**Summary**: verification is a **BitV-controlled, admin-attested
registry**, informed by (but not automatically derived from) Cleanverse
facts BitV cannot query on-chain. This is stated as the honest resolution
the task explicitly permits ("design a controlled registry boundary
rather than pretending [Cleanverse exposes the information] on-chain").

## 8. Oracle model

Reuses the existing `IPriceOracle` interface (`getPrice(asset) returns
(uint256 price, uint8 decimals)`) — no new oracle interface is invented.
**However, the current interface and its only implementation
(`StaticPriceOracle`) have no timestamp/staleness field at all** —
a real gap this specification must design around rather than assume
away, since RWA valuation staleness risk is materially higher than for
liquid on-chain assets.

**Design for this milestone (specification only):**
- **Oracle interface**: `IPriceOracle` is reused as-is for the *price*
  itself. The registry additionally requires each RWA asset's
  `AssetConfig.oracle` to implement a to-be-confirmed staleness-aware
  extension (a `getPriceWithTimestamp` variant, or an out-of-band
  "last updated" query) — **flagged here as an implementation
  dependency**, not designed in Solidity this milestone, since it
  requires either extending `IPriceOracle` (a change to an existing
  interface, which this spec does not make) or wrapping it in a new
  RWA-specific oracle adapter interface that also reports a timestamp.
  The cleanest resolution, deferred to the implementation milestone: a
  new `IStaleAwarePriceOracle` interface (extends the concept, not the
  existing type) that RWA oracles must implement, leaving
  `IPriceOracle` itself untouched for existing non-RWA pools.
- **Price decimals**: same convention as `IPriceOracle` today — a
  shared unit (e.g. USD) with an explicit `decimals` return value,
  compared across assets by the caller.
- **Update frequency**: not a Solidity-level property — an operational
  commitment for whichever oracle source is eventually wired in (e.g.
  daily NAV updates for a fund-backed RWA), not designed here.
- **Staleness threshold**: `AssetConfig.maxOracleStalenessSeconds` — if
  the oracle's last-updated timestamp is older than this threshold,
  the asset's price is treated as **unavailable**, not as "the last
  known price" (see fail-safe behavior below).
- **Zero-price handling**: a `price == 0` return is treated identically
  to a stale/unavailable price — never interpreted as "this collateral
  is worth nothing but still counts," which would be a nonsensical
  signal (probably an oracle bug), and never as valid data to compute a
  health factor against.
- **Negative-price handling**: `IPriceOracle.getPrice` returns
  `uint256`, so a "negative price" cannot occur at the type level;
  this is intentional and requires no additional handling — flagged
  here so the requirement is explicitly addressed, not silently
  ignored.
- **Price deviation protection**: not implemented in this milestone
  (no on-chain "compare against last price, reject if delta exceeds
  X%" logic exists anywhere in BitV today, including the base
  `StaticPriceOracle`). Flagged as a genuine gap and future work item
  (§19), not fabricated as already solved.
- **Emergency price freeze**: `ORACLE_MANAGER_ROLE` (§13) can set an
  asset's status to `Suspended` (§12) directly, which has the same
  practical effect as freezing its price for new-borrowing purposes —
  the registry does not need a separate "frozen price" concept distinct
  from the existing `AssetStatus` mechanism.

**Fail-safe requirement, stated explicitly per the task**: if the
oracle is unavailable, stale, or returns zero for a registered RWA
asset, **the registry must report that asset's collateral as
unavailable for computing *new* borrowing capacity** — never fall back
to a stale price, never treat "unknown" as "unchanged," never increase
what a user can borrow. This mirrors BitScore's own fail-safe principle
(`docs/bitscore-specification.md` §12: never fall back to something
*more* favorable) applied to oracle data instead of score data.

## 9. LTV model

**Hard collateral limits are retained exactly as the task requires —
BitScore adjusts within them, never past them.**

```
Asset's registry-configured ltvBps (base)
  ↓
BitScore tier adjustment (existing BitScoreManager.getAdjustedAvailableBorrowValue,
  reused unmodified — Build 04's triple-clamp pattern)
  ↓
Final allowed LTV, hard-capped at the asset's registry-configured
  maxLtvWithScoreBps (which itself can never exceed liquidationThresholdBps,
  enforced at registration time, same validation BitVPoolManager already
  performs for every collateral asset)
```

This is **not a new LTV mechanism** — it is the existing Build 04
BitScore/LTV integration (`_effectiveAvailableBorrowValue`'s triple-clamp:
bounded by construction in `BitScoreManager`, re-clamped in
`BitVLendingManager`, provably `<= maxAvailableBorrowValue`), applied to
an RWA collateral asset exactly the same way it's already applied to any
other collateral asset today. The registry's role is upstream of this:
it decides whether the asset's collateral value is available for the
calculation *at all* (§7, §12); once available, the existing
LTV/BitScore math is unmodified and untouched by this specification.

**"BitScore → unlimited RWA borrowing" is structurally impossible**
for exactly the reason it's already impossible for every other
collateral asset: `maxLtvWithScoreBps` is a hard, registry/pool-
configured ceiling BitScore's own contract cannot exceed by
construction (Build 04's design), and `BitVLendingManager` re-derives
and re-clamps that ceiling independently rather than trusting
`BitScoreManager`'s return value unchecked.

## 10. Borrowing

- **Which debt assets can be borrowed**: any `BitVPoolManager` pool
  with `isBorrowingEnabled = true` — unchanged. The registry's
  `allowedDebtAssetKeys` (§6) lets `RWA_ADMIN_ROLE` additionally
  *restrict* which debt assets a specific RWA collateral type may be
  borrowed against (e.g. a particular RWA might be approved only against
  a stablecoin debt pool, not against a volatile debt pool) — a
  narrowing option, not a new borrowing pathway.
- **RWA collateral borrowing MON/aUSDC or other approved assets**: yes,
  exactly like any other collateral asset today — `BitVLendingManager`'s
  existing cross-margin borrow logic is reused unmodified; an RWA asset
  is simply one more entry in a user's collateral set.
- **Borrow caps**: `BitVPoolManager.Pool.borrowCap` — unchanged,
  existing mechanism, applies per debt asset regardless of which
  collateral (RWA or not) backs a given borrow.
- **Per-user limits**: not currently a concept in
  `BitVLendingManager` for any asset type (limits are per-pool, not
  per-user) — this specification does not invent one for RWA either,
  consistent with "the RWA market must use the existing lending engine
  where possible."
- **Per-asset limits**: `AssetConfig.collateralCap` (§6) — an
  RWA-specific cap independent of (and typically tighter than) the
  underlying pool's own `supplyCap`, letting `RWA_ADMIN_ROLE` size RWA
  exposure conservatively without needing to also constrain the pool's
  general supply cap.
- **Pool liquidity requirements**: unchanged — `BitVPoolManager`'s
  existing `availableLiquidity` check on `borrow()` already prevents
  borrowing more than a pool actually holds, regardless of collateral
  type.

**The RWA market uses the existing lending engine for 100% of
deposit/borrow/repay/withdraw mechanics.** The only new logic is the
registry's upstream gate (§7, §9, §12) on whether an RWA asset's
collateral currently counts.

## 11. Liquidation

**Reuses the existing liquidation engine (`BitVLendingManager.liquidate`,
already implemented and tested — 7/7 `BitVLiquidation.t.sol` tests
passing) completely unmodified for the mechanics the task lists:**

- **Health factor**: existing `DataTypes.AccountData.healthFactorRay`
  computation — unchanged; an RWA asset's collateral value (when
  available per §7/§8) is weighted into this exactly like any other
  asset.
- **Liquidation threshold**: `AssetConfig.liquidationThresholdBps`
  (mirroring the underlying pool's own value, §6).
- **Close factor**: existing protocol-wide close-factor logic —
  unchanged.
- **Liquidation bonus**: `AssetConfig.liquidationBonusBps` (mirroring
  the pool's own value).
- **Partial liquidation**: existing mechanism — unchanged.
- **Insolvency / bad debt**: existing mechanism — unchanged; see §5's
  CVA table for the one RWA-specific wrinkle (a non-compliant liquidator
  could have a CVA-collateral seizure revert at the token level) and
  §12 for frozen-asset liquidation behavior.

**No duplicate liquidation engine is proposed** — exactly per
instruction.

## 12. RWA-specific liquidation & frozen-asset handling

The task's six illiquidity/freeze scenarios, each resolved explicitly:

| Condition | New deposits | New borrowing | Existing borrowing continues | Repayment | Withdrawal | Liquidation |
|---|---|---|---|---|---|---|
| **Illiquid collateral** (asset trades thinly / can't be sold quickly) | Allowed (asset still `Verified`) | Allowed | Yes | Yes | Yes | Allowed, but see "delayed settlement" below — this is a market-reality risk BitV's contract cannot eliminate, only price for via a conservative `liquidationBonusBps` |
| **Delayed settlement** (e.g. off-chain redemption takes days) | Allowed | Allowed | Yes | Yes | Yes | Allowed on-chain (seizing the token), but the liquidator's ability to *realize* value off-chain is outside this contract's scope — flagged as a limitation, not solved |
| **Market closure** (e.g. a TradFi-hours-only underlying market) | Allowed | Allowed | Yes | Yes | Yes | Allowed on-chain; the oracle's own staleness threshold (§8) is expected to widen or the asset temporarily `Suspended` during known closure windows — an operational, not automatic, response |
| **Frozen assets** (issuer-side freeze, e.g. a compliance action on the RWA token itself) | **Stopped** | **Stopped** | Yes | Yes | Yes | Allowed — liquidation must remain available specifically *because* existing borrowing continues; blocking liquidation on a frozen asset would let bad debt accumulate risk-free for the borrower |
| **Oracle failure** (stale/zero/unavailable, §8) | **Stopped** (no verified value to accept) | **Stopped** (§8's fail-safe: never increase borrowing capacity on unknown price) | Yes | Yes | Yes, if the position remains healthy against last-known accounting; see below | **Blocked** — liquidation requires a valid current price to compute a fair seizure amount; liquidating against a stale/zero price would either wrongly liquidate a healthy position or under/over-seize collateral. `ORACLE_MANAGER_ROLE`/`RWA_ADMIN_ROLE` intervention (manual status update or oracle fix) is required to resume liquidation |
| **Asset redemption restrictions** (issuer-imposed lock-up/redemption window) | Allowed if still `Verified` | Allowed if still `Verified` | Yes | Yes | **May be restricted at the token level, outside BitV's control** — the pool contract can only withdraw what the token itself allows; not a BitV-enforced restriction | Allowed on-chain, subject to the same token-level restriction on the liquidator's side |

**Asset status transitions and their exact effects**, mapped from
`AssetStatus` (§6):

- **`Suspended`** (temporary, e.g. oracle outage or a known market
  closure): new deposits and new borrowing stop; existing positions,
  repayment, withdrawal, and liquidation all continue exactly as in the
  "oracle failure" row unless the suspension has a separate, valid price
  (e.g. a manually-triggered suspension with the price feed still
  healthy) — in that case liquidation remains available since valid
  pricing exists.
- **`Frozen`** (asset-level freeze, e.g. issuer action): matches the
  "frozen assets" row above exactly — deposits/borrowing stop,
  everything else continues, liquidation explicitly *remains* available.
- **`Delisted`** (permanent removal from the registry): treated as the
  most restrictive combination — new deposits and new borrowing stop
  permanently; existing borrowers are expected to be wound down over
  time via repayment/withdrawal/liquidation, all of which remain
  available; a delisted asset is never re-registered under the same
  status transition (re-registration, if ever needed, is a fresh
  `registerAsset` call, an explicit admin decision, not automatic).
- **`Unverified`** (the task's term for an asset that was never
  registered, or whose registration was removed): identical to
  `Unregistered` in `AssetStatus` — cannot be deposited as new
  collateral at all; if somehow already held (e.g. a registry error is
  corrected by de-registering an asset that had active positions —
  an edge case this specification flags rather than silently allows),
  the same "everything except new deposits/borrowing continues" rule
  applies, since forcibly liquidating everyone the moment an asset is
  de-registered would be a worse outcome than winding down gradually.

**Core invariant, stated exactly per the task**: *the system must never
allow a frozen (or oracle-invalid, or delisted, or unregistered) asset
to increase borrowing capacity.* This is enforced at exactly one choke
point — the registry's "is this asset's collateral available for new
borrowing capacity" check (§7-§9) — rather than scattered across
multiple functions, so it's a single property to verify rather than
several.

## 13. Access control

Reuses `BitVAccessManager`/`BitVRoleConsumer` exactly. Per "reuse
existing BitV role architecture where possible" / "do not create
unnecessary roles," exactly **three** new roles are added (not four —
see below):

- **`RWA_ADMIN_ROLE`** — registers assets, updates `AssetConfig`,
  changes `AssetStatus` (freeze/suspend/delist), sets per-asset and
  total collateral caps. The RWA-specific analogue of
  `POOL_MANAGER_ROLE`/`VAULT_MANAGER_ROLE`'s day-to-day-operations role.
- **`ORACLE_MANAGER_ROLE`** — the task explicitly asks for this as a
  distinct role from `RWA_ADMIN_ROLE`, and it is kept distinct here:
  wires/replaces an RWA asset's oracle address and staleness threshold,
  and can trigger the emergency price-freeze-equivalent `Suspended`
  status (§8) specifically for oracle-related reasons. Separating it
  from `RWA_ADMIN_ROLE` mirrors `STRATEGY_MANAGER_ROLE` vs.
  `VAULT_MANAGER_ROLE`'s split in the yield vault spec: "which price
  source this registry trusts" is a materially different, more
  security-sensitive decision than day-to-day asset administration.
- **`RISK_MANAGER_ROLE`** — **reused, not newly created** — sets
  `ltvBps`/`maxLtvWithScoreBps`/`liquidationThresholdBps`/
  `liquidationBonusBps` per registered asset, exactly the same role
  that already sets these values for every non-RWA pool via
  `BitVPoolManager.setRiskParams`. The task lists `RISK_MANAGER` in its
  role table, but the existing `BitVAccessManager.RISK_MANAGER_ROLE` is
  reused directly rather than creating a second, RWA-specific
  risk-manager role that would fragment risk-parameter authority across
  two roles for what is conceptually the same responsibility.
- **`PAUSER_ROLE`** — **reused, not newly created** — the existing
  role already covers pool/vault pausing; the registry's own pause
  surface (if any is needed beyond per-asset `AssetStatus`, which
  already provides fine-grained control) would use the same role rather
  than adding a redundant one.

**Net new roles: `RWA_ADMIN_ROLE` and `ORACLE_MANAGER_ROLE` — two, not
four**, since `RISK_MANAGER_ROLE` and `PAUSER_ROLE` are reused exactly
as the task's own "reuse existing BitV role architecture where
possible" / "do not create unnecessary roles" instructions require.

Users are never granted any of these roles — unchanged principle.

## 14. Compliance

Every protected RWA action respects `BitVComplianceGuard`, evaluated
per the task's list:

| Action | Compliance checked? |
|---|---|
| Collateral deposit | **Yes** — via `BitVLendingManager.depositCollateral`'s existing `_requireCompliance(msg.sender)`, unchanged; the registry gate (§7/§9) is an *additional*, separate check, not a replacement |
| Borrow | **Yes** — existing `BitVLendingManager.borrow` check, unchanged |
| Repay | **Yes** — existing check, unchanged |
| Collateral withdrawal | **Yes** — existing check, unchanged |
| Liquidation | Liquidator identity is **not** compliance-gated today (matching the existing, already-implemented `BitVLendingManager.liquidate`, which does not call `_requireCompliance` on the liquidator — liquidation is a protocol-health action, not a borrower-privilege action) — **unchanged by this specification**; flagged explicitly here since the task asks the question directly, and the honest answer is "unchanged from the existing, already-tested behavior," not a new design choice invented for RWA |
| RWA transfer | **N/A** — RWA collateral tokens are never transferable-out except via the existing withdraw/liquidate paths (both already compliance-gated on the withdrawing party where applicable); there is no separate "RWA transfer" function this specification introduces. If a specific RWA asset happens to be a CVA (§5), its own transfer hook adds a further, token-level compliance check on any recipient — a bonus, not a gap |

**Asset movement cannot bypass identity requirements** — the registry
gate and the compliance gate are independent, both-required conditions,
not alternatives; an asset being `Verified` in the registry never
substitutes for the depositing/borrowing/withdrawing user's own CVI
compliance, and vice versa.

## 15. Risk controls

| Control | Mechanism |
|---|---|
| Per-asset collateral cap | `AssetConfig.collateralCap` (§6) |
| Total RWA collateral cap | `totalRwaCollateralCapUsd` (§6) — a protocol-wide ceiling on aggregate RWA collateral value (summed via the registered assets' oracle prices), independent of any single asset's own cap |
| Per-user collateral cap | Not implemented — see §10's note that per-user limits aren't a concept in the existing lending engine for any asset type; not invented here either, consistent with reusing the existing engine |
| Borrow cap | `BitVPoolManager.Pool.borrowCap` — existing, unchanged |
| LTV / liquidation threshold / liquidation bonus | `AssetConfig` fields, §6, validated against the underlying pool's own values at registration/update time so the two can never silently diverge |
| Oracle staleness threshold | `AssetConfig.maxOracleStalenessSeconds` (§8) |
| Emergency freeze | `AssetStatus.Suspended`/`Frozen` (§12), `ORACLE_MANAGER_ROLE`/`RWA_ADMIN_ROLE`-gated |

**No parameter here conflicts with the existing lending engine** — every
RWA-specific field either mirrors (and is validated against) an
existing `BitVPoolManager.Pool` field, or is a genuinely new, additive
constraint (`collateralCap`, `totalRwaCollateralCapUsd`,
`maxOracleStalenessSeconds`) that only ever *tightens* what's already
enforced, never loosens it.

## 16. Security model

| Risk | Addressed by design |
|---|---|
| Fake RWA token | Only registry-registered assets count as RWA collateral for the registry's own gate (§6, §7); a fake token could still technically be deposited into a `BitVPoolManager` pool if that pool's own `isCollateralEnabled` were separately misconfigured — this is why registration must validate `AssetConfig` fields against the referenced pool's own configuration, not trust either configuration alone |
| Unverified asset | `AssetStatus.Unregistered` — never eligible, §7/§9 |
| Oracle manipulation | Out of scope for `StaticPriceOracle`-class sources by design (a single admin-set price is inherently manipulable — documented as a known limitation of the existing oracle, not solved here); a production oracle would need its own manipulation-resistance design, orthogonal to this registry |
| Stale oracle | `maxOracleStalenessSeconds` fail-safe (§8) — treated as unavailable, never increases borrowing capacity |
| Zero price | Treated as unavailable (§8) |
| Price deviation | Not implemented — flagged gap, §19 |
| Collateral donation | Unchanged from existing pool behavior — `BitVPoolManager` already accounts collateral via explicit `deposit`/`depositCollateral` calls, not raw balance inspection, so a direct token donation to the pool doesn't inflate any user's credited collateral (same protection every existing collateral asset already has) |
| Reentrancy | `BitVRWACollateralRegistry`'s own functions are expected to be `view`/light state-only (no external token transfers), and every `BitVLendingManager` call site consulting it remains inside that contract's existing `nonReentrant` guards — no new reentrancy surface introduced |
| Unauthorized asset registration | `RWA_ADMIN_ROLE`-only |
| Unauthorized oracle updates | `ORACLE_MANAGER_ROLE`-only |
| Unauthorized parameter changes | `RISK_MANAGER_ROLE`-only for risk parameters, `RWA_ADMIN_ROLE`-only for registry administration — split exactly as §13 defines |
| Frozen asset borrowing | Structurally blocked at the single registry choke point (§12) |
| Liquidation manipulation | Reuses the existing, already-tested liquidation engine (§11) — no new liquidation-triggering logic is introduced that could be gamed independently |
| Bad debt / insolvency | Existing mechanism, unchanged (§11) |
| Compliance bypass | Registry gate and compliance gate are independent AND conditions (§14) |
| Sybil behavior | Unchanged from the existing protocol's posture — CVI is the identity gate Cleanverse provides; this specification does not add or remove any Sybil-resistance property, since RWA collateral doesn't introduce a new identity surface beyond what CVI already governs |

**This design is not claimed to be production-ready, audited, or free
of undiscovered vulnerabilities** — the same posture taken for every
prior BitV specification.

## 17. Privacy

**No names, physical addresses, government IDs, raw KYC information, or
private issuer information are stored anywhere in this design.** The
registry stores only: asset contract addresses, risk parameters (bps
values, caps), oracle addresses, staleness thresholds, and an
`AssetStatus` enum — all protocol-operational data, none of it personal
or identity data. This matches every prior BitV component's privacy
posture (CVI itself is a boolean `complianceVerify` result; BitScore
stores only numeric score state) exactly.

## 18. Test plan

Mirrors the task's requested categories; each maps to a concrete
scenario a future implementation milestone's Foundry suite must cover
(none of these tests exist yet):

**Registry**
- `test_RegisterApprovedAsset_Succeeds`
- `test_UnauthorizedRegistration_Reverts`
- `test_RegisterAsset_RejectsConfigExceedingPoolLimits` (the
  registry-vs-pool consistency check, §6/§16)
- `test_FreezeAsset_BlocksNewDepositsAndBorrowing`
- `test_UnfreezeAsset_RestoresEligibility`
- `test_DelistAsset_PermanentlyBlocksNewActivity`

**Collateral**
- `test_DepositVerifiedRwa_Succeeds`
- `test_DepositUnverifiedRwa_Reverts`
- `test_CollateralAccounting_MatchesDepositedAmount`
- `test_WithdrawRwaCollateral_Succeeds`
- `test_WithdrawRwaCollateral_RespectsHealthFactor`
- `test_FrozenCollateral_WithdrawalStillAllowed` (per §12's table)
- `test_FrozenCollateral_NewDepositBlocked`

**Oracle**
- `test_ValidPrice_AcceptedForBorrowCapacity`
- `test_ZeroPrice_TreatedAsUnavailable`
- `test_StalePrice_TreatedAsUnavailable`
- `test_InvalidPrice_NeverIncreasesBorrowCapacity`
- `test_PriceUpdate_ReflectedInBorrowCapacity`
- `test_UnauthorizedOracleUpdate_Reverts`

**Borrowing**
- `test_BorrowAgainstRwaCollateral_Succeeds`
- `test_LtvEnforcement_RwaCollateral`
- `test_BorrowCap_Enforced`
- `test_PoolLiquidityCap_Enforced`
- `test_BitScoreAdjustment_AppliesToRwaCollateral`
- `test_HardLtv_CannotBeExceededByBitScore` (mirrors the existing
  `test_HighScore_CannotBorrowBeyondConfiguredCeiling` pattern from
  `BitScoreManager.t.sol`, applied to an RWA-backed position)

**Liquidation**
- `test_HealthyRwaPosition_CannotBeLiquidated`
- `test_UnhealthyRwaPosition_CanBeLiquidated`
- `test_PartialLiquidation_RwaCollateral`
- `test_LiquidationBonus_RwaCollateral`
- `test_Insolvency_RwaCollateral`
- `test_BadDebt_RwaCollateral`
- `test_FrozenAsset_LiquidationStillAvailable` (per §12's explicit
  requirement)
- `test_StaleOracle_LiquidationBlocked` (per §12's oracle-failure row)

**Compliance**
- `test_UnverifiedUser_RwaDepositRejected`
- `test_ComplianceFailure_RegistryNeverConsulted` (mirrors the existing
  `test_ComplianceFailure_BitScoreNeverConsulted` pattern — compliance
  fails before the registry gate is ever reached)
- `test_ComplianceCannotBeBypassed_ViaRwaAssetStatus` (a `Verified`
  asset status must never substitute for user compliance)

**Security**
- `test_Reentrancy_RwaDepositAndBorrow`
- `test_UnauthorizedAdmin_CannotRegisterOrFreeze`
- `test_OracleManipulation_SingleAdminSourceDocumented` (documents,
  rather than "fixes," the existing `StaticPriceOracle` limitation)
- `test_AssetRegistrationAttack_CannotBypassPoolConsistencyCheck`
- `test_ParameterManipulation_UnauthorizedCallerRejected`
- `test_FrozenAssetAttack_CannotIncreaseBorrowCapacity`

**Invariants** (fuzzed, mirroring the existing
`BitVInvariant.t.sol`/`BitVYieldVaultInvariant.t.sol` handler-based
style)
- `invariant_UnregisteredAssetsNeverBecomeCollateral`
- `invariant_FrozenAssetsNeverIncreaseBorrowCapacity`
- `invariant_BorrowingNeverExceedsHardLtv`
- `invariant_OracleFailureNeverIncreasesBorrowCapacity`
- `invariant_UnauthorizedUsersCannotRegisterCollateral`
- `invariant_UnauthorizedUsersCannotChangeRiskParameters`
- `invariant_ComplianceRemainsMandatory`
- `invariant_TotalRwaCollateralNeverExceedsConfiguredCap`
- `invariant_BadDebtAccountingRemainsConsistent` (reuses the existing
  liquidation engine's own invariant properties, re-asserted with RWA
  collateral in the fuzzed actor mix)

## 19. Future extensions

- **Price deviation protection** (§8, §16) — flagged as unimplemented,
  a natural next hardening step once a real (non-static) oracle source
  is selected.
- **A confirmed, staleness-aware oracle interface** (§8) — this
  specification identifies the need and sketches the shape
  (`IStaleAwarePriceOracle`) but does not design it in full, since it
  depends on decisions (extend `IPriceOracle` vs. wrap it) better made
  alongside the actual production oracle selection.
- **CVA settlement/recovery mechanics**, if and when Cleanverse
  documents something beyond automatic transfer-time compliance (§5) —
  revisit only against confirmed documentation, never speculatively.
- **Per-user collateral caps**, if a concrete need emerges (§10, §15) —
  not designed here since none of BitV's existing collateral types have
  this concept either.
- **RWA-as-vault-strategy** — `docs/yield-vault-specification.md` §20
  already keeps `IBitVVaultStrategy` extensible for a future verified-RWA
  yield strategy; this specification's registry could, in principle,
  become a shared verification source for both the lending and vault
  product surfaces, but that integration is not designed here and would
  need its own review.

## 20. Open questions

1. **Which specific RWA token(s) will BitV actually integrate first,
   and has Cleanverse confirmed CVA status for it/them?** Nothing in
   this specification can answer this — it's a business/partnership
   fact, not an architectural one, and must precede any
   `isCVA = true` registration.
2. **Does Cleanverse expose any on-chain "is this token verified"
   query for CVA beyond transfer-time gating?** If Cleanverse later
   documents such a call, §7's registry-attestation model could be
   simplified to query it directly — revisit only against confirmed
   documentation.
3. **Should liquidator compliance be required for RWA-backed
   liquidations specifically**, even though it isn't required for
   liquidation generally today (§14)? The existing behavior is reused
   here as the conservative default (don't invent a new requirement),
   but RWA's CVA-transfer-hook interaction (§5) means an
   incompliant liquidator could already be *functionally* blocked at
   the token level for CVA collateral — worth an explicit decision
   before implementation rather than leaving it as an emergent,
   asset-dependent side effect.
4. **What is the exact mechanism for "recovering" value from a
   `Delisted` or permanently `Frozen` RWA asset that still backs open
   debt** (§12)? This specification describes the wind-down principle
   (existing positions continue, no new activity) but does not design
   an active recovery/settlement mechanism beyond what liquidation
   already provides — flagged as unresolved, consistent with §5's
   conclusion that Cleanverse doesn't document a recovery mechanism
   either.
5. **Should the registry live as a fully separate contract (as
   specified) or as a library/extension consumed directly by
   `BitVLendingManager`'s storage** for gas efficiency? This
   specification chose the separate-contract form for the
   isolation/precedent reasons in §2; a future implementation review
   could re-evaluate the gas-vs-isolation tradeoff once real usage
   patterns are known, without changing the external interface
   contract.
6. **Oracle interface evolution** (§8, §19) — extend `IPriceOracle` or
   introduce a parallel interface? Left open pending the production
   oracle decision.
