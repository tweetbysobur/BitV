# BitV Permissioned Yield Vault Implementation (Build 05.1)

Implements `docs/yield-vault-specification.md` exactly — no architectural
redesign. This document records what was actually built, one real bug
found and fixed during implementation (not hypothetical), and what
remains a known limitation.

## Contract architecture

New:
- `contracts/src/core/BitVYieldVault.sol` — `ERC4626 + BitVComplianceGuard
  + BitVRoleConsumer + ReentrancyGuard`. Owns all accounting, compliance,
  limits, pause, and fee logic (spec §3).
- `contracts/src/interfaces/IBitVVaultStrategy.sol` — the narrow
  vault↔strategy boundary (`asset`, `vault`, `totalAssets`, `deposit`,
  `withdraw`, `emergencyWithdraw`). A strategy can only ever report a
  `totalAssets()` figure into vault accounting — it cannot mint/burn
  shares, change configuration, or otherwise touch the vault's state.
- `contracts/src/vault/TestYieldStrategy.sol` — the MVP's only strategy,
  explicitly non-production (see "Test strategy" below).
- `contracts/src/libraries/VaultErrors.sol` — vault-specific errors, per
  the codebase's existing per-domain error library convention
  (`ProtocolErrors` for lending, `ComplianceErrors` for Cleanverse).

Modified:
- `contracts/src/core/BitVAccessManager.sol` — added `VAULT_MANAGER_ROLE`
  and `STRATEGY_MANAGER_ROLE` (spec §8), granted to `admin` at
  construction alongside the four existing roles. No other role was
  added, and `RISK_MANAGER_ROLE`/`PAUSER_ROLE` were reused as-is for the
  fee rate and pause switches respectively.

Untouched: `BitVPoolManager.sol`, `BitVLendingManager.sol`,
`BitScoreManager.sol`, `BitVComplianceGuard.sol`,
`IAPassComplianceValidator.sol`, `BitVTreasury.sol`. The pre-existing
Build-01.5-era `BitVVaultManager.sol` compliance stub is also untouched
— it is not this vault, and is not wired to it.

## ERC-4626 implementation

Uses OpenZeppelin's `ERC4626` unmodified as the base, with a
**conservative fixed decimal offset of 6** (`_decimalsOffset()` returns
`6`), chosen deliberately over OpenZeppelin's default of `0`. With this
offset, an attacker attempting the classic "donate to the empty vault"
inflation attack needs to donate roughly 1,000,000× their own deposit to
move the reported share price by one part in a million — verified
directly by `test_InflationAttack_FirstDepositorCannotStealFromSecond`,
which has an attacker deposit the minimum, then donate 1,000,000e18
directly to the vault, and confirms a subsequent normal-sized depositor
still receives a fair, substantial share of what they put in rather than
being rounded down to near-zero.

`deposit`/`mint`/`withdraw`/`redeem` are all overridden (not left as
OpenZeppelin's defaults) to layer in, in order: a self-service-only
check, the relevant pause check, the Cleanverse compliance check,
performance-fee accrual, and (for withdraw/redeem) a liquidity-ensuring
step — before delegating to `super.deposit`/`super.mint`/
`super.withdraw`/`super.redeem` for the actual conversion/transfer/mint/
burn logic, which is never reimplemented. Rounding direction is
therefore exactly OpenZeppelin's own (floor on the share-out side of
deposit/mint, ceil on the share-in side of withdraw, floor on the
asset-out side of redeem) — `test_Rounding_NeverFavorsDepositor` checks
this holds end-to-end through BitV's overrides, not just in isolation.

`totalAssets()` is overridden to be idle balance (`asset().balanceOf`)
plus the active strategy's reported `totalAssets()` — the only point at
which strategy-reported value enters vault accounting at all.

## Share accounting

**Self-service only, for both principal and exit.** `deposit`/`mint`
require `receiver == msg.sender`; `withdraw`/`redeem` require
`receiver == owner == msg.sender`. This is a deliberate implementation
choice within the approved architecture (not a redesign of it): it
closes, structurally, a bypass the specification didn't explicitly
enumerate but that the same reasoning applies to — a compliant caller
minting shares directly to (or redeeming on behalf of) a different
address without that address's own compliance being checked. Reverts
`VaultErrors.OnlySelfService`.

