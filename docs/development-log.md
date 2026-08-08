# BitV Development Log

Every milestone updates this file. Newest entry first.

---

## Milestone 7.1 — CVA integration specification (Build 07)

**Date:** 2026-08-08

**Context:** Documentation-only. No Solidity written or modified —
every existing contract (`BitVAccessManager`, `BitVComplianceGuard`,
`BitVPoolManager`, `BitVLendingManager`, `BitVVaultManager`,
`BitScoreManager`, `BitVTreasury`, `BitVRWACollateralRegistry`) is
untouched. No new Cleanverse source material was available this
milestone — this specification is built entirely from the two official
PDFs already transcribed in `docs/cleanverse-integration.md` (Build
02.1/02.5/02.6); nothing was re-derived or re-searched beyond that
existing transcription.

**Deliverable:** `docs/cva-integration-specification.md` — full
specification covering the CVA definition, registration flow, exact
(and honestly incomplete) contract interface, RuleV2 semantics, the
transfer flow, a proposed `BitVCVAAdapter`, RWA registry integration,
lending/vault integration, settlement (mostly `UNCONFIRMED`),
compliance ordering, failure handling, security model, architecture
decision, per-contract impact table, test plan, a full Cleanverse
dependency table, and a final recommendation.

**Core finding driving the whole design**: no Cleanverse document
confirms an on-chain query for "is this token actually
Cleanverse-approved as a CVA" — only the on-chain *behavior* of a CVA
token (implementing `IATokenPolicy`, responding to `canTransfer`/
`getRulesV2`) is verifiable by BitV directly. This means
`BitVRWACollateralRegistry`'s current bare `isCVA` admin-attested bool
cannot be meaningfully strengthened into a "verified" flag by Solidity
alone — the specification's two-flag model (`adminAttestedCVA` +
`onChainInterfaceVerified`) raises the bar (a token must be a real,
responding contract implementing the right interface) without ever
claiming to fully solve Cleanverse-approval verification, which remains
fundamentally an off-chain fact.

**Recommended architecture**: (D) — a new, thin, replaceable
`BitVCVAAdapter` (owns 100% of the actual Cleanverse-interface-calling
logic) paired with an additive extension of
`BitVRWACollateralRegistry`'s existing `isCVA` field into the two-flag
model above. No other existing contract requires modification — zero
or additive changes throughout, per instruction.

**Key `UNCONFIRMED` items, not invented around**: `canTransfer`'s
return type/visibility/mutability; whether a rejected transfer reverts
or returns `false`; any CVA freeze/revoke mechanism; the CVA
registration review/approval process; any CVA settlement/recovery/
redemption/treasury/cross-chain mechanism; CVA events. Full dependency
table in the specification's §17.

**Not done (per instruction):** no Solidity written, no contracts
modified, nothing deployed, no Cleanverse functionality invented, no
addresses/endpoints/signatures/events fabricated.

**Next recommended milestone**: implement `BitVCVAAdapter` and the
`CVAStatus` extension to `BitVRWACollateralRegistry` per this
specification — blocked on obtaining full `canTransfer`/`RuleV2`
policy-interface signatures and the transfer-rejection mechanism from
Cleanverse directly (specification §18's deployment blockers).

---

## Milestone 6.2 — RWA collateral registry implementation (Build 06.1)

**Date:** 2026-08-08

**Context:** Implements `docs/rwa-market-specification.md` (Build 06)
exactly, per the approved architecture decision (B) — no redesign of
the lending/liquidation engine. `BitVLendingManager` remains
responsible for all collateral/debt accounting, LTV, health factor,
borrowing, repayment, and liquidation.

**Contracts created:**
- `BitVRWACollateralRegistry.sol` — registration, asset status
  (Active/Frozen/Delisted), oracle staleness tracking, collateral caps,
  allowed-debt-asset restrictions. Owns exactly one responsibility:
  whether a registered RWA asset's collateral counts toward NEW
  borrowing capacity.
- `IRWACollateralRegistry.sol` — narrow interface boundary, mirroring
  `IBitScoreManager`'s role for `BitScoreManager`.
- `RWAErrors.sol` — RWA-specific error library.

**Contracts modified:** `BitVAccessManager.sol` (added
`RWA_ADMIN_ROLE`, `ORACLE_MANAGER_ROLE`); `BitVLendingManager.sol` —
added an optional, `try`/`catch`-wrapped, fail-safe registry
integration: a new `depositCollateral` eligibility/cap check, a
`debtAssetFilter`-aware `_accountData` overload that zeroes a
registered-but-ineligible asset's LTV contribution (while leaving its
health-factor/liquidation weighting untouched), and a simple aggregate
`_totalCollateralByAsset` counter for cap enforcement. No existing
function signature was narrowed; every change is additive and
inert for assets never registered with the registry.

**Key decisions, matching the approved spec exactly:** four asset
states (Unregistered/Active/Frozen/Delisted, `Suspended` folded into
`Frozen` + independent oracle-staleness tracking, per the task's
explicit narrowing); frozen/delisted assets keep repayment/withdrawal/
liquidation available while new deposits and new borrowing stop;
oracle staleness tracked registry-side (`markPriceFresh` attestation)
since `IPriceOracle` itself has no timestamp and was not modified; zero/
stale/unavailable price always treated as ineligible, never favorable;
the four-layer LTV bound (pool hard limit -> RWA asset hard LTV ->
BitScore adjustment -> registry maximum) verified end to end; only two
new roles (`RWA_ADMIN_ROLE`, `ORACLE_MANAGER_ROLE`), `RISK_MANAGER_ROLE`/
`PAUSER_ROLE` reused.

**One real design tension surfaced and documented, not silently
resolved as a bug-fix**: the registry's own risk-parameter fields are
validated against, but not used instead of, `BitVPoolManager.Pool`'s
own values for live LTV/threshold weighting — avoiding a second,
independently-drifting number feeding the same calculation. Flagged as
a known limitation (see `docs/rwa-market-implementation.md`) rather
than silently assumed solved.

**Tests created:** `BaseRWATest.sol` fixture,
`BitVRWACollateralRegistry.t.sol` (48 scenario tests: registry,
collateral, oracle, borrowing, liquidation, compliance, security),
`RWAHandler.sol` + `BitVRWAInvariant.t.sol` (10 fuzzed invariants, 256
runs / 128,000 calls each, covering all nine properties the task
specified plus cap-authorization).

**One invariant assertion caught and corrected during its own review**
(not a contract bug): an initial invariant asserted total collateral
never exceeds the *current* cap, which fails once an admin legitimately
lowers a cap below an already-deposited total (the same non-retroactive
semantics `BitVPoolManager.Pool.supplyCap` already has) — corrected to
assert the actually-guaranteed property: once at/above cap, no further
deposit can push it higher.

**Full Foundry suite — actually executed:** `forge test` after a clean
`forge build`. Result: **10 suites, 181 tests, 181 passed, 0 failed, 0
skipped** — the two new RWA suites (48 unit + 10 invariant) plus all
eight pre-existing suites (123 tests, including the yield vault's 44
unit + 8 invariant tests) unchanged, confirming no regression to the
lending/compliance/BitScore/vault engine.

**Not done (per instruction):** no new lending engine, no new
liquidation engine, no governance, no cross-chain, no production CVA
settlement, nothing deployed.

**Known limitations:** registry LTV fields are validated-but-not-live-
enforced independently of the pool's own values; collateral cap is
deposit-time-enforced only, not continuously true after a retroactive
lowering; a delisted/frozen asset whose oracle also fails entirely can
become practically unliquidatable (inherited from the pre-existing,
unmodified `_valueOf` zero-price revert, not introduced here) — all
documented in full in `docs/rwa-market-implementation.md`.

---

## Milestone 6.1 — RWA-backed market specification (Build 06)

**Date:** 2026-08-08

**Context:** Documentation-only. No Solidity written or modified — every
existing contract (`BitVPoolManager`, `BitVLendingManager`,
`BitVComplianceGuard`, `BitScoreManager`, `BitVYieldVault`,
`BitVTreasury`, `BitVAccessManager`) is untouched.

**Deliverable:** `docs/rwa-market-specification.md` — full specification
covering purpose, architecture decision, Cleanverse/CVI/CVA integration,
asset registry, collateral verification, oracle model, LTV model,
borrowing, liquidation, frozen-asset handling, access control,
compliance, risk controls, security model, privacy, test plan, future
extensions, and open questions.

