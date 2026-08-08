# BitScore Implementation (Build 04)

**Scale note (post-implementation spec update):** `docs/bitscore-
specification.md` was subsequently revised to a 0–100 score range
(from the 0–1000 range this document and the deployed contracts still
use). That revision was explicitly documentation-only — no Solidity was
touched. Everything below accurately describes the contracts as they
exist right now (0–1000, start 300, tiers at 250/500/750). Treat every
score number in this document as **on the pre-rescale 0–1000 scale**
until a follow-up implementation milestone updates
`BitScoreManager.sol` (and this document) to match the new
specification — see that document's own status banner for the
authoritative current target.

Implements `docs/bitscore-specification.md` (as it stood at
implementation time). This document records what was actually built,
where implementation diverged from the spec's illustrative sketch (and
why), and what remains a known limitation.

## Contract architecture

New: `contracts/src/core/BitScoreManager.sol`, implementing
`IBitScoreManager` (`contracts/src/interfaces/IBitScoreManager.sol`).
Inherits `BitVRoleConsumer` (the shared `PROTOCOL_ADMIN_ROLE`/
`RISK_MANAGER_ROLE`/`POOL_MANAGER_ROLE`/`PAUSER_ROLE` pattern already
used by `BitVPoolManager`/`BitVLendingManager`) — deliberately **not**
`BitVComplianceGuard`/`Ownable`, which exists specifically for
Cleanverse's `RuleV2` rule-management convention and has nothing to do
with BitScore. `BitScoreManager` never imports, calls, or references
`IAPassComplianceValidator` — the structural separation the spec
insisted on is enforced by the contract's own import graph, not just by
convention.

## State model

```solidity
struct ScoreState {
    bool initialized;
    uint16 positiveContribution;   // capped, decaying accumulator
    uint40 lastPositiveUpdateTimestamp;
    uint16 liquidationPenalty;     // decaying
    uint40 lastLiquidationTimestamp;
    uint16 badDebtPenalty;         // permanent, never decays
    uint16 tenureCredited;         // tenure points already granted, so they aren't re-added
    uint32 successfulRepayments;   // count, informational
    uint32 liquidationCount;       // count, informational
    uint32 badDebtCount;           // count, informational
    uint40 firstActivityTimestamp;
}
```

**Deviation from the spec's sketch, documented explicitly (per the task's
"do not redesign unless implementation reveals a direct contradiction"
allowance — this is a tractability simplification, not a contradiction):**
the spec described separate decay windows per input category (repayments
180 days, utilization/collateralization 30 days). This implementation
consolidates every positive input (repayments, timeliness, tenure,
low-utilization bonus) into **one** decaying `positiveContribution`
accumulator with a single decay window. The per-input *point values* and
the *overall cap* (700) are preserved from the spec; only the "how many
separate decay clocks" mechanic was simplified, for a smaller, more
auditable state struct and fewer interacting decay curves to reason
about. Liquidation penalties still decay on their own, slower, separate
clock; bad-debt penalties still never decay — both exactly as specified.

## Score updates

Event-driven, O(1) per call — no history replay. Every mutating
`record*` call follows a "decay-then-add" pattern
(`_applyPositiveDelta`/`_applyLiquidationPenalty`): decay the currently
stored value based on elapsed time since its own last update, then add
the new delta, then clamp, then stamp the new timestamp. `getScore` is a
pure view that applies the same decay formula without writing state, so
reads are always consistent with "decay as of now" without needing a
keeper to periodically touch every user's storage.