**Non-transferable shares**, exactly as specified (spec §7's chosen MVP
architecture): `_update` is overridden to permit only `from == 0`
(mint) or `to == 0` (burn); any genuine transfer (`from != 0 && to != 0`)
reverts `OnlySelfService`, regardless of whether it's a direct
`transfer` or an allowance-based `transferFrom`. There is no
compliance-gated-transfer code path to audit or forget — the transfer
path does not exist. `test_NoShareTransferComplianceBypass` covers both
`transfer` and `transferFrom`.

**Zero-share / zero-asset protection**: `deposit(0, ...)` reverts
`BelowMinimumDeposit` (since `minDeposit > 0` by construction in every
test fixture and is expected to be set `> 0` in any real deployment);
`mint(0, ...)` reverts `ZeroShares` directly; a `deposit`/`mint` whose
computed share/asset amount would round to zero is pre-checked and
reverted before any transfer happens, rather than silently succeeding
with a zero-effect state change.

**Minimum deposit floor**: `minDeposit` (an underlying-asset-unit
threshold, `VAULT_MANAGER_ROLE`-configurable) is enforced on `deposit`'s
`assets` parameter directly and on `mint`'s *resulting* `assets` amount
(computed via `previewMint` before the call) — both entry points are
covered, not just one.

## Compliance integration

Reuses `BitVComplianceGuard`/`IAPassComplianceValidator` completely
unmodified — `BitVYieldVault` inherits `BitVComplianceGuard` exactly the
way `BitVPoolManager`/`BitVLendingManager` already do, registers its own
Cleanverse `RuleV2` rule(s) via the existing owner-gated
`setRuleV2FromContract`/`addRuleV2FromContract` wrappers, and calls
`_requireCompliance(msg.sender)` before both deposit and normal
withdrawal (`test_ComplianceRequired_BeforeDeposit`/
`test_ComplianceRequired_BeforeWithdrawal`, the latter re-checking
compliance at withdrawal time by revoking rules after an initial
compliant deposit and confirming the subsequent withdrawal reverts).

No personal identity data is stored anywhere in `BitVYieldVault` or
`IBitVVaultStrategy` — `complianceVerify` returns a boolean, exactly as
in every other BitV integration point.

**CVA**: not integrated, per the spec §10 conclusion — nothing in this
implementation labels the vault's underlying asset a CVA, and no CVA
interface is referenced.

## Strategy architecture

`BitVYieldVault.strategy` holds at most one `IBitVVaultStrategy` at a
time (`address(0)` = none configured, deposits simply sit idle).

- **`setStrategy(address)`** — `STRATEGY_MANAGER_ROLE`-only. Always
  calls the *old* strategy's `emergencyWithdraw()` first (recovering
  whatever it can, even if impaired) before adopting the new one, so a
  strategy is never orphaned mid-detachment with value stuck behind a
  dropped pointer. Validates the new strategy's `asset()` and `vault()`
  match this vault before adopting it.
  `test_Strategy_ReplacementExitsOldStrategy` confirms the old
  strategy's balance is fully recovered and `totalAssets()` is
  unaffected by a clean replacement.
- **`allocateToStrategy(uint256)`** / **`withdrawFromStrategy(uint256)`**
  — `VAULT_MANAGER_ROLE`-only, day-to-day liquidity management.
  Allocation is bounded by both `maxStrategyAllocationBps` (checked
  against the *resulting* strategy total, not just the increment) and
  `minIdleReserveBps` (the vault will not push funds out if doing so
  would breach the configured idle reserve).
- **`emergencyExitStrategy()`** — `STRATEGY_MANAGER_ROLE`-only,
  available regardless of `strategyPaused`; this is the exact mechanism
  `strategyPaused` exists to preserve access to.

**Test strategy vs. production strategy — explicitly distinguished.**
`TestYieldStrategy.sol`'s NatSpec opens with an unambiguous
"NON-PRODUCTION, TEST/DEVELOPMENT ONLY" banner. It holds deposited funds
and does nothing with them on its own; its `simulateYield(amount)`
function pulls additional underlying from whatever caller invokes it
(via `transferFrom`) — this is not, and is never described as, a real
yield source. Its constructor requires an explicit
`confirmedTestOnlyDeployment` boolean set to `true`, reverting
`VaultErrors.NotTestOnlyDeployment()` otherwise, so it cannot be
deployed by an unattentive script. No production strategy was
implemented — out of scope per instruction.