**Key decisions:**
- **Architecture: (B) a dedicated `BitVRWACollateralRegistry` contract
  connected to `BitVLendingManager` via a narrow, optional,
  `try`/`catch`-wrapped interface** — mirrors the `BitScoreManager`
  integration pattern (Build 04) exactly, rather than extending
  `BitVLendingManager` directly. The existing collateral/borrow/repay/
  liquidate engine is reused 100% unmodified; the registry only adds an
  upstream gate on whether a given RWA asset's collateral currently
  counts toward *new* borrowing capacity.
- **CVI unchanged, CVA not issued** — BitV remains a CVA *consumer*, not
  an issuer, consistent with `docs/cleanverse-integration.md` §3. No CVA
  contract address, API, or verification field is invented; where
  Cleanverse doesn't expose an on-chain "is this asset verified" query,
  the spec designs a BitV-controlled, admin-attested registry boundary
  instead of pretending one exists.
- **Hard LTV ceilings preserved exactly as Build 04's pattern already
  guarantees** — BitScore adjusts within a registry/pool-configured
  `maxLtvWithScoreBps` ceiling, never past it; no new LTV mechanism is
  introduced for RWA collateral.
- **Liquidation engine reused unmodified** — no duplicate liquidation
  logic. RWA-specific liquidation considerations (illiquid collateral,
  delayed settlement, market closure, frozen assets, oracle failure,
  redemption restrictions) are resolved via a single choke point: the
  registry's "is this asset's collateral available for new borrowing
  capacity" check, plus an explicit table of which operations
  (deposit/borrow/repay/withdraw/liquidate) remain available under each
  `AssetStatus`. Frozen/delisted assets always keep repayment,
  withdrawal, and liquidation available — never new deposits or new
  borrowing.
- **Oracle staleness gap identified, not hand-waved** — the existing
  `IPriceOracle`/`StaticPriceOracle` have no timestamp field at all;
  this is flagged as a real implementation dependency requiring either
  an interface extension or a new staleness-aware adapter, not silently
  assumed solved. Zero price and stale price are both treated as
  "unavailable," never as valid data.
- **Roles: two new, not four** — `RWA_ADMIN_ROLE` and
  `ORACLE_MANAGER_ROLE` are added; the task's `RISK_MANAGER` and
  `PAUSER` roles are the *existing* `RISK_MANAGER_ROLE`/`PAUSER_ROLE`
  reused directly, per "do not create unnecessary roles."

**Not done (per instruction):** no Solidity written, no contracts
modified, nothing deployed.

**Next recommended milestone:** implement `BitVRWACollateralRegistry`
and the narrow `IRWACollateralRegistry` interface per this
specification, wire the two new roles into `BitVAccessManager`, resolve
open question 6 (oracle interface evolution) before writing the
staleness-aware oracle adapter, and build the Foundry test suite per
§18.

---

## Milestone 5.2 — Permissioned yield vault implementation (Build 05.1)

**Date:** 2026-08-08

**Context:** Implements `docs/yield-vault-specification.md` (Build 05)
exactly, per the approved architecture — no redesign. Existing lending/
liquidation/compliance/BitScore contracts untouched.

**Contracts created:**
- `BitVYieldVault.sol` — `ERC4626 + BitVComplianceGuard +
  BitVRoleConsumer + ReentrancyGuard`. Owns accounting, compliance,
  limits, pause, and fee logic.
- `IBitVVaultStrategy.sol` — vault↔strategy interface boundary.
- `TestYieldStrategy.sol` — explicitly non-production placeholder
  strategy (guarded constructor, no real yield claimed).
- `VaultErrors.sol` — vault-specific error library.

**Contracts modified:** `BitVAccessManager.sol` — added
`VAULT_MANAGER_ROLE` and `STRATEGY_MANAGER_ROLE` (exactly two new
roles, per spec §8).

**Key decisions, matching the approved spec exactly:** ERC-4626 with a
conservative fixed decimal offset of 6 (inflation-attack mitigation);
CVI as the sole eligibility layer, BitScore not integrated; shares
non-transferable (`_update` reverts on any real transfer); deposit/
withdraw restricted to self-service (`receiver == owner == msg.sender`)
as an implementation-level closure of an unenumerated-but-related
bypass; performance-fee-only, capped at 20%, flowing to the existing
`BitVTreasury` via its unmodified `receiveFee` entry point; vault
liquidity kept completely independent from lending pools; safest-by-
default limits (100% idle reserve, 0% strategy allocation) until an
admin explicitly opts in.

**Two real bugs found and fixed during implementation (not
hypothetical):**
1. The first fee design minted fee shares at the pre-mint price, then
   immediately re-converted those same shares to assets at the
   post-mint (self-diluted) price — under-paying a configured 10% fee
   on a 500e18 profit by ~3.2% (48.4e18 instead of 50e18). Fixed by
   tracking `accruedFeeShares`/`accruedFeeAssets` as an explicit ledger
   at accrual time rather than re-deriving via a second conversion.
2. The high-water-mark's zero initial value would have taxed a
   *second* depositor's principal as if it were profit relative to the
   first depositor's contribution. Fixed by bumping the mark by the
   exact principal delta on every deposit/mint/withdraw/redeem/fee-
   collection, so only genuine strategy-driven growth is ever taxed.

**Tests created:** `BaseVaultTest.sol` fixture,
`MockReentrantVaultERC20.sol`, `BitVYieldVault.t.sol` (44 scenario
tests: access, accounting, security, strategy, fees, pause,
compliance), `VaultHandler.sol` + `BitVYieldVaultInvariant.t.sol` (8
fuzzed invariants, 256 runs / 128,000 calls each).

**Full Foundry suite — actually executed:** `forge test` after a clean
`forge build`. Result: **8 suites, 123 tests, 123 passed, 0 failed, 0
skipped** — the two new vault suites plus all six pre-existing suites
unchanged, confirming no regression to the lending/compliance/BitScore
engine.

**Not done (per instruction):** no pool-as-strategy integration, no
BitScoreManager dependency, no production yield strategy, no RWA
markets, no governance, nothing deployed.

**Known limitations:** `maxWithdraw`/`maxRedeem` aren't overridden for
real-time liquidity/pause signaling (actual `withdraw`/`redeem` still
enforce correctly via reverts); emergency withdrawal is all-or-nothing,
idle-only, and does not accrue the performance fee (deliberate
simplifications, documented in `docs/yield-vault-implementation.md`).

---

## Milestone 5.1 — Permissioned yield vault specification (Build 05, part 1)

**Date:** 2026-08-08

**Context:** Documentation-only. No Solidity written or modified — the
existing `BitVVaultManager.sol` remains the Build-01.5-era compliance
stub it has always been (every function reverts `NotImplemented` after
a compliance check). This milestone designs what should replace it.

**Deliverable:** `docs/yield-vault-specification.md` — full specification
covering purpose, user flow, architecture, ERC-4626 decision, asset
model, strategy architecture, Cleanverse/CVI/CVA integration, share
accounting, fees, access control, emergency controls, risk controls,
pool relationship, BitV component integration, security model, test
plan, RWA extensibility, and open questions.

**Key decisions:**
- **ERC-4626** chosen as the accounting standard (OpenZeppelin's
  `ERC4626`), not a custom share system — gets audited inflation/rounding
  math for free; BitV-specific logic (compliance, limits, pause,
  strategy routing) layered on top via the standard's hooks.
- **CVI is the sole vault-eligibility layer** — BitScore is explicitly
  **not** made a dependency; the spec found no strong reason to
  integrate it (BitScore is scoped to lending risk, and a yield vault
  has no borrowing/credit-risk dimension for it to price).
- **Share transfers disabled entirely for the MVP** — rather than
  gating `transfer`/`transferFrom` behind a second compliance
  checkpoint, the transfer path is removed altogether, structurally
  closing the "verified depositor transfers shares to an unverified
  wallet" bypass the task flagged.
- **Vault liquidity kept completely separate from lending pools** for
  the MVP (option A of two evaluated) — avoids coupling an
  already-validated lending engine's liquidity/withdrawal behavior to
  a new, unproven vault/strategy system. Pool-as-strategy (option B)
  is left as a possible future direction requiring its own
  integration-invariant test suite.