**Empirically observed behavior worth documenting**: because decay is
recalculated relative to the *previous* update on every new event, an
accumulator that receives events frequently relative to its decay window
converges toward a stable equilibrium **below** the nominal cap, rather
than climbing linearly toward it and stopping. At this deployment's
default parameters (180-day decay window, qualifying repayments roughly
every 2 days in the test fixture's cadence), the positive accumulator
equilibrates in the mid-500s (raw) rather than reaching 700 — i.e. a
sustained, maximally-active user's score plateaus somewhere in the
800s–900s under these specific parameters, not exactly at 1000. This is
consistent with the design intent (the cap is a ceiling that's *never
exceeded*, verified by both scenario and fuzzed invariant tests) but
worth knowing explicitly: **reaching literally 1000 requires either a
much longer time horizon, less frequent decay-triggering events per
point earned, or `RISK_MANAGER_ROLE`-tuned parameters** — it is not
something a test needed to demonstrate to prove the cap itself is safe
(and the invariant test suite proves the cap holds under arbitrary
fuzzed activity, not just the scenario tests' specific cadence).

## Tier calculation

Pure function of the decayed score, four bands exactly as specified:
Restricted (0–249), Standard (250–499, includes the 300 starting score),
Established (500–749), Trusted (750–1000). `_tierOf` is `internal pure`,
called by both `getTier` and internally wherever a tier-dependent
adjustment is computed — no separate on-chain "current tier" storage
field exists, since it's always cheap to derive from the score.

## Lending integration

### LTV adjustment (real, wired into actual borrow capacity)

`DataTypes.Pool` gained a new field, `maxLtvWithScoreBps` — the absolute
LTV ceiling BitScore may ever raise a user to for that asset, distinct
from the base `ltvBps` everyone gets by default. `_validateRiskParams`
enforces `ltvBps <= maxLtvWithScoreBps <= liquidationThresholdBps` at
configuration time (`createPool`/`setRiskParams`), so a misconfigured
ceiling that would let a score-boosted position start life already
liquidatable is rejected before it can ever be used. Equal to `ltvBps`
by default (no bonus possible) unless `RISK_MANAGER_ROLE` explicitly
configures headroom.

`DataTypes.AccountData` gained `weightedMaxLtvValue` (parallel to the
existing `availableBorrowValue`, but weighted by `maxLtvWithScoreBps`
instead of `ltvBps`), computed in the same aggregation loop in
`_accountData` at negligible extra cost.

`BitVLendingManager._effectiveAvailableBorrowValue(user, data)` is the
actual integration point, called from `borrow()` in place of the raw
`data.availableBorrowValue`:

1. If `bitScoreManager` is unset (`address(0)`), return
   `data.availableBorrowValue` unchanged — disabled, fail-safe default.
2. Otherwise, `try` calling
   `bitScoreManager.getAdjustedAvailableBorrowValue(user, base, max, totalDebtValue, totalCollateralValue)`.
3. **On success**, the returned value is *still* re-clamped to `max`
   at the call site — defense in depth: even a correctly-implemented
   `BitScoreManager` is never trusted alone to respect the ceiling; the
   caller enforces it independently. This is what makes "score cannot
   bypass hard protocol limits" a provable property of
   `BitVLendingManager`, not just an assumption about `BitScoreManager`'s
   internals.
4. **On any revert** (`catch`), fall back to `data.availableBorrowValue` —
   the base, score-independent figure. Never a partial/corrupted result.

### Why the adjustment is provably bounded

`BitScoreManager.getAdjustedAvailableBorrowValue` computes
`bonus = headroom * tierFraction * temperFraction`, where `headroom =
maxAvailableBorrowValue - baseAvailableBorrowValue` (i.e. by
construction, `bonus <= headroom`), and both `tierFraction` and
`temperFraction` are `<= 10_000` (basis points), so `bonus <= headroom`
always. `adjusted = base + bonus <= base + headroom = max`. The final
line still clamps explicitly (`adjusted > max ? max : adjusted`) as a
second, independent guarantee rather than relying purely on the algebra
above. `BitVLendingManager` then re-clamps a *third* time at the call
site (step 3 above). Three independent layers, not one.

**Utilization tempering**: `temperFraction = 10_000 - utilizationBps`
(full bonus at 0% utilization, zero bonus at 100%), where
`utilizationBps = totalDebtValue * 10_000 / totalCollateralValue`,
capped at `10_000`. Matches the spec's "current utilization tempers
rather than blocks" requirement.

**Tier 0 (Restricted)**: instead of a positive headroom fraction, applies
a *protective reduction* — `20%` of the base available-borrow-value,
subtracted (floored at 0). A bad score can only ever *reduce* a user's
own borrowing power below the same-collateral Tier 1 baseline, never
increase anyone else's risk.

### Interest rate adjustment: quoted only, NOT wired into real accrual

**This is the one place implementation revealed a direct contradiction
with the spec's Section 7 table, resolved rather than silently ignored
or forced through:** `BitVPoolManager` computes interest via a single
shared `borrowIndexRay` per pool (`docs/protocol-architecture.md`'s
interest model) — every borrower's debt grows by the *same* index
multiplier. A genuinely per-user differentiated interest rate (a real
Tier 3 discount that changes how fast *that specific user's* debt
compounds) is architecturally incompatible with a shared-index pool
without a much larger redesign (per-user indices, or a
shadow-accounting layer) — squarely "core lending economics," which
this milestone was explicitly told not to modify except where
*necessary* for the approved integration, and a full interest-model
rewrite is not necessary for BitScore's MVP.

**Resolution**: `getBaseRateDiscountRay(user)` and
`BitVLendingManager.getQuotedBaseRateDiscountRay(user)` exist, return
tier-appropriate bounded values (0 for Tier 0/1, 0.5% for Tier 2, 1% for
Tier 3, all `RISK_MANAGER_ROLE`-tunable), and are tested — but they are
**informational/quoted only**. Nothing in `BitVPoolManager.accrueInterest`
or `KinkedInterestRateModel` was touched; every borrower in a pool still
accrues against the exact same shared index regardless of tier. This is
called out explicitly in the interface's NatSpec, this document, and the
spec update below, rather than left to look like a real discount that
silently does nothing.

## Adjustment caps (explicit, deterministic)

| Tier | LTV adjustment | Interest (quoted only) |
|---|---|---|
| 0 (Restricted) | −20% of base available-borrow-value (protective) | 0 |
| 1 (Standard) | 0 (unchanged) | 0 |
| 2 (Established) | up to 50% of the configured LTV headroom, tempered by utilization | 0.5% (5e24 ray) |
| 3 (Trusted) | up to 100% of the configured LTV headroom, tempered by utilization | 1% (1e25 ray) |

All four rows are `RISK_MANAGER_ROLE`-tunable via `setTierAdjustments`
(bounds-checked: `ltvHeadroomBps` must be in `[-10000, 10000]`), and
`setParams` for the scoring-side constants (decay windows, per-event
points, minimum position duration, etc.) — none of the illustrative
numbers in the spec or this document are hardcoded without a governance
escape hatch.

## Failure handling

Exactly the spec's Section 12 table, implemented via Solidity
`try`/`catch` at every BitScore call site in `BitVLendingManager`:

| Condition | Implementation |
|---|---|
| BitScore unavailable (`bitScoreManager == address(0)`) | Every integration point checks this first and returns/skips before attempting a call |
| BitScore call reverts (unexpected internal failure) | `try`/`catch` around `getAdjustedAvailableBorrowValue`, `getBaseRateDiscountRay`, and all three `record*` calls; `catch` returns the base/neutral value (LTV, rate) or silently no-ops (repayment/liquidation/utilization recording), emitting `BitScoreUpdateFailed(user, action)` for the recording failures so it's observable off-chain without blocking the real economic action |
| Score corrupted (out-of-range stored value) | Not independently reachable given `getScore`'s own `int256` clamp to `[0, 1000]` before casting back to `uint16` — the clamp runs on every read, not just at write time |
| Missing score (first interaction) | `ScoreState.initialized == false` → `getScore` returns `params.startScore` (300) directly, without touching storage |
| Score at floor (0) | Not an error state — Tier 0 behavior applies (protective reduction), the user is not blocked from the protocol (CVI remains the only eligibility gate) |
| Cleanverse verification unavailable | Unrelated to BitScore — `BitVComplianceGuard._requireCompliance` reverts before any BitScore call is ever reached; unchanged from Build 02.x |

**Never falls back to something more favorable than base** — verified
directly by `invariant_BitScoreFailureNeverMoreFavorableThanBase`
(`contracts/test/invariant/BitVInvariant.t.sol`), which disables
BitScore mid-fuzz-run and asserts every actor's effective available
borrow value exactly equals their base figure, under arbitrary
accumulated state.

## Access control

- `record*` (repayment/liquidation/utilization): `onlyLendingManager` —
  a single registered address, mirroring
  `BitVPoolManager.onlyLendingManager`'s existing trust-boundary pattern
  exactly (same rationale: not designed for multiple callers).
- `setParams`, `setTierAdjustments`, `emergencyResetScore`:
  `RISK_MANAGER_ROLE`.
- `setLendingManager`: `PROTOCOL_ADMIN_ROLE` (on `BitScoreManager` itself).
- `setBitScoreManager` (wiring it into `BitVLendingManager`, including
  disabling it via `address(0)`): `PROTOCOL_ADMIN_ROLE` (on
  `BitVLendingManager`).
- `getScore`/`getTier`/`getAdjustedAvailableBorrowValue`/
  `getBaseRateDiscountRay`/`getRawState`: unrestricted views.

Users cannot call any `record*` function, cannot call
`emergencyResetScore`, and have no path to directly write their own
score under any role.

## Events

`ScoreUpdated(user, oldScore, newScore, reason)`,
`TierChanged(user, oldTier, newTier)` (only emitted when a boundary is
actually crossed), `EmergencyReset(user, admin)`,
`LendingManagerSet`, `ParamsUpdated`, `TierAdjustmentsUpdated` (admin
config changes), and — on the `BitVLendingManager` side —
`BitScoreManagerSet` and `BitScoreUpdateFailed(user, action)` for
observable fail-safe fallback events. No personal data in any event —
only addresses, score numbers, and a `bytes32` reason tag.

## Security assumptions

- BitScore is trusted by `BitVLendingManager` only up to the
  independently-enforced ceiling (defense in depth, Section "Why the
  adjustment is provably bounded" above) — a bug in `BitScoreManager`
  cannot let any user borrow beyond `maxLtvWithScoreBps`, because
  `BitVLendingManager` re-derives and re-clamps that ceiling itself from
  `BitVPoolManager`'s own configuration, never trusting a value
  `BitScoreManager` returns unchecked.
- `record*` calls happen *after* the triggering economic action's core
  state changes in `repay()`/`liquidate()` (transfer, debt reduction),
  so a `BitScoreManager` failure cannot roll back or block a real
  repayment or liquidation from completing.
- The `type(uint256).max` repay-sentinel fix (see "Bug found and fixed"
  below) closes a precision gap that would otherwise have made
  `wasFullClose` detection unreliable for *any* caller computing an
  exact repay amount off-chain, not just for BitScore — a genuine
  correctness improvement to `BitVLendingManager.repay()`, not a
  BitScore-only patch.
- No BitScore-specific reentrancy surface: `BitScoreManager` makes no
  external calls of its own (no token transfers, no oracle reads) — it
  is pure storage arithmetic behind role checks, called by
  `BitVLendingManager`'s already-`nonReentrant`-guarded functions.

## Bug found and fixed during implementation

**`BitVLendingManager.repay()`'s full-close detection was unreliable
even before BitScore** — `rayDiv(rayMul(scaledDebt, index), index)` is
not guaranteed to land back at exactly `scaledDebt` (both round to
nearest independently), so a "repay my exact current debt" call
computed by reading `getCurrentDebt()` off-chain and passing that amount
would routinely leave 1 wei of scaled debt behind. `_userDebtAssets`
would never actually clear for that asset, and — once BitScore's
`wasFullClose` signal started depending on this — full-close credit was
never awarded, discovered via this milestone's test suite (see the
`test_Debug_ScoreGrowth` exploration, not kept in the final test files).

**Fixed two ways, together:**
1. `repay()` now supports `amount == type(uint256).max` as "repay my
   exact current debt," mirroring the pattern already established in
   `BitVPoolManager.withdraw()`. This is the recommended way to fully
   close a position and is what the BitScore test suite's helper
   (`_borrowAndFullyRepayAfter`) uses.
2. Full-close detection itself was changed from a scaled-balance
   comparison (`rayDiv(repaid) >= scaledDebt`) to a direct
   underlying-amount comparison (`repaid == currentDebt`), which is
   exact by construction rather than dependent on round-trip rounding —
   and when true, the scaled balance is set to exactly `0` rather than
   subtracted, removing the dust instead of just detecting around it.

This was a real, pre-existing precision bug in core lending logic,
fixed because it was *necessary* to make the approved BitScore
integration function correctly — not a scope-creep rewrite of repay().

## Known limitations

- **Interest rate adjustment is quoted-only** (see above) — a real
  per-user rate is out of scope without a shared-index redesign.
- **Decay convergence below nominal cap at frequent event cadences**
  (see "Score updates" above) — documented, not a safety issue (the cap
  itself is never violated, proven by fuzzed invariant), but means
  "reaching exactly 1000" isn't guaranteed within any bounded number of
  events at default parameters.
- **Wash-borrowing remains unresolved**, exactly as the specification
  flagged — nothing in this implementation adds a mitigation beyond
  what Section 8 of the spec already described (rate-limiting via caps/
  decay). Not claimed as solved.
- **Single protocol-wide score, not per-asset** — as drafted in the
  spec's open question #3, unresolved either way; this implementation
  keeps it single/global, consistent with the cross-margin design.
- **`recordUtilizationSnapshot`'s negative-adjustment path was not
  implemented** — per the spec's own §4.4 simplification note, only a
  small positive credit for sustained low utilization + high health
  factor exists; no direct penalty for high utilization via this path
  (indirectly captured through the liquidation penalty instead, since
  sustained high utilization is what leads to liquidations).
- **Tenure credit only accrues alongside a qualifying repayment event**
  (per spec open question #2, resolved here) — a supply-only user who
  never borrows/repays earns no tenure credit and effectively never
  moves off the starting score. This matches the spec's framing of
  BitScore as lending-risk-specific, but means supply-only users have no
  BitScore differentiation at all.