## Limits

| Limit | Enforced by | Role |
|---|---|---|
| Vault deposit cap (`vaultCap`) | `maxDeposit`/`maxMint` return 0 once `totalAssets() >= vaultCap`; `deposit`/`mint` inherit OpenZeppelin's `ERC4626ExceededMaxDeposit`/`ERC4626ExceededMaxMint` revert via `super.deposit`/`super.mint` | `VAULT_MANAGER_ROLE` sets |
| Minimum deposit (`minDeposit`) | Checked directly in `deposit`/`mint`, see "Share accounting" above | `VAULT_MANAGER_ROLE` sets |
| Strategy allocation cap (`maxStrategyAllocationBps`) | Re-checked against the resulting strategy total on every `allocateToStrategy` call, not just at configuration time | `STRATEGY_MANAGER_ROLE` sets |
| Minimum idle liquidity reserve (`minIdleReserveBps`) | Enforced in `allocateToStrategy` — the vault will not push idle balance below this fraction of `totalAssets()` | `VAULT_MANAGER_ROLE` sets |

Both bps limits default to their safest values at construction
(`minIdleReserveBps = 10,000` i.e. 100% idle; `maxStrategyAllocationBps
= 0`) — a freshly deployed vault uses no strategy at all until an admin
explicitly opts in, matching the spec's "the vault must not blindly
deploy 100% of assets into a strategy" requirement by simply not
deploying *any* assets until configured to.

## Fees

**Performance fee only**, exactly as specified — no management fee, no
withdrawal fee. Capped at `MAX_PERFORMANCE_FEE_BPS = 2,000` (20%),
enforced in `setPerformanceFeeBps`'s own revert check
(`VaultErrors.InvalidBps`), `RISK_MANAGER_ROLE`-gated.

**High-water-mark mechanism (deliberately minimal, per instruction not
to build a complex one):** a single monotonically-non-decreasing
`highWaterMarkAssets` peak. A performance fee is only ever charged on
the portion of `totalAssets()` that exceeds this prior peak — recovering
from a loss back up to a previous high is never taxed as if it were new
profit, resolving `docs/yield-vault-specification.md`'s open question 6
in the simplest correct way (never lower the mark on a loss; only raise
it when genuinely new profit is taxed).

**A real bug found and fixed during implementation, not a hypothetical:**
the first design (mint fee shares to the vault itself at the current
price, then have `collectPerformanceFee` immediately convert those same
shares back to assets via the *now-diluted* post-mint share price)
systematically under-paid the fee — minting new shares increases
`totalSupply()`, so reading them back against the enlarged denominator
values them below what they were minted for. Measured directly: a
configured 1,000 bps (10%) fee on a 500e18 profit should yield exactly
50e18, but the naive round-trip produced ~48.4e18 (a ~3.2% shortfall,
not rounding noise). **Fixed** by tracking `accruedFeeShares` and
`accruedFeeAssets` explicitly as a ledger at each accrual event, and
paying out exactly those tracked figures at collection time rather than
re-deriving the asset value from the shares via a second, self-diluting
conversion. `test_PerformanceFee_AccruesOnYield` and
`test_TreasuryAccounting_EventEmitted` assert the corrected, accurate
amount (within a small tolerance for the underlying `mulDiv` rounding
that remains, which does favor the vault, not the fee recipient).

**Also caught during the same review**: the high-water mark's initial
value of `0` would otherwise tax a *second* depositor's principal as if
it were profit relative to the first depositor's contribution (since
`totalAssets()` rising from a first deposit looks identical to yield
against a zero baseline). **Fixed** by bumping `highWaterMarkAssets` by
the exact principal delta on every deposit/mint/withdraw/redeem/fee-
collection (`_adjustHighWaterMarkForPrincipal`), so only genuine
strategy-driven growth between principal-changing actions is ever
counted as taxable profit. `test_PerformanceFee_AccruesOnYield`
specifically deposits from two separate users before introducing any
real profit and asserts no fee-shares exist yet at that point.

**Recipient**: `BitVTreasury`, via its existing, unmodified
`receiveFee(asset, amount)` entry point (`forceApprove` then call) — no
second treasury contract was created.
`test_PerformanceFee_RecipientIsTreasury` confirms the treasury's
underlying-asset balance increases by exactly the collected amount.