- **CVA integration**: evaluated for deposits/assets/yield/withdrawals;
  not confirmed for any of them on the current deployment target — no
  vault should be documented as "CVA-backed" until Cleanverse confirms
  a specific token's CVA registration.
- **Roles**: exactly two new roles added to the plan —
  `VAULT_MANAGER_ROLE`, `STRATEGY_MANAGER_ROLE` — reusing
  `PROTOCOL_ADMIN_ROLE`/`PAUSER_ROLE` where sufficient, per "do not
  create unnecessary roles."
- **Fees**: performance-fee-only for the MVP (capped, `RISK_MANAGER_ROLE`-
  gated, flows to `BitVTreasury`); no management or withdrawal fee —
  no demonstrated need for either yet.
- **Withdrawal pause handled carefully**: normal withdrawal can be
  paused if the strategy is failing, but a separate, always-available
  emergency-withdrawal path (pro-rata share of whatever the vault can
  actually account for) is never blocked by that pause — users cannot
  be permanently locked out of funds by a strategy failure.
- **Test strategy vs. production strategy** explicitly distinguished —
  the MVP's placeholder strategy is documented as generating no real
  yield; a real strategy is out of scope pending its own review.

**Not done (per instruction):** no Solidity written, no contracts
modified, nothing deployed. `BitVVaultManager.sol` is untouched.

**Next recommended milestone:** implement `BitVYieldVault`/
`IBitVVaultStrategy`/`TestYieldStrategy` per this specification, wire
the two new roles into `BitVAccessManager`, and build the Foundry test
suite per §19 of the specification.

---

## Milestone 4.2 — BitScore scale reconciliation (0–1000 → 0–100, Solidity)

**Date:** 2026-08-08

**Context:** Milestone 4.1 rescaled `docs/bitscore-specification.md` to
0–100 but explicitly left the deployed `BitScoreManager.sol` on the
original 0–1000 scale, creating a known spec-vs-implementation
disagreement. This milestone reconciles them: the contracts now
implement the approved 0–100 model exactly, and no production Solidity
in the repository uses the old scale.

**Contracts modified:**
- `contracts/src/interfaces/IBitScoreManager.sol` — `getScore` return
  type changed `uint16` → `uint8`.
- `contracts/src/core/BitScoreManager.sol` — fully rewritten to the
  0–100 scale: `MIN_SCORE = 0`, `MAX_SCORE = 100`, tier floors
  `25/50/75` (Restricted 0–24, Standard 25–49, Established 50–74,
  Trusted 75–100); `Params.startScore = 30`; contribution point deltas
  redesigned to fit the approved caps (repayment +3, timeliness +1 —
  together capping under the spec's +35 repayment-and-timeliness
  allowance well before the overall +70 max positive contribution is
  reached; tenure +1/period up to a +5 cap; low-utilization bonus +1);
  liquidation penalties `-10` full / `-5` partial; bad debt `-30`,
  permanent. `ScoreState.positiveContribution` and `.tenureCredited`
  narrowed to `uint8` (sufficient for the 0–70 cap); `liquidationPenalty`
  and `badDebtPenalty` deliberately kept `uint16` (unbounded downward
  accumulators — narrowing to `uint8` would risk silent overflow across
  repeated liquidations/bad debts even though the final clamped score
  can never go below 0). No fixed-point/decipoint representation was
  introduced — the approved 0–100 caps and penalties are whole numbers,
  so plain integers are simpler and equally exact.

**Formula, unchanged in shape:** `score = clamp(30 + capped positive
contributions − decayed liquidation penalties − permanent bad-debt
penalties, 0, 100)` — same "decay-then-add" accumulator architecture as
Build 04, only the scale-dependent constants changed.

**Tests updated:** `contracts/test/unit/BitScoreManager.t.sol` (21
tests) and `contracts/test/invariant/BitVInvariant.t.sol`'s BitScore
invariants — every hardcoded 300/700/1000-scale literal replaced with
its 0–100 equivalent (30/70/100). `_repayUntilTier`'s iteration budgets
were recalibrated empirically (via a temporary `console2.log` debug
trace, not kept) for the new per-event point deltas: at the test
fixture's cadence, Tier 2 is reached around iteration 6 and Tier 3
around iteration 14, and the positive accumulator now reaches its
nominal +70 cap directly (score saturates at 100) within roughly two
dozen events, rather than merely approaching an equilibrium below the
cap as the old 0–1000/700-point design did — reflected in updated test
comments and assertions.

