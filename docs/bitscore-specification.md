# BitScore Specification (Build 04)

**Status: SCALE UPDATE PENDING IMPLEMENTATION.** The deployed Build 04
contracts (`BitScoreManager.sol` et al., see
`docs/bitscore-implementation.md`) still run on the **original 0–1000
scale** described in earlier revisions of this document. This revision
rescales the specification to **0–100**, per an explicit instruction not
to touch Solidity yet. Until a follow-up implementation milestone lands,
**the deployed contracts and this document disagree on scale** — treat
this document as the current target, and
`docs/bitscore-implementation.md` as describing the pre-rescale
contracts, until that milestone updates both.

**Underlying architecture and scoring principles are unchanged** by
this rescale: the same inputs, the same directional weighting
(repayments > timeliness > tenure; utilization/collateralization as a
secondary tempering signal), the same decay mechanics (single
consolidated decaying positive-contribution accumulator, separately
decaying liquidation penalty, permanent bad-debt penalty), the same
per-input cap structure, the same anti-gaming rules, the same CVI/
BitScore separation, and the same fail-safe behavior. Only the numeric
range — and every number derived from it — changed.

Two deviations from this spec were found necessary during the *first*
Solidity implementation pass (still true of the deployed 0–1000
contracts, and still the intended resolution once the 0–100 rescale is
implemented):

1. **Decay model consolidated** to a single accumulator/window instead
   of per-input-category windows (tractability simplification — point
   values and the overall cap are preserved, just rescaled below).
2. **Interest rate adjustment is quoted/informational only**, not wired
   into real per-user accrual — `BitVPoolManager`'s shared borrow index
   makes a genuine per-user rate architecturally incompatible without a
   much larger redesign, out of scope for BitScore's MVP. This remains
   unaffected by the score-scale change.

## 1. Purpose

BitScore is BitV's own protocol-level risk layer. It answers a question
Cleanverse's CVI does not and should not answer: *given that a
participant is already verified and eligible (CVI), how much should BitV
trust their specific on-protocol behavior when setting lending
parameters for them?*

BitScore never decides *whether* someone may use BitV — that is entirely
CVI's job. BitScore only ever adjusts *how favorable* their terms are,
within limits the asset's own risk configuration always caps.

## 2. Design principles

1. **CVI and BitScore are separate systems, permanently.** CVI is an
   external, Cleanverse-owned eligibility gate. BitScore is an internal,
   BitV-owned reputation signal derived only from what BitV's own
   contracts observe. Neither can substitute for the other, and this
   document does not propose merging them.
2. **BitScore only ever reads Cleanverse through
   `complianceVerify(pool, user)`.** That is the only confirmed
   Cleanverse interface (see `docs/cleanverse-integration.md`). BitScore
   treats CVI as a boolean gate checked before it runs at all, never as
   a source of identity attributes — there are none to read. No
   `allowedGroup`/`minTier`/etc. from `RuleV2` is read or interpreted by
   BitScore; those are Cleanverse's own compliance-rule fields, not
   risk-scoring inputs, and reusing them for a different purpose would
   blur the two systems this document insists on keeping separate.
3. **Protocol-native data only.** Every input is something
   `BitVPoolManager`/`BitVLendingManager` already record on-chain as a
   side effect of normal operation (deposits, borrows, repayments,
   liquidations). Nothing is fetched off-chain, nothing is
   self-reported by the user, nothing resembles a traditional credit
   bureau's inputs (income, employment, other-platform history).