**Access control**: `collectPerformanceFee()` is `RISK_MANAGER_ROLE`-
gated (an implementation-level choice — the spec did not mandate who
triggers collection, only that the fee be transparently accounted for
and capped; gating it avoids an untrusted keeper controlling the timing
of treasury inflows).

## Pause controls

Three independent `bool`s, each `PAUSER_ROLE`-gated, mirroring
`BitVPoolManager`'s existing per-pool `isPaused` pattern rather than
introducing OpenZeppelin's `Pausable`:

- `depositsPaused` — blocks `deposit`/`mint`.
- `withdrawalsPaused` — blocks `withdraw`/`redeem` only; does **not**
  affect `emergencyWithdraw()`.
- `strategyPaused` — blocks `allocateToStrategy`/`withdrawFromStrategy`,
  and additionally blocks a normal withdrawal's liquidity-ensuring step
  from pulling out of the strategy (`_ensureLiquidity` reverts
  `InsufficientLiquidity` rather than touching a paused strategy) —
  forcing admins toward `emergencyWithdraw`/`emergencyExitStrategy`
  instead of a potentially-unsafe strategy interaction. Does **not**
  block `emergencyExitStrategy()`, which exists specifically to remain
  available through this pause.

`test_DepositPause_BlocksDeposit`, `test_WithdrawalPause_
BlocksNormalWithdrawal`, `test_StrategyPause_BlocksAllocation`, and
`test_EmergencyWithdrawal_AvailableDuringWithdrawalPause` cover all
four properties directly.

## Emergency withdrawal

`emergencyWithdraw()` (no arguments) burns **all** of the caller's
shares and returns their pro-rata share of the vault's **idle balance
only** — never assets still deployed to the strategy, since pulling
from a potentially-impaired strategy is exactly the risk this path
exists to avoid. Still requires compliance (`_requireCompliance`) —
compliance is never waived, only the operational pause/strategy-touching
complexity is. Available regardless of `withdrawalsPaused`/
`strategyPaused`.

This is a deliberately conservative, all-or-nothing design: a partial
emergency exit, or a later top-up once the strategy recovers additional
funds, is not implemented — a user who emergency-exits forfeits any
further claim on assets the strategy later manages to recover, since
their shares are already fully burned. Flagged as a known limitation
below (also present as spec open question 3, left unresolved by the
spec itself).

`emergencyWithdraw` never promises principal preservation — if
`totalAssets()` has genuinely fallen (e.g. via
`TestYieldStrategy.simulateLoss`), the pro-rata calculation reflects
that honestly rather than reverting or overstating what's recoverable.

## Security protections

| Risk | Protection | Test |
|---|---|---|
| Reentrancy | `ReentrancyGuard.nonReentrant` on every state-changing entry point | `test_Reentrancy_MaliciousTokenCannotReenterDeposit` |
| ERC-4626 inflation attack | Decimal offset 6 | `test_InflationAttack_FirstDepositorCannotStealFromSecond` |
| Donation attack | Decimal offset + fee-share accounting operating on `totalAssets()` rather than a manipulable per-call figure | `test_DonationAttack_CannotStealFromExistingDepositors` |
| Rounding / precision loss | OpenZeppelin's reviewed rounding preserved through all overrides; explicit fee-ledger fix (above) closes a genuine BitV-introduced rounding bug | `test_Rounding_NeverFavorsDepositor`, `test_PerformanceFee_AccruesOnYield` |
| Zero-share deposits | Pre-checked, reverted before any transfer | `test_ZeroDeposit_Reverts`, `test_ZeroShareDeposit_Reverts` |
| Strategy insolvency | `totalAssets()` reflects strategy loss honestly and immediately (no lag, no hiding) | `test_StrategyInsolvency_SharePriceReflectsLossHonestly`, `test_Strategy_Failure` |
| Unauthorized strategy replacement/operations | `STRATEGY_MANAGER_ROLE`/`VAULT_MANAGER_ROLE` gates, checked directly | `test_UnauthorizedStrategyChange_Reverts`, `test_UnauthorizedStrategyOperations_Reverts` |
| Fee manipulation | Hard cap in the setter | `test_FeeManipulation_CannotExceedCap`, `test_PerformanceFee_CannotExceedCap` |
| Vault cap bypass | `maxDeposit`/`maxMint` plus OpenZeppelin's own `ERC4626ExceededMax*` reverts | `test_VaultCapBypass_Reverts` |
| Strategy cap bypass | Re-checked on every allocation | `test_StrategyCapBypass_Reverts`, `test_Strategy_AllocationCapEnforced` |
| Compliance bypass | Deposit/withdrawal gated; non-transferable shares remove the transfer-based bypass structurally | `test_ComplianceRequired_BeforeDeposit`/`_BeforeWithdrawal`, `test_NoShareTransferComplianceBypass` |
| Emergency withdrawal | Always available, idle-only, honest about loss | `test_EmergencyWithdrawal_AvailableDuringWithdrawalPause`, `invariant_EmergencyWithdrawalNeverExceedsRecoverable` |