**Verification — repo-wide sweep for `1000`/`300`/`0–1000`/`0-1000`:**
searched the entire repository. Every remaining occurrence outside test
literals (now fixed) is either (a) historical documentation explaining
the migration (`docs/bitscore-specification.md`'s and
`docs/development-log.md`'s own prior-milestone entries, both
deliberately preserved as history), or (b) explanatory comments in
`BitScoreManager.sol`/`IBitScoreManager.sol` that name the old scale
only to contrast it with the current one (no numeric `1000`/`300`
constant is actually used in any computation). No production BitScore
logic remains on the old scale. `docs/bitscore-implementation.md` was
rewritten to describe the new 0–100 implementation (its prior "still
0-1000" status banner removed).

**Full Foundry suite — actually executed, all suites, not just
BitScore:** `forge test` (after `forge build` confirmed a clean
compile). Result: **6 suites, 71 tests, 71 passed, 0 failed, 0
skipped** — `BitVComplianceGuard.t.sol` (11), `BitVLendingManager.t.sol`
(12), `BitVPoolManager.t.sol` (12), `BitScoreManager.t.sol` (21),
`BitVLiquidation.t.sol` (7), and `BitVInvariant.t.sol` (8 invariants,
256 runs / 128,000 calls each, 0 reverts). The pre-existing
non-BitScore suites (compliance/pool/lending/liquidation) pass
unchanged, confirming the rescale did not regress the lending engine.

**Not done:** no architecture change beyond the scale itself (same
accumulator design, same triple-clamped LTV integration, same
quoted-only interest adjustment, same fail-safe try/catch pattern) — per
instruction, this was a scale reconciliation, not a redesign.

---

## Milestone 4.1 — BitScore specification rescale to 0–100 (docs only)

**Date:** 2026-08-08

**Context:** Documentation-only update. No Solidity touched, no
contracts modified — the deployed `BitScoreManager.sol` still runs on
the original 0–1000 scale from Build 04.

**Change:** `docs/bitscore-specification.md` rescaled from 0–1000 to
0–100 throughout: starting score 300→30, tiers 250/500/750-point bands
→ 25/50/75-point bands (Restricted 0–24, Standard 25–49, Established
50–74, Trusted 75–100, as specified), max positive contribution 700→70,
per-input caps 350/150/50→35/15/5, every per-event point delta
rescaled by the same 1/10 factor (several becoming fractional — e.g.
+5→+0.5 for a full-close repayment — with a note that the follow-up
Solidity milestone should represent these via fixed-point internal
accounting to preserve exact relative weighting rather than losing
precision to integer rounding), and the storage sketch's `score` field
narrowed from `uint16` to `uint8` (0–100 fits comfortably). Formula
mechanically unchanged: `30 + capped positive contributions - decayed
liquidation penalties - permanent bad-debt penalties`, clamped
`[0, 100]` — same shape as before, only the constants changed.

**Explicitly unchanged**: every underlying architecture decision and
scoring principle — the single consolidated decaying
positive-contribution accumulator, the separately-decaying liquidation
penalty, the permanent (never-decaying) bad-debt penalty, the CVI/
BitScore separation, the fully-on-chain event-driven update model, the
anti-gaming caps structure, the privacy model, the fail-safe behavior,
and the interest-rate-quoted-only resolution. Section 7's LTV
percentage-point adjustments and interest-rate-discount values are
independent of the score scale and were left as-is.

**`docs/bitscore-implementation.md`** got a status banner flagging that
it still describes the pre-rescale (0–1000) deployed contracts, so a
reader doesn't mistake its numbers for the current specification target.

**Not done (per instruction):** no Solidity written, no contracts
modified. The deployed `BitScoreManager.sol` and the current
specification now disagree on scale until a follow-up implementation
milestone reconciles them.

**Next recommended milestone:** implement the 0–100 rescale in
`BitScoreManager.sol` (and update `docs/bitscore-implementation.md` to
match), most likely introducing an internal fixed-point representation
for the fractional point deltas this rescale introduced.

---

## Milestone 4 — BitScore implementation and validation (Build 04, part 2)

**Date:** 2026-08-08

**Context:** Implements `docs/bitscore-specification.md` (approved
design from the first half of Build 04). Cleanverse interfaces
untouched. Core lending economics touched only where necessary for the
approved integration (see below).

**Contracts created:** `BitScoreManager.sol` (accumulator, tier
calculation, LTV-adjustment computation, quoted rate-discount
computation, admin/record functions), `IBitScoreManager.sol`.

**Contracts modified:**
- `DataTypes.sol` — added `Pool.maxLtvWithScoreBps` (BitScore's LTV
  ceiling per asset) and `AccountData.weightedMaxLtvValue`.
- `BitVPoolManager.sol` — `PoolConfigParams`/`createPool`/
  `setRiskParams`/`_validateRiskParams` extended for the new ceiling
  field, validated to sit between `ltvBps` and `liquidationThresholdBps`.
- `BitVLendingManager.sol` — wired `IBitScoreManager` in (optional,
  `address(0)`-disableable), added `_effectiveAvailableBorrowValue`
  (the real LTV integration point, triple-clamped — see
  `docs/bitscore-implementation.md`), `_recordRepayment`/
  `_recordLiquidation`/`_recordUtilizationSnapshot` (try/catch-wrapped,
  fail-safe), `getEffectiveAvailableBorrowValue`/
  `getQuotedBaseRateDiscountRay` views. **Fixed a real pre-existing bug**
  in `repay()`: full-close detection via scaled-balance comparison was
  unreliable (rounding), routinely leaving 1 wei of dust debt and never
  triggering BitScore's `wasFullClose` signal; fixed with an exact
  underlying-amount comparison plus a new `type(uint256).max` repay-all
  sentinel (mirroring `withdraw()`'s existing pattern).

**Score model implemented:** 0–1000, start 300, four tiers exactly as
specified. Single consolidated decaying `positiveContribution`
accumulator (documented deviation from the spec's per-category-window
sketch — point values/cap preserved), separate slower-decaying
liquidation penalty, permanent bad-debt penalty. Decay-then-add pattern,
O(1) per update, no history replay.

**Lending integration:** LTV adjustment is real (wired into `borrow()`'s
actual capacity check, triple-clamped so a `BitScoreManager` bug
provably cannot exceed the asset's configured ceiling). Interest rate
adjustment is quoted/informational only — `BitVPoolManager`'s shared
borrow index makes a genuine per-user rate incompatible with this
milestone's scope; documented as the one real spec-vs-implementation
contradiction found, resolved rather than forced or hidden.

**Compliance ordering:** unchanged — `_requireCompliance` always runs
first in every protected `BitVLendingManager` function; `BitScoreManager`
has no reference to, and never calls, `IAPassComplianceValidator`.

**Anti-gaming:** per-input caps (single consolidated cap, 700 points),
minimum 1-day position duration before repayment credit (zero credit
below it, not partial), no credit for pool deposit/withdraw cycles
(BitScore only hooks lending-side events), decay windows, wallet
tenure only accrues alongside real lending activity. Wash-borrowing
explicitly still unresolved, restated rather than silently dropped.

**Fail-safe:** every BitScore call site in `BitVLendingManager` is
`try`/`catch`-wrapped; failure/disablement always falls back to base
parameters, never something more favorable — proven directly by a new
fuzzed invariant (`invariant_BitScoreFailureNeverMoreFavorableThanBase`),
not just asserted in a scenario test.

**Tests created:** `BitScoreManager.t.sol` (21 tests, covering all 20
scenarios the milestone listed plus one extra), 5 new BitScore-specific
fuzzed invariants added to `BitVInvariant.t.sol` (score ≤ 1000, score ≥
0, unauthorized caller cannot increase score, LTV adjustment cannot
exceed the configured ceiling, BitScore failure never more favorable
than base) alongside the 3 already-existing pool/lending/compliance
invariants.

**Foundry test result:** `forge test -vvv` — **71/71 PASS** across 6
suites (11 compliance + 12 pool + 12 lending + 7 liquidation + 21
BitScore + 8 invariant, the last including all 3 pre-existing plus 5 new
BitScore invariants). Two rounds of real failures found and fixed during
this milestone, not weakened or deleted:
1. A `vm.prank` scope bug in a new access-control test (same class as
   Build 03.5's — a role-hash lookup between `prank` and the call
   consumed the prank).
2. The `repay()` full-close precision bug described above, discovered
   via a debug trace (`console2.log`, not kept) after several test
   iteration-count miscalibrations turned out to be secondary to this
   root cause. Several test loop iteration counts were also increased
   after confirming (via the same debug trace) that decay-tempered score
   growth per event was slower than initially assumed — a test-
   calibration fix, not a contract change.

**Invariant result:** 8/8 PASS (256 runs × 500 calls each, 3
pre-existing + 5 new).

**Remaining limitations:** interest-rate quoted-only (not a real
per-user discount), decay-tempered score growth converges below the
nominal 1000 cap at realistic event cadences (the cap itself is never
violated — proven, not just claimed), wash-borrowing unresolved,
single protocol-wide (not per-asset) score, no negative utilization
penalty path, tenure only accrues via lending activity (supply-only
users get no differentiation). Full detail in
`docs/bitscore-implementation.md`.

**Not implemented (per instruction):** yield vaults, RWA markets,
governance, cross-chain functionality, production deployment.

---

## Milestone 3.5 — Economic engine validation (Build 03.5)

**Date:** 2026-08-08

**Context:** First milestone with Foundry actually available. Got
`forge 1.0.0` installed in this sandbox via `raw.githubusercontent.com`
(reachable, unlike `foundry.paradigm.xyz`, `api.github.com`, and
`binaries.soliditylang.org`, all still blocked) — foundryup's install
script and raw solc-bin release binaries are both served from that
domain. `solc 0.8.24` was placed manually into `~/.svm/0.8.24/` since
`svm`'s own downloader hits the blocked `binaries.soliditylang.org`.
Full detail, including the exact commands, in
`docs/economic-engine-review.md`.

**Foundry: AVAILABLE.**

**Compilation: PASS**, after one real fix — `BitVPoolManager.accrueInterest`
hit solc's "stack too deep" codegen limit under the legacy pipeline;
fixed by enabling `via_ir = true` in `foundry.toml` (the standard fix,
not a function rewrite). `solc` also pinned to `0.8.24` explicitly in
`foundry.toml` to match every contract's pragma and avoid re-triggering
an auto-selected-newer-version download.

**Full `forge test -vvv` and all four requested `--match-contract`
filters run.** Two real test-logic bugs found and fixed (both were
`vm.prank` scope bugs — a role-hash lookup between `vm.prank` and the
actual call consumed the prank — not contract bugs); after the fix, all
**45 tests across 5 suites pass**: `BitVComplianceGuardTest` (11),
`BitVPoolManagerTest` (12), `BitVLendingManagerTest` (12, incl. 2 new
regression tests below), `BitVLiquidationTest` (7), and a new
`BitVInvariantTest` (3, see Task 6).

**Economic/security review (Tasks 4-5) found two real issues, both
fixed with regression tests, not just documented:**

1. `BitVLendingManager.depositCollateral` didn't check pool pause state
   at all — pausing a collateral pool via `BitVPoolManager.setPoolPaused`
   didn't actually stop new collateral deposits into it. Fixed.
   `withdrawCollateral` deliberately left unpaused-by-design (users
   should always be able to exit).
2. A zero-priced asset (oracle explicitly set to price `0`, distinct
   from no oracle configured at all) was silently valued at `$0`
   instead of reverting — could mask real debt or wipe out real
   collateral in a health-factor calculation with no signal anything
   was wrong. Fixed with a new `ZeroPrice` error, split into a
   reverting `_valueOf` (for the specific asset an action directly
   touches) and a non-reverting `_tryValueOf` (for `_accountData`'s
   aggregation loops, so one misconfigured asset can't deny-of-service
   every action for every user holding it) — the split itself has a
   documented residual risk (a zero-priced *debt* asset now drops out
   of `totalDebtValue`, understating risk, rather than the safer-but-
   DoS-prone alternative of reverting) — see
   `docs/economic-engine-review.md`.

**No other contract-logic bugs found.** Full review notes (rounding
symmetry as a non-blocking limitation, insolvent-liquidation and
multi-asset cross-margin paths implemented-but-untested, no
stale-price protection, decimal-mismatch handling reviewed but not
exercised beyond 18/18) are in `docs/economic-engine-review.md` — not
repeated here in full.

**Invariants (Task 6):** new `contracts/test/invariant/Handler.sol` +
`BitVInvariant.t.sol`. Three fuzzed invariants, all passing at 256
runs × 500 calls: borrowed liquidity never exceeds supplied,
`availableLiquidity + totalBorrowed >= totalSupplied` always, and a
never-compliant wallet stays rejected regardless of accumulated fuzzed
state. Several invariants named in the brief were deliberately left as
scenario tests instead of fuzzed ones, with reasoning documented in
`docs/economic-engine-review.md` rather than silently skipped.

**Explicitly not claimed:** BitV is not production-ready, the
contracts are not audited, Cleanverse is not confirmed deployed on
Monad (unchanged from Build 02.6), and passing tests are not treated as
proof the protocol is secure.

**Not started (per instruction):** BitScore, yield vaults, RWA markets,
any new protocol feature, any deployment.

**Next recommended milestone:** address the documented residual risks
if/when a subsequent milestone actually needs them fixed (rounding
direction hardening, insolvent-liquidation test coverage, multi-asset
cross-margin test coverage) — none required this milestone, since it
was scoped to validation, not feature work. Separately: BitScore design
or continuing to chase Cleanverse's deployment information, neither
started here.

---

## Milestone 3 — Core pool and lending architecture (Build 03)

**Date:** 2026-08-08

**Context:** First economic-logic milestone. Cleanverse's compliance
*architecture* (Build 02.x) is treated as fixed/confirmed and was not
modified except where required to add pool/lending economics on top of
it — `IAPassComplianceValidator` and `BitVComplianceGuard` are unchanged.
Per this milestone's explicit constraint, the validator address stays
deployment-time configuration (never hardcoded), and nothing was deployed
anywhere.

**Contracts created:**

- `contracts/src/libraries/WadRayMath.sol`, `PercentageMath.sol` — ray
  and bps fixed-point math.
- `contracts/src/libraries/DataTypes.sol` — `Pool` and `AccountData`
  structs.
- `contracts/src/libraries/ProtocolErrors.sol` — protocol-level custom
  errors, kept separate from `ComplianceErrors` (Cleanverse-specific).
- `contracts/src/interfaces/IPriceOracle.sol`, `IInterestRateModel.sol`
  — clean, swappable boundaries.
- `contracts/src/oracles/StaticPriceOracle.sol` — admin-set price
  source, explicitly documented as non-production.
- `contracts/src/oracles/KinkedInterestRateModel.sol` — two-slope
  interest model with a documented (not deployed) suggested starting
  parameter set.
- `contracts/src/access/BitVRoleConsumer.sol` — shared `onlyRole`
  modifier checking a central `BitVAccessManager`, kept deliberately
  separate from `BitVComplianceGuard`'s Cleanverse-specific `Ownable`.
- `contracts/script/Deploy.s.sol` — deployment-configuration template
  (not executed) requiring `CLEANVERSE_VALIDATOR_ADDRESS` as an env var
  with no fallback.

**Contracts modified:**

- `BitVAccessManager` — replaced `GOVERNANCE_ROLE`/`PAUSER_ROLE` with
  four roles: `PROTOCOL_ADMIN_ROLE`, `RISK_MANAGER_ROLE`,
  `POOL_MANAGER_ROLE`, `PAUSER_ROLE`.
- `BitVTreasury` — switched from its own standalone `AccessControl` to
  `BitVRoleConsumer` (shared roles), added `receiveFee` and kept
  role-gated `withdraw`.
- `BitVPoolManager` — full rewrite from Build 02's compliance-only stub:
  real pool creation/config, ray-scaled supply accounting, `deposit`/
  `withdraw` (with the exact-scaled-balance max-withdraw fix applied
  from the start), `borrowFromPool`/`repayToPool` restricted to a
  single registered `lendingManager`, linear interest accrual with
  reserve-factor-to-treasury routing, full view surface (`totalSupplied`,
  `availableLiquidity`, `totalBorrowed`, `utilizationRay`, etc.).
- `BitVLendingManager` — full rewrite: cross-margin collateral/debt
  accounting via `EnumerableSet`, `depositCollateral`/
  `withdrawCollateral` (health-factor-gated), `borrow` (LTV-gated),
  `repay`, `liquidate` (close-factor-capped partial liquidation,
  liquidation bonus, insolvency-capped seizure), `getUserAccountData`/
  `getHealthFactor` views.

**Not modified (per instruction, unless docs proved them wrong — they
didn't):** `IAPassComplianceValidator.sol`, `BitVComplianceGuard.sol`,
`BitScoreManager.sol`, `BitVVaultManager.sol`.

**Pool architecture:** one `BitVPoolManager` contract, one pool per
asset, ray-scaled real on-chain balances (no off-chain/synthetic
accounting anywhere) — see `docs/protocol-architecture.md` for full
detail.

**Lending architecture:** cross-margin (multi-collateral,
multi-borrowed-asset per user), debt tracked in `BitVLendingManager`
using the same borrow index `BitVPoolManager` maintains per pool.

**Collateral model:** any pool flagged `isCollateralEnabled` can back a
loan; value computed via each asset's configured `IPriceOracle`, weighted
by per-asset `ltvBps`/`liquidationThresholdBps`.

**Interest model:** `KinkedInterestRateModel`, base rate + two-slope
utilization component, explicitly separated per the requirement; linear
(not continuously compounded) accrual, documented as a deliberate
determinism/auditability tradeoff.

**Liquidation model:** health-factor threshold at `1 ray`;
`closeFactorBps` (default 50%) caps a single liquidation call;
liquidation bonus computed via oracle prices; insolvent positions handled
by capping seizure at available collateral and scaling the repay down
proportionally (documented bad-debt tradeoff, not hidden).

**Compliance integration point:** unchanged mechanism
(`BitVComplianceGuard._requireCompliance`), now called at the start of
every pool/lending protected action, including the liquidator (not the
liquidated user) in `liquidate`.

**Security controls:** `ReentrancyGuard` on every state-changing
function, checks-effects-interactions ordering, role-gated admin
functions, index-based (not `balanceOf`-based) supply accounting to
avoid donation attacks, exact-scaled max-withdraw (avoiding the earlier
dust bug's return), documented (not hidden) insolvency/bad-debt handling,
a clean swappable oracle interface with no production price source
assumed. Full detail and rationale in `docs/protocol-architecture.md`'s
Security Assumptions section.

**Tests created:** `BitVComplianceGuard.t.sol` (reworked to use a new
`ComplianceGuardHarness` instead of the now-real `BitVPoolManager`),
`BitVPoolManager.t.sol` (deposit, withdraw incl. max-withdraw exactness,
pool accounting, pause/unpause, compliance accept/reject, unauthorized
admin action rejection, a real reentrancy attack via
`MockReentrantERC20`), `BitVLendingManager.t.sol` (collateral deposit/
withdraw incl. health-factor-breach rejection, borrow incl. LTV-breach
rejection, repay incl. overpay capping, interest accrual, compliance
rejection), `BitVLiquidation.t.sol` (healthy position cannot be
liquidated, unhealthy position can be, partial liquidation respects
close factor, liquidation bonus amount verified exactly, debt reduction
verified exactly, no-outstanding-debt rejection, repeated liquidation on
a still-unhealthy position). New shared fixture `BaseProtocolTest.sol`
and mocks `MockERC20.sol`, `MockReentrantERC20.sol`.

**COMPILED:** yes — every contract, script, and test file compiles clean
via `solc@0.8.24` (Foundry still unavailable in this sandbox; direct
release-asset download and `api.github.com` access were both attempted
this milestone and both blocked — `api.github.com` specifically returns
this session's GitHub-scoping error, not a generic network block, and a
guessed release-asset filename 404'd rather than resolving, so the exact
correct asset name would need to be sourced through GitHub's normal web
UI, not scriptable from here). Only pre-existing, expected
`state mutability can be restricted to view` warnings on
`BitVVaultManager`'s and the compliance harness's still-unimplemented
stub functions.

**TESTS EXECUTED: NOT EXECUTED.** `forge test` has not been run — solc
compilation is not a substitute and is not reported as such. All test
assertions above describe what the test *code* checks, not confirmed
pass/fail outcomes.

**Remaining Cleanverse deployment blockers (unchanged from Build 02.6):**
validator's deployed address (any network), explicit Monad Testnet
support, chain ID, validator-registration signing algorithm, CVI
issuance/verification APIs — see `docs/cleanverse-integration.md`'s
"Deployment Readiness" section.

**Next recommended milestone:** get Foundry running somewhere to
actually execute the full test suite (this milestone's tests plus
Build 02's compliance tests) and get real pass/fail results before
trusting any of this economically. Separately and independently: BitScore
design (now that risk-parameter plumbing exists to eventually feed from
it), yield vaults, or continuing to chase Cleanverse's deployment
information — none of which this milestone started, per its scope.

---

## Milestone 2.6 — Cleanverse deployment readiness audit (Build 02.6)

**Date:** 2026-08-08

**Context:** Final pre-deployment audit, opened alongside PR #2 (which
bundles Build 01's foundation rebuild and Build 02.x's compliance
architecture into one PR against `main`). No new source material this
milestone — a targeted re-search of the same two PDFs (CVI Integration
Guide V2, CVA Integration Guide) for Monad-specific and deployment-
specific terms, per this milestone's explicit instruction not to infer
addresses from unrelated sources.

**Search performed:** the strings `Monad`, `Monad Testnet`, `validator
address`, `IAPassComplianceValidator deployment`, `CVA deployment`, `CVA
address`, and `chain ID` were searched for across both PDFs.

**Result: no matches for "Monad" in either document.** No chain ID, no
validator address, no CVA address appears anywhere in either document,
for any network. This is a negative result, not a gap in the search —
both documents were read in full in Build 02.1 and are short enough
(11–14 pages each) that this is a complete search, not a sampling.

**Validator registration re-confirmed exactly as Build 02.5 left it:**
`POST /api/cooperate/validator/register`, signature rule
`keccak256(chain + contract_address)` (lowercase hex concatenation) —
and nothing else. No headers, request field names, response shape, or
error handling are specified. No claim of EIP-191/`personal_sign` was
reintroduced for this endpoint (that error was corrected in Build 02.5
and stays corrected).

**CVI issuance/verification/status-lookup/expiration/revocation APIs:**
confirmed absent from both documents — restated as explicitly
`UNCONFIRMED`, not silently dropped from the todo list.

**Documentation changes:** `docs/cleanverse-integration.md` gained a
"Deployment Readiness" section (Confirmed / Unconfirmed / Required
before deployment) directly answering this milestone's checklist.
`docs/cleanverse-integration-todo.md` got a "Build 02.6 deployment-
readiness re-search" addendum confirming the negative search result and
adding one new explicit item: whether Cleanverse supports Monad Testnet
*at all* is unconfirmed, not just the address on it.

**No Solidity or TypeScript changes this milestone** — per instruction,
the compliance interface is not modified unless documentation proves it
wrong, and this audit found no such proof (it found more absence of
information, not new information).

**Foundry:** re-confirmed unavailable (`which forge` → exit 1; `curl` to
`foundry.paradigm.xyz` → `403`). `forge test` still **NOT EXECUTED**.

**Bottom line:** BitV's Cleanverse compliance *architecture* is verified
against real primary documentation and internally consistent. BitV's
Cleanverse *deployment* is blocked — the validator's address, and even
confirmation that Monad Testnet is a supported network, must come from
Cleanverse directly; neither exists in the documentation provided so far.
Per instruction, economic contract implementation does not proceed until
this is resolved.

---

## Milestone 2.5 — Cleanverse interface verification audit (Build 02.5)

**Date:** 2026-08-08

**Context:** Line-by-line re-audit of the entire Cleanverse compliance
implementation against the same two official PDFs used in Build 02.1
(CVI Integration Guide V2, CVA Integration Guide) — no new source
material this milestone, just a rigorous re-check of every claim already
made, since a prior implementation had been provisional and this task
explicitly asked not to preserve any assumption just because it already
existed in the code.

**Previous assumptions checked:**

- `IAPassComplianceValidator`'s every function name, parameter, type, and
  return value (Build 02.1's version).
- `RuleV2`'s field names/types/semantics (Build 02.1's version).
- `complianceVerify`'s behavior and preconditions.
- Single-Contract Mode's required contract state.
- The CVA mechanism and its relationship to the CVI validator.
- The validator/CVA registration API flows, including authentication.
- Whether Monad Testnet is explicitly named as supported.

**Verified correct (no change needed):** the full `IAPassComplianceValidator`
interface (all 10 functions, exact names/params/types/visibility — no
events, errors, or modifiers exist in the source, and none were invented
here either), `RuleV2`'s fields and AND/OR/bitwise-AND semantics,
`complianceVerify`'s signature and "view, returns bool, no revert on its
own" behavior, Single-Contract Mode's `immutable` validator + `Ownable`
rule-management pattern, and the CVI-validator-vs-CVA-interface
distinction (§3 of `docs/cleanverse-integration.md`).

**Found incorrect and corrected:** `docs/cleanverse-integration.md`
previously claimed the CVI validator's registration signature scheme
(`POST /api/cooperate/validator/register`, CVI guide §5.4: "Signature
Rule: `keccak256(chain + contract_address)`, lowercase hex
concatenation") was "the same" as the CVA guide's `owner_signature`
field ("EIP-191 `personal_sign` signature over `lowercase(chain +
atoken_address)`"). The CVI guide never says `personal_sign`, never
names a request field, and never states what's actually signed with that
hash — that equivalence was an unstated inference dressed up as
confirmed fact. Corrected across §4/§5/§10/the new Verification Table:
the two schemes are now documented separately, and the validator's exact
registration signing mechanism is marked `UNCONFIRMED`. This was a
documentation-only error — no Solidity code depended on the wrong claim,
since no API client was implemented against it.

**No Solidity changes were needed this milestone** — the audit found the
contracts (`IAPassComplianceValidator.sol`, `BitVComplianceGuard.sol`,
the six `contracts/src/core/*.sol` contracts, the mock, and the test
file) already matched the source PDFs after Build 02.1's corrections.
One stale TS comment was fixed: `services/cleanverse/client.ts` referred
to the interface as still needing verification against primary
documentation, which is now done — only the deployed address remains
unconfirmed.

**`docs/cleanverse-integration.md`** gained a "Verification Table"
(Cleanverse Component | Official Definition | BitV Usage | Verified) at
the top, and §7's blockchain table was split out to explicitly flag
"explicit Monad Testnet support," "chain ID," and "CVA contract
addresses" as their own `UNCONFIRMED` rows rather than folding the Monad
caveat into prose.

**Tests:** Not modified this milestone (already correct from Build
02.1). **NOT EXECUTED** — Foundry (`forge`) remains unavailable in this
sandbox (`which forge` → exit 1; same network block on its installer as
every prior milestone). Every contract and the test file were re-verified
to compile clean via `solc@0.8.24` directly — this is a compilation
check only, not a substitute for `forge test`'s cheatcode-driven
execution, and is not reported as a test pass.

**Remaining unknowns** (unchanged from Build 02.1's todo list, restated
here per this milestone's instructions): CVI issuance/verification flow,
CVI expiration/revocation, off-chain identity-status lookup API,
validator's deployed address (any network), full paths for Query Apply
Status / Query Supported CVA List / Add CVA Rule APIs, API key/`api-id`
provisioning process, AES key-management detail for the Launch CVA API,
validator/CVA events, pause/freeze function signatures, and — newly
tightened this milestone — the validator-registration signing algorithm
and explicit Monad Testnet support/chain ID.

**Not done (per instructions):** no new features, no lending/liquidity
economics, no BitScore, no contract deployment, no Factory Mode
implementation, no API client implementation.

---

## Milestone 2.1 — Cleanverse compliance foundation, corrected against real docs (Build 02.1)

**Date:** 2026-08-08

**Context:** The user provided the two official Cleanverse PDFs directly
("CVI Integration Guide V2" and "CVA Integration Guide") — the first real
primary-source access this project has had, after multiple sessions where
`docs.cleanverse.com` was network-blocked. This let Build 02's
implementation be checked against ground truth, and it was wrong in one
concrete way: `RuleV2`'s field types.

**Corrections made:**

- `contracts/src/interfaces/external/IAPassComplianceValidator.sol` —
  `RuleV2` field types fixed from an all-`uint256` guess to the confirmed
  `bytes2 allowedGroup, bytes2 allowedSubGroup, uint8 minTier, uint8
  minSubTier, uint256 poolCountryBitmap`. Added the full confirmed
  interface: `registerV2`, `registerApass` (2 overloads),
  `setRuleV2FromRegistrar`, `isRegistered` (registration side,
  `REGISTER_ROLE`), and `setRuleV2FromContract` / `addRuleV2FromContract`
  / `removeRuleV2FromContract` / `getRulesV2` (business-contract side) —
  none of which existed in Build 02's interface, which only declared
  `complianceVerify`.
- `contracts/src/compliance/BitVComplianceGuard.sol` — now inherits
  `Ownable` (per the guide's Single-Contract-Mode template) and exposes
  the four rule-management functions as `onlyOwner`-gated wrappers, per
  the guide's explicit instruction to gate them with `onlyOwner` or
  `AccessControl`. Constructor now takes `(validator, owner)`.
- `BitVPoolManager` / `BitVLendingManager` / `BitVVaultManager`
  constructors updated to pass an owner through.
- `contracts/test/mocks/MockComplianceValidator.sol` and
  `contracts/test/unit/BitVComplianceGuard.t.sol` — reworked for the
  corrected field types (`bytes2` group/sub-group test constants, `uint8`
  tiers) and corrected "no restriction" semantics (empty/zero fields on a
  `RuleV2` mean unrestricted, not "must equal zero" — Build 02's mock had
  exact-match-only comparisons). Added a test for the new owner-gated
  rule-management wrappers.
- `services/cleanverse/types.ts` — `RuleV2` TS mirror field types
  corrected to match (`0x${string}` for the two `bytes2` fields, `number`
  for the `uint8` fields, `bigint` for the bitmap).
- `docs/cleanverse-integration.md` — substantially rewritten from the
  actual PDF content: full confirmed API endpoint table (§5), the
  distinction between the CVI validator and the separate CVA
  `IComplianceRule`/`IATokenPolicy` interface (§3), Single-Contract Mode
  vs. Factory Mode with the guide's own verbatim comparison table (§12),
  and the confirmed authentication schemes (§4). `docs/cleanverse-
  integration-todo.md` rewritten to list only what's genuinely still
  unconfirmed (9 items — CVI issuance flow, validator's deployed address,
  a few unnamed endpoint paths, etc.), not everything.

**Verification:**

- Every contract, the mock, and the test file re-verified to compile
  clean via `solc@0.8.24` (Foundry still not installed/available in this
  sandbox — same limitation as prior milestones; `forge test` still not
  executed).
- Frontend `npm run build` / `lint` / `typecheck` re-run after the
  `RuleV2` TS type change — all still **PASS**.

**Remaining before real deployment:** the 9 items in the rewritten
`docs/cleanverse-integration-todo.md` — most notably the validator's
actual deployed address on Monad Testnet (BitV cannot register a contract
or get a meaningful `complianceVerify` answer without it) and the CVI
issuance/verification flow (needed before any identity-status UI beyond
static placeholder states).

**Next recommended milestone:** get Foundry running somewhere to actually
execute `contracts/test/unit/BitVComplianceGuard.t.sol` against the
corrected interface; separately, if/when the validator's Monad Testnet
address becomes available, wire up `services/cleanverse/client.ts`'s
`checkCompliance` to actually read it via viem. Economic logic (pool
accounting, lending interest, vault strategies, BitScore) stays out of
scope until then.

---

## Milestone 2 — Cleanverse compliance foundation (BUILD 02)

**Date:** 2026-08-08

**Context:** Build 01.6 (Cleanverse documentation audit) could not proceed
— `docs.cleanverse.com` is hard-blocked by this sandbox's network egress
policy, confirmed on retry and via raw `curl`, even with the access code
provided (the block is at the network layer, before the docs site's own
auth would even apply). The user then supplied Build 02, which relays
specific interface details attributed to a "Cleanverse Compliance
Protocol Integration Guide V2" directly in the task text rather than as a
fetched document. Those relayed details (not independently verified
against a primary source) were implemented; everything not given was left
as `UNCONFIRMED` rather than guessed. Full sourcing caveat and spec in
`docs/cleanverse-integration.md`.

**Contracts created** (new `contracts/` Foundry workspace on this branch
— it didn't exist after the Build 01 clean-slate rebuild):

- `contracts/src/interfaces/external/IAPassComplianceValidator.sol` —
  `complianceVerify(address poolAddress, address userAddress) view returns (bool)`
  and the `RuleV2` struct (`allowedGroup`, `allowedSubGroup`, `minTier`,
  `minSubTier`, `poolCountryBitmap`). Field Solidity types are an
  engineering assumption (`uint256`), flagged in the file header.
- `contracts/src/libraries/ComplianceErrors.sol` — `ComplianceCheckFailed`,
  `ZeroValidatorAddress`, `NotImplemented`.
- `contracts/src/compliance/BitVComplianceGuard.sol` — abstract base:
  holds an `immutable` validator reference (no setter, rejects
  `address(0)`), exposes `_requireCompliance(user)`.
- `contracts/src/core/BitVAccessManager.sol` — OpenZeppelin
  `AccessControl`-based protocol admin roles (distinct from Cleanverse
  compliance).
- `contracts/src/core/BitVPoolManager.sol` — `addLiquidity`,
  `removeLiquidity`, `swap`: compliance-checked, then `NotImplemented`.
- `contracts/src/core/BitVLendingManager.sol` — `supply`, `borrow`,
  `repay`, `withdraw`, `liquidate`, `depositCollateral`,
  `withdrawCollateral` (RWA hooks folded into lending, no separate RWA
  contract — none was in the six-contract list): same pattern.
- `contracts/src/core/BitVVaultManager.sol` — `deposit`, `withdraw`,
  `claimRewards`: same pattern.
- `contracts/src/core/BitScoreManager.sol` — skeleton only, explicitly
  not gated by Cleanverse (BitScore is BitV-native, not a Cleanverse
  primitive) and not calculated yet.
- `contracts/src/core/BitVTreasury.sol` — `AccessControl`-gated skeleton,
  not compliance-gated (internal protocol contract, not in the
  pool/lending/vault/RWA hook list).
- `contracts/test/mocks/MockComplianceValidator.sol` — test-only, clearly
  labeled not-for-production `IAPassComplianceValidator` implementation.
- `contracts/test/unit/BitVComplianceGuard.t.sol` — the 9 required
  scenarios (verified pass, unverified reject, wrong group, wrong tier,
  country restriction, AND-within-rule, OR-across-rules, no-bypass,
  immutable/non-zero validator), plus one supporting test.
- `contracts/lib/openzeppelin-contracts` (pinned `v5.0.2`) and
  `contracts/lib/forge-std` added as git submodules; `foundry.toml` +
  `remappings.txt` added.

**Build/test result:** Foundry (`forge`) is not installed in this sandbox
and its installer host (`foundry.paradigm.xyz`) is network-blocked here —
same limitation as Build 01. As a substitute, every contract, the mock,
and the test file were compiled with `solc@0.8.24` directly (manual
import resolution against the submodule paths): **compiles clean**, only
expected `state mutability can be restricted to view` warnings on the
stub functions (correct — they'll need to be non-`view` once real state
changes are implemented). **Test execution was not run** — solc only
checks compilation, not `forge test`'s VM cheatcodes (`vm.prank`,
`vm.expectRevert`, etc.) used in the test file. Run
`forge test --match-contract BitVComplianceGuardTest -vvv` in an
environment with Foundry installed to get an actual pass/fail result.

**Frontend changes:**

- `services/cleanverse/types.ts` — added `RuleV2` (TS mirror of the
  on-chain struct, same type-assumption caveat) and `ComplianceStatus`
  (BitV's own UI status union: `loading | verification-required |
  eligible | ineligible | error`, explicitly not a Cleanverse type).
- `services/cleanverse/client.ts` — added `checkCompliance` as a
  still-throwing stub (no on-chain call wired up yet).
- `components/compliance/ComplianceStatusBadge.tsx` — presentational
  only; renders whatever `ComplianceStatus` it's given, produces none of
  its own data.
- `config/cleanverse.ts` — new config boundary: validator address (from
  `NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS`, left empty — no guessed
  address), network, and private API config references.
- `app/globals.css` / `tailwind.config.ts` — added a `destructive` color
  token (light/dark) since the compliance status states needed an
  error/ineligible color that didn't exist yet.
- `.env.example` — added `NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS`
  (public — it's a contract address, not a secret) under Blockchain
  configuration, left empty.

**Frontend verification:** `npm run build`, `npm run lint`,
`npm run typecheck` all re-run after these changes — all still **PASS**,
no regressions from Build 01.5.

**Documentation:** `docs/cleanverse-integration.md` created (full spec,
sourcing caveats, and the Single-Contract-Mode-vs-Factory-Mode
rationale). `docs/cleanverse-integration-todo.md` updated with the Build
02 status rather than replaced (prior egress-block findings still hold).

**Remaining before real deployment:** `RuleV2` field types, any
rule-management functions on the real validator, the validator's deployed
address on Monad Testnet, CVA's actual mechanics, and the entire
off-chain API/SDK/auth/webhook surface — all `UNCONFIRMED`, none guessed.

**Next recommended milestone:** Resolve the `UNCONFIRMED` list above via
real documentation access (pasted content is the only channel that's
worked so far), then (a) confirm/adjust `RuleV2` field types and any
missing validator functions, (b) get Foundry running somewhere to
actually execute `contracts/test/unit/BitVComplianceGuard.t.sol`, and (c)
only then move to economic logic (pool accounting, lending interest,
vault strategies) — still explicitly out of scope until compliance is
confirmed correct end-to-end.

---

## Milestone 1 — Foundation verification & stabilization (BUILD 01.5)

**Date:** 2026-08-08

**Context:** Verify and stabilize the `claude/bitv-recovery-foundation`
branch before any further feature work. No new product features added.

**Verified / fixed:**

- `npm install` — succeeds (833→853 packages). Existing peer-dependency
  warnings from `wagmi`/`RainbowKit`'s connector tree are pre-existing
  upstream noise, not something introduced here.
- `npm run build` — **initially failed**: RainbowKit's default connector
  set pulls in `@coinbase/cdp-sdk`, whose x402-payments code path imports
  `@x402/core`, `@x402/evm`, `@x402/svm`, `@x402/extensions` as real peer
  dependencies that weren't installed. Fixed by adding those four real
  npm packages (`^2.21.0`, matching cdp-sdk's declared peer range) to
  `package.json` — not stubbed or ignored.
- `npm run build` — **second failure**: static prerendering of `/`
  instantiated the RainbowKit/Wagmi config at build time, which throws
  without a real `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` ("No projectId
  found"). Since we don't fake credentials, the fix is architectural: added
  `export const dynamic = "force-dynamic"` to `app/layout.tsx` so the
  Web3-wrapped shell renders at request time (when a real env var is
  present) instead of at build time. No projectId was invented.
- `npm run build` — now **passes**. Two remaining compiler warnings
  (`@react-native-async-storage/async-storage` from MetaMask SDK,
  `pino-pretty` from WalletConnect's logger) are optional deps for
  code paths that only run in React Native / Node pretty-printing contexts,
  never reached from this browser app — left as warnings rather than
  silenced with fake stub packages.
- `npm run lint` — **initially failed** (285 errors): (1) ESLint config had
  no `.next/**` / `next-env.d.ts` ignore, so it was linting Next's own
  generated type-check files; fixed by adding those to `eslint.config.mjs`
  ignores. (2) Our own `services/cleanverse/types.ts` used empty
  `interface` placeholders, which `@typescript-eslint/no-empty-object-type`
  correctly flags as accepting any value; changed to
  `Record<string, never>` type aliases, which express "empty object,
  fields TBD" without that loophole. Also added an
  `argsIgnorePattern: "^_"` rule override so intentionally-unused stub
  params (`_address` in the Cleanverse client) don't warn.
- `npm run lint` — now passes clean (0 errors, 0 warnings).
- `npm run typecheck` (`tsc --noEmit`) — passes.
- Monad Testnet config (`config/chains.ts`) — chain ID `10143`, native
  currency MON (18 decimals), and block explorer
  `https://testnet.monadexplorer.com` cross-checked via web search against
  chainlist.org / chainid.network / Alchemy / thirdweb (direct fetch of
  `docs.monad.xyz` was blocked by this sandbox's egress policy). Removed
  the hardcoded RPC URL fallback from code — the chain now only resolves
  its RPC from `NEXT_PUBLIC_MONAD_TESTNET_RPC_URL`, per instruction not to
  hardcode a public RPC where an env var is expected. See
  `docs/architecture.md` for the full verified table and re-confirmation
  note.
- Cleanverse (`services/cleanverse/`) — reviewed and left as throwing
  stubs; no implementation added. This sandbox located Cleanverse's real
  docs URL (`docs.cleanverse.com`) via search but could not fetch its
  content (egress blocked), so nothing from search-result snippets (e.g.
  the terms "CVI"/"CVA") was implemented — see the rewritten
  `docs/cleanverse-integration-todo.md` for the exact 13-item checklist
  still outstanding, marked unverified where search surfaced candidate
  terminology.
- Contracts (`services/contracts/`) — added a `BitVContractName` union
  (`AccessManager | PoolManager | LendingManager | VaultManager |
  BitScoreManager | Treasury`) and typed `contractAddresses` as
  `Partial<Record<BitVContractName, DeployedContract>>`, so the registry
  shape is ready for all six protocol contracts without changing again
  when they're deployed. No addresses or ABIs added — still empty.
- `.env.example` — regrouped into Public frontend / Blockchain
  configuration / Cleanverse credentials (private, server-only) sections
  with an explicit warning that `NEXT_PUBLIC_*` is bundled client-side and
  must never hold a real credential. No new private-variable category was
  needed yet (no server-only, non-Cleanverse secrets exist in this
  foundation).

**Build result:** PASS
**Lint result:** PASS
**Typecheck result:** PASS

**Remaining blockers:**

- Cleanverse's real API/SDK content is still unread by this environment —
  blocks any real `services/cleanverse` implementation.
- Monad Testnet values are cross-source-verified but not confirmed against
  the primary `docs.monad.xyz` page directly (egress blocked here).
- No Solidity contracts exist yet — `services/contracts` is a typed but
  empty boundary.

**Next recommended milestone:** Get direct access to `docs.cleanverse.com`
(different network context, or the values manually provided) to resolve
the 13-item checklist in `docs/cleanverse-integration-todo.md`, then
implement `services/cleanverse` for real. In parallel, contract design for
`AccessManager` (the dependency root for the other five) can start once
Cleanverse's identity primitive shape is known, since access control will
likely gate on it.

---

## Milestone 0 — Project foundation reconstruction

**Date:** 2026-08-08

**Context:** Full clean-slate rebuild per BITV PROJECT RECOVERY brief. The
previous repo contents (a Foundry Solidity protocol under active PR review,
and a legacy Vite/vanilla-JS frontend) were removed by explicit user
instruction to start the product from the current specification.

**What was built:**

- Next.js (App Router) + TypeScript + Tailwind CSS project scaffold
- shadcn/ui wiring (`components.json`, `components/ui/` placeholder)
- Design tokens for BitV brand (black primary, orange accent) in
  `app/globals.css` + `tailwind.config.ts` — see `docs/design-tokens.md`
- Typography: Poppins (primary) / Montserrat (secondary) via
  `next/font/google` in `lib/fonts.ts`
- Web3 config: Wagmi + RainbowKit + TanStack Query provider
  (`components/providers/web3-provider.tsx`, `config/wagmi.ts`)
- Monad Testnet chain definition (`config/chains.ts`) — chain ID and RPC
  URL are best-effort and **must be verified** against Monad's official
  docs before real use
- Service-layer boundaries for Cleanverse and on-chain contracts
  (`services/cleanverse/`, `services/contracts/`) — stubs only, no fake
  implementations
- Environment variable template (`.env.example`)
- Documentation structure (`docs/architecture.md`, `docs/design-tokens.md`,
  `docs/cleanverse-integration-todo.md`, this log)

**Explicitly not built (per brief):** lending, borrowing, pools, vaults,
BitScore, any production Cleanverse transaction, any Solidity contracts.

**Verification status:** `npm install` / build was not run in this
session's sandbox. Dependencies are declared in `package.json` but not
installed or version-locked yet — first task on the next milestone.

**Next milestone:** Cleanverse documentation review (see
`docs/cleanverse-integration-todo.md`) to fill in
`services/cleanverse/types.ts` and `client.ts` for real, followed by
confirming Monad Testnet chain parameters and running a first successful
`npm install && npm run build`.