4. **BitScore only ever loosens, never tightens below the protocol
   floor, and never loosens past the asset ceiling.** The existing
   asset-level `ltvBps`/`liquidationThresholdBps`/caps
   (`BitVPoolManager`'s `DataTypes.Pool`) remain the hard safety
   ceiling for every user regardless of score. A perfect score can
   move a user *up to* that ceiling, never past it.
5. **Fail safe, not fail open.** Every failure mode (Section 11) resolves
   to the most conservative outcome available (base parameters, no
   score bonus), never to defaulting toward more generous terms.
6. **Simplicity over sophistication for the MVP.** A fully on-chain,
   deterministic, event-driven point system (Section 10) is preferred
   over anything requiring an off-chain component, a signer, or a
   separate trust assumption — see Section 10's comparison.

## 3. Score model

**Range: 0–100.** Superseding the original 0–1000 range (kept below for
traceability of the decision this revision reverses):

- The original document chose 0–1000 specifically because "0–100 is too
  coarse for the number of distinct inputs in Section 4 to each carry a
  meaningful, non-overlapping weight without rounding several of them
  into indistinguishable single-point deltas." **This rescale doesn't
  eliminate that concern — it resolves it at the implementation layer
  instead of the specification layer**: point deltas that would round to
  indistinguishable whole numbers on a 0–100 scale (e.g. the original
  timeliness bonus) are represented as documented fractional values in
  this specification (Section 4), with the follow-up implementation
  milestone expected to use fixed-point (e.g. storing "tenths of a
  point" internally, dividing by 10 for any externally displayed score)
  to preserve exact relative weighting without losing precision to
  integer rounding. This is an implementation detail, not a principle
  change — see Section 10.
- The unsigned-range and "0 is the unambiguous floor" reasoning is
  unchanged and still applies at the new scale.
- **100 specifically**: divides cleanly into the four-tier structure in
  Section 6 (25-point bands, as specified in the update instruction)
  the same way 1000 divided into 250-point bands before.

**Starting score: 30.** Directly rescaled from 300 (300/1000 = 30/100).
Still not the midpoint (50) and not the floor (0), for the same reason
as before: a new, never-before-seen wallet has *no negative history*
(shouldn't be penalized) but also *no positive history* (shouldn't be
trusted as much as a wallet with a long clean track record). 30 sits
inside Tier 1 (Section 6), meaning every new user still starts at base
parameters with zero BitScore-driven adjustment.

**Minimum: 0. Maximum: 100.** Both hard-clamped — no event can push a
score outside this range regardless of magnitude or repetition.

**Score calculation:** additive/subtractive point deltas applied
per-event (Section 4), computed deterministically on-chain from state
`BitVLendingManager`/`BitVPoolManager` already have at the moment of the
triggering action (a repayment, a liquidation, etc.) — not a formula
re-evaluated from scratch each time, an accumulator updated by discrete
events. See Section 10 for exactly which functions write to it.

**Score updates:** happen synchronously, in the same transaction as the
triggering protocol action (e.g. `repay()` ends by adjusting the
caller's BitScore before returning) — not batched, not delayed, not
requiring a separate transaction. This keeps the score always
consistent with on-chain state as of the last action, with no pending/
stale-update window.

**Score decay:** yes, but only for the *positive* history component
(Section 4's repayment-consistency and protocol-longevity inputs),
applied lazily at read/update time (not via a keeper or cron) — see
Section 4 for exactly which inputs decay and why. Negative history
(liquidations, bad debt) does **not** decay — a past liquidation stays
recorded permanently in the score-affecting history, only its numeric
score impact fading is inappropriate; see Section 4.7.

**Score recovery:** a low score recovers only through the same positive
events that raise it in the first place (consistent on-time repayment
over time) — there is no separate "recovery mechanism," which would
just be a second way to gain points and therefore a second thing to
game. Recovery is slow by design: the point deltas in Section 4 are
calibrated so that undoing a liquidation's score impact requires
materially more sustained good behavior than the single event that
caused the drop, consistent with Anti-Gaming (Section 8).

**Score reset conditions: none, by default, for the MVP.** A full reset
(back to 30) is a governance-level, `RISK_MANAGER_ROLE`-gated
*emergency* action only (e.g. correcting a confirmed scoring bug for a
specific user), not a normal part of the score's lifecycle — a user
cannot reset their own score, and there's no automatic reset (e.g. after
account inactivity) since that would be a Sybil vector (drain a bad
score to zero activity, wait, "reset" back to neutral 30, better than
staying at a poor earned score).

## 4. Inputs

Every input below is derived only from `BitVPoolManager`/
`BitVLendingManager` state. Format per the brief: why it matters,
direction, strength, decay.

### 4.1 Successful repayments (count)

- **Why**: the single strongest positive signal — direct evidence the
  user borrows and pays back as agreed.
- **Direction**: increases.
- **Strength**: moderate per-event (+0.5 points per fully-closed loan,
  i.e. a `repay()` call that brings `getCurrentDebt(user, asset)` to
  zero — rescaled from +5 on the original 0–1000 range; represented as
  fixed-point internally per Section 3/Section 10, not literally a
  fractional on-chain integer), capped at a maximum contribution from
  this input alone (see Section 4.9) so repayment count alone can't be
  farmed to max score (Anti-Gaming, Section 8).
- **Decay**: yes — each counted repayment's contribution decays
  linearly to zero over a fixed window (suggested: 180 days) if no
  further qualifying activity occurs, so the score reflects *recent*
  behavior, not a permanent count that can never regress.

### 4.2 Repayment timeliness

- **Why**: BitV's lending has no fixed maturity date (positions can be
  held indefinitely), so "timeliness" isn't "paid by a due date" —
  it's "how long a position stayed open relative to how much interest
  accrued on it," a proxy for whether the user actively manages debt
  rather than letting it accrue toward unhealthy.
- **Direction**: increases for positions closed while healthy with
  moderate accrued interest; neutral (no bonus, no penalty) for
  positions closed extremely quickly (see Anti-Gaming 8.3 — instant
  open/close cycles get zero credit, not partial credit).
- **Strength**: small per-event (+0.2 points, rescaled from +2), since
  this is a secondary signal layered on top of 4.1, not a standalone
  strong one.
- **Decay**: yes, same window as 4.1 (they're both "closed loan"
  events, decay together).

### 4.3 Outstanding debt (current, not historical)

- **Why**: current exposure is a real-time risk signal — a user with
  significant open debt is not automatically "worse," but it's a factor
  the *lending-impact* calculation (Section 7) should see, since
  BitScore-driven parameter improvements shouldn't apply the same way
  to a user about to become more leveraged as to one who is not.
- **Direction**: not a score input at all — this is used directly in
  the lending-impact calculation (Section 7), not folded into the
  0–100 score itself, to keep the score a reputation signal (slow-
  moving) rather than a real-time exposure gauge (fast-moving). See
  Section 7 for how current utilization tempers a score-based
  improvement.
- **Strength/Decay**: n/a — see above.

### 4.4 Borrow utilization (user's own, i.e. debt / max-permitted debt)

- **Why**: consistently borrowing near one's own limit is a weak
  negative signal (less margin for error, more likely to become
  unhealthy from a price move); consistently borrowing well under one's
  limit (when borrowing at all) is a weak positive signal.
- **Direction**: increases for sustained low utilization, decreases for
  sustained high utilization (>90% of permitted borrow value) —
  "sustained" meaning observed at multiple update points, not a single
  snapshot, to avoid punishing a single legitimate large borrow.
- **Strength**: small (+/-0.1 to 0.3 points per qualifying observation,
  rescaled from +/-1 to 3), the weakest input in this list — a
  secondary tie-breaker, not a primary driver.
- **Decay**: yes, fast (suggested: 30-day window) — this reflects
  *recent* risk posture, not lifetime behavior.

### 4.5 Collateralization (ratio, sustained)

- **Why**: a user who maintains collateral well above the liquidation
  threshold demonstrates conservative risk management independent of
  whether they've ever had to be liquidated.
- **Direction**: increases for sustained health factor comfortably
  above 1 (suggested: >1.5 observed consistently).
- **Strength**: small (+0.1 to 0.2 points per qualifying observation,
  rescaled from +1 to 2).
- **Decay**: yes, same 30-day window as 4.4 (both are "current risk
  posture" signals, not permanent history).

### 4.6 Liquidation history (count and recency)

- **Why**: the strongest negative signal — direct evidence a position
  became unhealthy and had to be forcibly closed.
- **Direction**: decreases.
- **Strength**: large per-event (-10 points for a full liquidation, -5
  for a partial one that still leaves the position open under the
  close-factor cap — see `docs/protocol-architecture.md`'s liquidation
  model; rescaled from -100/-50), deliberately much larger in magnitude
  than any single positive input, so no realistic combination of
  positive events from one time period offsets one liquidation from the
  same period.
- **Decay**: **partial only, and slow** — the numeric score deduction
  itself decays over a long window (suggested: 365 days) back toward
  neutral, but the *event itself* is never erased from the user's
  on-chain history (Section 10's storage keeps a running liquidation
  count separately from the decayed score contribution) — see 4.7.

### 4.7 Default / bad-debt history

- **Why**: the CVI-adjacent-but-not-CVI worst-case outcome — a
  liquidation that still leaves unrecovered debt (the insolvency path
  documented in `docs/economic-engine-review.md`'s liquidation review).
  This is categorically worse than a normal liquidation: the protocol
  itself absorbed a loss.
- **Direction**: decreases, sharply.
- **Strength**: largest single penalty (-30 points, rescaled from
  -300), and — unlike every other input — **does not decay**. A
  bad-debt event is a permanent mark. This is the one input where
  "recovery" (Section 3) is deliberately made very slow: climbing back
  from a -30 event via only +0.5-point repayment increments requires
  dozens of qualifying events over a long period, which is the intended
  friction, not an oversight — same relative ratio as the original
  -300-via-+5-increments framing.
- **Decay**: none.

### 4.8 Length of protocol activity (tenure)

- **Why**: sustained presence is weak evidence against Sybil/farming
  behavior (a wallet created and immediately farmed for score looks
  different from one with months of organic activity) — but see
  Anti-Gaming 8.1 for why this must stay a *minor* factor, not a major
  one, per the brief's explicit instruction not to over-weight wallet
  age.
- **Direction**: increases, very mildly, and only in combination with
  actual activity (a dormant wallet that's merely "old" gets nothing —
  this is tenure-with-activity, not wallet age alone).
- **Strength**: smallest of all inputs (+0.1 point per 30 days of
  activity, rescaled from +1, capped low — see Section 4.9).
- **Decay**: no — tenure, once accrued, doesn't un-happen. (Its
  *influence* is capped low enough that this doesn't matter much either
  way.)

### 4.9 Per-input caps (anti-gaming, tying Section 4 together)

No single input category may contribute more than a fixed share of the
**70-point range above the 30 starting score** (rescaled from the
original 700-point range above 300, same 70% proportion of the total
climb):

| Input | Max contribution |
|---|---|
| Repayments + timeliness (4.1, 4.2) | 35 points (was 350) |
| Utilization + collateralization (4.4, 4.5) | 15 points (was 150) |
| Tenure (4.8) | 5 points (was 50) |
| Liquidation/bad-debt penalties (4.6, 4.7) | unbounded downward (can drive score to 0) |

This means reaching the top tier requires a *combination* of sustained
good repayment behavior, conservative risk posture, and tenure — not
maximum farming of any single cheap-to-repeat action. Same principle,
same proportions, as the original range.

## 5. Scoring rules (summary)

`score = clamp(30 + Σ(decayed positive contributions, each capped per
Section 4.9) - Σ(liquidation penalties, decayed per 4.6) -
Σ(bad-debt penalties, never decayed), 0, 100)`

Applied as a running accumulator, recalculated (decay applied lazily)
whenever a triggering event occurs or the score is read — not
recomputed from full history each time (see Section 10 for the
storage shape that makes this practical). Mechanically identical to the
original 0–1000 formula, only the constants changed (30 replaces 300,
100 replaces 1000).

## 6. Risk tiers

Four tiers, **25-point bands** (rescaled from the original 250-point
bands matching the 0–1000 range):

| Tier | Range | Name | Meaning |
|---|---|---|---|
| 0 | 0–24 | **Restricted** | Below the starting score — reached only through liquidations/bad debt. No BitScore-driven improvement to any parameter; may additionally face a *reduction* from base parameters (Section 7) as a protective measure, not just "no bonus." |
| 1 | 25–49 | **Standard** | The default tier — includes the starting score of 30. Base asset-level parameters apply exactly, no adjustment either direction. This is intentionally the largest starting surface: most users, especially new ones, live here. |
| 2 | 50–74 | **Established** | Sustained positive history. Modest, capped improvements to LTV/rate/threshold (Section 7). |
| 3 | 75–100 | **Trusted** | The strongest sustained history achievable under the caps in Section 4.9 combined with a long liquidation/bad-debt-free record. Maximum permitted BitScore-driven improvement — still bounded by the asset's own ceiling, never beyond it. |

Names chosen to describe standing on BitV specifically ("Restricted" /
"Standard" / "Established" / "Trusted"), not to imply a generic credit
rating — not final, flagged in Section 13.

## 7. Lending impact

BitScore adjusts, within hard limits the asset configuration always
imposes:

| Parameter | Tier 0 (Restricted) | Tier 1 (Standard) | Tier 2 (Established) | Tier 3 (Trusted) |
|---|---|---|---|---|
| Effective LTV | base LTV − up to 10pp (protective) | base LTV (unchanged) | base LTV + up to 5pp | base LTV + up to 10pp |
| Borrow limit (beyond LTV-implied) | no change | no change | no change | no change — see note below |
| Interest rate | no change | no change | small discount (e.g. −0.5pp on the base-rate component only, never the utilization component) | moderate discount (e.g. −1pp on base-rate component only) |
| Liquidation threshold | no change | no change | no change | no change |
| Pool eligibility | no change | no change | no change | no change |

**Every adjustment is capped at `min(BitScore-implied adjustment,
asset's configured ceiling)`** — e.g. if an asset's `ltvBps` is already
configured at its practical maximum by `RISK_MANAGER_ROLE`, a Tier 3
user gets no further LTV improvement, because there's no room below the
liquidation threshold to give it (the "LTV must leave room below the
liquidation threshold" invariant already enforced in
`BitVPoolManager._validateRiskParams` is not something BitScore is
allowed to violate).

**Explicitly not adjusted by BitScore, ever, regardless of tier:**

- **Liquidation threshold** — adjusting this would mean a high-BitScore
  user's position becomes liquidatable at a *different* collateral
  ratio than the asset's own configuration says is safe, which directly
  contradicts "the existing asset-level risk parameters remain the hard
  safety ceiling."
- **Borrow caps / supply caps** — these are pool-solvency limits, not
  user-risk limits; BitScore has no legitimate opinion on how much
  total liquidity a pool should allow out, only on how a given user's
  own borrow should be priced/sized relative to their own collateral.
- **Pool eligibility** — whether a pool exists / is active / has
  borrowing or collateral enabled is a `POOL_MANAGER_ROLE`/
  `RISK_MANAGER_ROLE` decision about the asset, unrelated to any
  individual user's score.
- **Compliance requirements** — CVI's `complianceVerify` gate is
  checked before BitScore is ever consulted (Section 9) and is
  unaffected by score in either direction.

**Interest rate adjustment is deliberately restricted to the base-rate
component only** (per `KinkedInterestRateModel`'s separation of base
rate from the utilization-driven slope1/slope2 components,
`docs/protocol-architecture.md`), never the utilization component — a
high BitScore should not let a user borrow more cheaply *at high
utilization* than the pool's own supply/demand curve says is
appropriate; utilization pricing is a pool-wide signal that no
individual user's score should distort.

**Current outstanding debt/utilization (Section 4.3) tempers, rather
than blocks, an improvement**: a user in Tier 3 with very high current
utilization gets a smaller fraction of their tier's maximum LTV/rate
improvement than the same-tier user with low current utilization — this
prevents a scenario where reaching Tier 3 becomes a one-time unlock
that a user immediately maximally exploits by borrowing to the new,
higher limit; the improvement itself scales down as the user's own
current risk rises.

## 8. Anti-gaming

| Threat | Mitigation |
|---|---|
| **Sybil behavior** (many wallets, each farming small positive events) | Per-input caps (4.9) mean no wallet reaches Tier 2+ from cheap/repeated actions alone; reaching a high tier requires sustained *combined* signals over time, raising the cost of Sybil farming per-wallet enough that splitting across wallets doesn't help — each wallet still needs real capital at risk and real time elapsed. |
| **Repeated deposit/withdraw cycles** | Deposits/withdrawals of pool liquidity (`BitVPoolManager`) are **not a scored input at all** — only lending-side events (repayment, liquidation) affect score, so this class of activity earns nothing. |
| **Artificial repayment loops** (borrow small, immediately repay, repeat) | 4.2's "instant close gets zero credit" rule — a minimum position-open-duration (suggested: 1 day) is required before a repayment counts toward 4.1/4.2 at all, not just discounted. |
| **Wash borrowing** (borrow against one's own liquidity supplied elsewhere) | Out of scope to fully solve on-chain without identity linkage (which BitScore explicitly must not have, per Section 2's privacy principle) — documented as a known limitation (Section 13), not solved; the per-input caps and minimum-duration rule limit the *rate* at which even successful wash borrowing can raise score, same as any other farming attempt. |
| **Flash-loan manipulation** | BitV has no flash-loan feature; any position affecting BitScore requires a real, standing collateral deposit that persists across blocks (collateral/debt state is read at settlement time, not mid-transaction), so a single-transaction flash-loan-funded position cannoteven be opened in a way that scores. |
| **Small-volume activity farming** | Per-event point values (Section 4) are flat, not proportional to volume, but the minimum-duration rule (above) and per-input caps together bound how fast flat small-volume events can accumulate; a future refinement could weight points by position size relative to the user's own typical size (Section 13). |
| **Rapid score manipulation** | Decay windows (4.1/4.2: 180 days, 4.4/4.5: 30 days) mean recent farming decays back out relatively quickly if not sustained — score is a trailing signal of *sustained* behavior, not a snapshot a user can spike and immediately exploit. |
| **Liquidation avoidance** (e.g. self-liquidating via a cooperating wallet to avoid a "real" liquidation's penalty) | Not distinguishable on-chain from a real liquidation — any liquidation event, regardless of who the liquidator is, applies the 4.6 penalty; there is no exemption for "friendly" liquidations, which removes the incentive to arrange one instead of letting a real liquidator act. |
| **Creating artificial activity purely to raise score** | The combination of per-input caps, minimum-duration rules, and decay is intended to make genuine, sustained, capital-at-risk usage cheaper than any artificial pattern — not provably ungameable (no on-chain reputation system is), but raising the cost/benefit ratio is the explicit design goal, documented as such rather than claimed as solved. |

**Wallet age is explicitly not used as a major factor** — Section 4.8's
tenure input is the smallest-weighted input in the entire model (max 5
points out of a possible 70-point climb, rescaled from 50/700) and
requires *activity* during that tenure, not mere existence.

## 9. Privacy

BitScore stores and computes on:

- A running point total (the score itself).
- Per-category decay timestamps/accumulators (Section 4's decay
  windows need to know "when" for each category, not "what" beyond a
  count/amount already public via the lending contracts' own events).
- Counts (successful repayments, liquidations, bad-debt events).

BitScore **never** stores, requires, or has access to: name, address,
phone number, government ID, raw KYC data, or any other personal
identity information — none of this is available to it in the first
place, since its only Cleanverse touchpoint is the boolean
`complianceVerify` result (Section 2, principle 2). This isn't a policy
choice layered on top of an otherwise-capable system — the architecture
structurally cannot access this data, because nothing in `BitVLendingManager`
or `BitVPoolManager` (BitScore's only data sources) ever receives it
either.

Everything BitScore stores is already derivable by anyone from public
on-chain events (`Repaid`, `Liquidated`, etc.) — BitScore is a
convenience aggregation of public on-chain history into a single
queryable number, not a new category of stored information.

## 10. On-chain architecture

**Chosen: fully on-chain (option 1 of the three offered).** Rejected
alternatives:

- **Off-chain calculated with signed updates**: introduces a new signer
  key as a trust assumption and a new liveness dependency (what happens
  if the off-chain signer is down — see Section 11) for a computation
  that's simple enough not to need it. Rejected for the MVP.
- **Partially on-chain** (e.g. off-chain aggregation feeding periodic
  on-chain checkpoints): same trust/liveness issues as fully off-chain,
  with added complexity from having two representations of the score
  (a checkpointed on-chain one and a more current off-chain one) that
  can disagree. Rejected for the MVP.

Fully on-chain is simplest, requires no new trust assumption beyond
what `BitVLendingManager` already has, and is well within gas
feasibility for an accumulator-style update (no loops over history —
see storage design below).

### `BitScoreManager` — storage

```solidity
struct ScoreState {
    uint8 score;                     // 0-100, current value after last decay application
    uint40 lastUpdateTimestamp;      // for lazy decay calculation
    uint32 successfulRepayments;     // count, for 4.1 (decayed contribution derived from this + timestamp)
    uint32 liquidationCount;         // count, for 4.6 (permanent count; decayed *score* contribution separate)
    uint32 badDebtCount;             // count, for 4.7 (permanent, never decayed)
    uint40 firstActivityTimestamp;   // for 4.8 tenure
}

mapping(address user => ScoreState) private _scores;
```

`score` narrows from `uint16` to `uint8` (0–100 fits comfortably; the
original 0–1000 needed `uint16`) — a genuine, if minor, storage-packing
benefit of the rescale. Internal fixed-point accumulators for the
fractional point deltas in Section 4 (e.g. tracked as tenths of a point)
are an implementation detail of the follow-up Solidity milestone, not
specified further here — see Section 3's note.

Kept deliberately minimal — no per-event history array (would grow
unbounded and be expensive to iterate); decay is computed from counts +
timestamps at read/update time, not by replaying history.

### Functions

- `recordRepayment(address user, bool wasFullClose, uint256 positionDurationSeconds)` —
  called only by `BitVLendingManager` (see Integration, Section 9)
  after a successful `repay()`. Applies 4.1/4.2 point deltas subject to
  the minimum-duration rule (Section 8).
- `recordLiquidation(address user, bool wasBadDebt)` — called only by
  `BitVLendingManager` after `liquidate()` completes. Applies 4.6 or 4.7
  penalty.
- `recordUtilizationSnapshot(address user, uint16 utilizationBps, uint16 healthFactorBps)` —
  called only by `BitVLendingManager` at natural checkpoints (borrow,
  repay, withdrawCollateral) — not a separate keeper-triggered function,
  to avoid needing external automation for the MVP. Applies 4.4/4.5
  deltas.
- `getScore(address user) external view returns (uint16 score)` — applies
  lazy decay to a *view* copy without writing state (state is only
  written on the next `record*` call) — cheap, callable by anyone,
  including `BitVLendingManager` itself when computing lending impact.
- `getTier(address user) external view returns (uint8 tier)` — derived
  from `getScore`.
- `getAdjustedParams(address user, address asset) external view returns (uint16 adjustedLtvBps, uint256 baseRateDiscountRay)` —
  the function `BitVLendingManager` actually calls (Section 9); combines
  tier + current utilization/health-factor tempering (Section 7) into
  concrete numbers, capped against the asset's own configuration read
  from `BitVPoolManager`.
- `setDecayParams(...)`, `setTierThresholds(...)`, `setInputWeights(...)`
  — `RISK_MANAGER_ROLE`-gated, so the specific numbers in Sections 4/6/7
  (all flagged as "suggested" throughout this document) are tunable
  without a redeploy, consistent with the existing protocol's
  configurable-parameters pattern
  (`docs/protocol-architecture.md`'s Risk Parameters section).
- `emergencyResetScore(address user)` — `RISK_MANAGER_ROLE`-gated,
  resets to 30 (Section 3's only reset path), emits a distinct event
  so it's auditable as an exceptional governance action, not confused
  with normal score movement.

### Access control

Uses the existing `BitVRoleConsumer` pattern
(`contracts/src/access/BitVRoleConsumer.sol`), reading from the same
`BitVAccessManager`:

- `record*` functions: restricted to a single registered
  `lendingManager` address (mirrors `BitVPoolManager.onlyLendingManager` —
  same trust-boundary pattern already established, not a new one).
- `setDecayParams`/`setTierThresholds`/`setInputWeights`:
  `RISK_MANAGER_ROLE`.
- `emergencyResetScore`: `RISK_MANAGER_ROLE`.
- `getScore`/`getTier`/`getAdjustedParams`: unrestricted views.

**Not** using `BitVComplianceGuard`/`Ownable` — that pattern exists
specifically for Cleanverse's documented `RuleV2` rule-management
convention (Section 2, principle 1) and BitScore has nothing to do with
Cleanverse compliance rules, so reusing it would blur the two systems
this document keeps separate.

### Events

`ScoreUpdated(address indexed user, uint16 oldScore, uint16 newScore, bytes32 reason)`,
`TierChanged(address indexed user, uint8 oldTier, uint8 newTier)`,
`EmergencyReset(address indexed user, address indexed admin)` — enough
for off-chain indexers/UI to reconstruct score history from events
alone, without needing the contract to store a history array on-chain.

### Score calculation / tier calculation

Both fully on-chain, both pure functions of stored state
(`ScoreState`) plus the current block timestamp (for decay) — no
external calls, no oracle dependency, no off-chain input at all.

## 11. Integration

```
User calls a BitVLendingManager function (e.g. borrow)
  ↓
BitVComplianceGuard._requireCompliance(msg.sender)
  → IAPassComplianceValidator.complianceVerify(pool, user)
  → false: revert ComplianceCheckFailed — BitScore is never consulted
  → true: continue
  ↓
BitVLendingManager reads base risk parameters from BitVPoolManager
  (ltvBps, liquidationThresholdBps, interest rate model output)
  ↓
BitVLendingManager calls BitScoreManager.getAdjustedParams(user, asset)
  → BitScoreManager reads the user's ScoreState, applies decay,
    derives tier, tempers by current utilization/health factor
    (Section 7), caps against the base parameters just read
  → returns adjusted (never worse than base for the user's benefit,
    except Tier 0's protective LTV reduction — see Section 6)
  ↓
BitVLendingManager uses the adjusted parameters for this action's
  LTV/rate check
  ↓
Action executes (or reverts on its own merits, e.g. still insufficient
  collateral even with the adjustment)
  ↓
On success, BitVLendingManager calls the relevant
  BitScoreManager.record*() function so future actions see updated state
```

**Compliance is always checked first and is never affected by
BitScore.** BitScore is always checked after compliance and before the
base-vs-adjusted parameter decision. Neither system can be bypassed by
going through the other — `BitVComplianceGuard` doesn't know
`BitScoreManager` exists, and `BitScoreManager` doesn't know
`IAPassComplianceValidator` exists; `BitVLendingManager` is the only
contract that talks to both, and only in the fixed order above.

## 12. Fail-safe behavior

| Condition | Behavior |
|---|---|
| BitScore unavailable (e.g. `BitScoreManager` not yet set on `BitVLendingManager`, or the call reverts unexpectedly) | Falls back to base asset-level parameters — treated identically to a Tier 1 (Standard) user. Never blocks the underlying lending action; BitScore is an *enhancement* to parameters, not a gate on the action itself (that's CVI's job). |
| Score corrupted (e.g. a stored value somehow outside 0–100 — shouldn't be reachable given clamping, but defensively checked) | `getScore`/`getAdjustedParams` treat any out-of-range stored value as Tier 1/base parameters rather than reverting the underlying lending action or extrapolating an invalid tier. |
| Score update fails (a `record*` call reverts) | The triggering action (repay/liquidate) that already completed is **not** rolled back by a scoring failure downstream of it — score-recording happens *after* the economically meaningful state change, in a way that doesn't let a scoring bug block real repayments/liquidations from succeeding. (Concretely: `record*` calls are the last step of the relevant `BitVLendingManager` function; if this needs a `try/catch` to fully decouple failure, that's a Section 13 open question for the Solidity milestone, not resolved here.) |
| User has no score (first-ever interaction) | Treated as the starting score (30, Tier 1) — not as an error state, not as Tier 0. `ScoreState` in storage defaults to all-zero, which `getScore` must interpret as "uninitialized → 30," not as "score is literally 0" (Tier 0) — an explicit `initialized` flag or equivalent is needed in the real struct to distinguish these two cases (noted for the Solidity milestone). |
| Score falls below minimum (0) | Already the floor — clamped, not an error. Tier 0 behavior (Section 6) applies; the user is not blocked from the protocol (that's still CVI's decision), only from any BitScore-driven improvement, and may see the protective LTV reduction. |
| Cleanverse verification unavailable (validator unreachable/reverts) | Unrelated to BitScore's fail-safe behavior — this is `BitVComplianceGuard`'s existing responsibility (a `complianceVerify` revert propagates and blocks the action entirely, per Build 02.x's design) and happens *before* BitScore is ever reached. BitScore has no independent behavior to define here; noted for completeness since the brief asked. |

## 13. Test plan

All tests below are for the future Solidity implementation — none exist
yet, per this milestone's "do not write Solidity" scope.

**Initial score**: new user's `getScore` returns 30 (Tier 1) with no
prior interaction.

**Successful repayment**: full-close repayment after minimum duration
increases score by the expected 4.1+4.2 delta; repeated repayments
accumulate up to the 4.9 cap and no further.

**Late repayment** *(reframed per 4.2 — BitV has no fixed due dates)*:
a position closed with very high accrued interest relative to principal
gets a smaller (or zero) 4.2 bonus than one closed promptly, per the
"proxy for active management" framing.

**Liquidation**: a liquidation event applies the -10 (full) or -5
(partial) penalty and increments `liquidationCount`; verify the
liquidated user's score reflects this immediately after the triggering
`liquidate()` call in the same transaction.

**Bad debt**: an insolvent liquidation (the capped-seizure path in
`BitVLendingManager.liquidate`) applies the -30 penalty, increments
`badDebtCount`, and this penalty does not decay across a warped-forward
timestamp in a test.

**Score recovery**: after a liquidation, sustained qualifying
repayments over time raise the score back up, more slowly than the
same repayments would from a clean starting point (since the 4.9 cap
counts total accumulated positive contribution, not "extra on top of
the penalty").

**Score decay**: warp time forward past a decay window (e.g. 200 days
for 4.1/4.2's 180-day window) with no further activity; verify score
has decayed back toward 30 by the expected amount, while
`liquidationCount`/`badDebtCount` (permanent counts) are unchanged.

**Tier changes**: crossing a tier boundary (e.g. 49 → 50) via a
qualifying event emits `TierChanged`; crossing back down (decay or
penalty) also emits it.

**LTV adjustment**: a Tier 2/3 user's `getAdjustedParams` returns a
higher `adjustedLtvBps` than a Tier 1 user's, both capped at the
asset's configured `ltvBps` when the asset's ceiling is tight; a Tier 0
user's is *lower* than base (protective reduction).

**Borrowing limit adjustment**: verify `getAdjustedParams` never
returns anything that would let `BitVLendingManager.borrow`'s
LTV check pass a case that should fail against the pool's actual
liquidity/borrow cap — i.e. BitScore's output is provably still bounded
by `BitVPoolManager`'s own limits in a test that tries to exploit a
high score against a capacity-constrained pool.

**Interest adjustment**: Tier 2/3 discount applies only to the
base-rate component (verify by comparing `getAdjustedParams`'s
rate output against `KinkedInterestRateModel`'s raw output at a fixed
utilization — the *difference* should be independent of utilization,
proving the utilization/slope components weren't touched).

**Anti-gaming**: instant open/close cycle (same-block or
sub-minimum-duration) earns zero 4.1/4.2 credit; rapid repeated
small-amount actions don't exceed the same-window accumulation a single
larger equivalent action would give (bounding farming's advantage over
genuine use).

**Unauthorized score updates**: any address other than the registered
`lendingManager` calling `record*` reverts
(`ProtocolErrors.Unauthorized`-style, matching the existing pattern);
any non-`RISK_MANAGER_ROLE` caller of `setDecayParams`/
`emergencyResetScore` reverts.

**Compliance failure**: a `complianceVerify`-failing user's transaction
reverts at `BitVComplianceGuard` before `BitScoreManager` is ever
called — verify (e.g. via a call-count check or a revert-reason
assertion) that no `BitScoreManager` state changes when compliance
fails.

**Missing score**: a brand-new address's `getScore`/`getAdjustedParams`
return the Tier 1/base-parameter defaults without reverting.

## Future improvements (not in MVP scope)

- Position-size-relative weighting (Section 8, small-volume farming
  mitigation) — weight point deltas by how large a position is relative
  to the user's own historical typical size, rather than flat per-event
  points.
- Cross-asset reputation weighting (does consistent good behavior on
  one asset say anything about a brand-new asset the user hasn't
  touched?) — deliberately not addressed; this spec treats BitScore as
  a single protocol-wide number, not per-asset, for MVP simplicity, but
  the tradeoffs of that choice aren't fully explored here.
- A formal wash-borrowing mitigation beyond rate-limiting via caps/
  decay (Section 8) — flagged as unsolved, not solved.
- Governance-facing analytics/visualization of score distribution
  (out of scope for a risk-parameter spec).

---

## Open design questions (flagged, not resolved here)

1. Should `record*` calls be wrapped in `try/catch` inside
   `BitVLendingManager` so a `BitScoreManager` bug can never block a
   real repayment/liquidation (Section 12), or should the trust
   boundary instead guarantee `BitScoreManager` can't revert by
   construction (no external calls, no complex logic)? Leaning toward
   the latter (simpler, no need for `try/catch`'s own gas/behavior
   subtleties) but not decided.
2. Should tenure (4.8) require the wallet to have *both* supplied and
   borrowed, or does either alone count? Current draft doesn't
   distinguish; may matter for a supply-only user who never touches
   lending — should they have a BitScore at all, given it's framed
   entirely around lending risk?
3. Is a single protocol-wide score (vs. per-asset) the right MVP
   choice given BitV's cross-margin lending model already aggregates
   risk across assets at the position level (`docs/protocol-
   architecture.md`)? Leaning yes (consistency with the existing
   cross-margin design) but flagged for review.
4. Exact numeric values throughout (point deltas, decay windows, tier
   boundaries, adjustment caps) are all marked "suggested" — this
   document defines the *shape* of the system with concrete illustrative
   numbers, not final calibration, which likely needs simulation
   against realistic usage patterns before a Solidity implementation
   locks them in (even as `RISK_MANAGER_ROLE`-tunable parameters,
   starting values matter for early-adopter fairness).
5. Should `getAdjustedParams` be a single combined view call (as
   drafted) or should `BitVLendingManager` call narrower
   `getAdjustedLtv`/`getAdjustedRate` separately? Combined reduces
   external calls; separate is more flexible if only one parameter is
   needed in some code path. Not decided.