**This implementation is not claimed to be production-ready, audited, or
free of undiscovered vulnerabilities.** Two real bugs were found and
fixed during this milestone's own review (the fee-ledger double-
dilution bug and the high-water-mark principal-taxation bug, both
detailed above) — evidence that careful review matters, not evidence
that none remain.

## Tests created

- `contracts/test/BaseVaultTest.sol` — shared fixture (access manager,
  treasury, compliance mock, mock underlying, deployed vault, an
  unwired `TestYieldStrategy`).
- `contracts/test/mocks/MockReentrantVaultERC20.sol` — reentrancy-attack
  mock targeting the vault's `deposit(uint256,address)` signature,
  mirroring the existing `MockReentrantERC20` used for
  `BitVPoolManager`.
- `contracts/test/unit/BitVYieldVault.t.sol` — 44 scenario tests across
  access, accounting, security, strategy, fees, pause, and compliance
  categories (full list matches `docs/yield-vault-specification.md`
  §19's plan).
- `contracts/test/invariant/VaultHandler.sol` /
  `BitVYieldVaultInvariant.t.sol` — 8 fuzzed invariants (256 runs /
  128,000 calls each): internally-consistent accounting, shares never
  created without assets, strategy exposure never exceeds its cap, fees
  never exceed the configured maximum (and are only ever changed via
  the handler's authorized path), compliance cannot be bypassed,
  unauthorized configuration changes are always rejected, and emergency
  withdrawal never transfers more than the vault's idle balance.

## Full Foundry result (actually executed)

`forge test` (after `forge build` confirmed a clean compile,
`via_ir = true`, solc 0.8.24): **8 suites, 123 tests, 123 passed, 0
failed, 0 skipped.** This includes the two new vault suites (44 unit +
8 invariant) and all six pre-existing suites
(`BitVComplianceGuard.t.sol` 11, `BitVLendingManager.t.sol` 12,
`BitVPoolManager.t.sol` 12, `BitScoreManager.t.sol` 21,
`BitVLiquidation.t.sol` 7, `BitVInvariant.t.sol` 8 invariants at 256
runs/128,000 calls each) — all still passing unchanged, confirming this
milestone did not regress the lending/compliance/BitScore engine.

## Known limitations

- **`maxWithdraw`/`maxRedeem` are not overridden** — they use
  OpenZeppelin's default (owner's share balance converted to assets),
  which does not reflect real-time pause state or strategy illiquidity.
  The actual `withdraw`/`redeem` functions enforce those conditions via
  reverts regardless, so this is a UX/integrator-signaling gap, not a
  security gap — an integrator calling `maxWithdraw` first may see a
  nonzero figure that a subsequent `withdraw` call still reverts on.
- **Emergency withdrawal is all-or-nothing and idle-only** — a user
  cannot partially exit, and forfeits any later claim on strategy funds
  recovered after their exit (spec open question 3, still unresolved).
- **`emergencyWithdraw` does not accrue or pay the performance fee** —
  by design, to keep the emergency path maximally simple and robust;
  documented as a deliberate simplification, not an oversight. This
  means an emergency exit can, in principle, let a user avoid a
  since-unrealized fee — acceptable for an emergency path whose purpose
  is guaranteed access, not fee optimization.
- **Vault liquidity is completely independent from BitV's lending
  pools** (spec §16 decision A) — no pool-as-strategy integration
  exists or was attempted.
- **Single test strategy only** — no production yield strategy was
  implemented, per instruction.
- **BitScoreManager is not integrated** — per the spec's explicit
  conclusion that no strong reason was found to make it a vault
  dependency.
- **No governance, no RWA markets, nothing deployed** — per instruction.
