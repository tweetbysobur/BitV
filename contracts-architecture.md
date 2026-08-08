# BitV Smart Contract Architecture

Status: testnet-ready. The interest-accrual solvency issue previously tracked here as an open, must-fix-before-mainnet item has been resolved by unifying debt accounting into `PoolManager` — see [§5 Interest accrual](#5-interest-accrual) for the fix and [§7 Testing strategy](#7-testing-strategy) for the invariant campaign that verifies it (32,768 calls across 128 runs, zero violations at a 1bp tolerance retained only for `WadRayMath` rounding).

Solidity 0.8.28, Foundry, deployed to Monad Testnet. Source lives in `contracts/src`, tests in `contracts/test`, deployment in `contracts/script/Deploy.s.sol`.

---

## 1. System overview

Six manager contracts, one registry, one identity adapter, one price oracle:

```
                         ┌─────────────────────┐
                         │   ProtocolRegistry   │  (not upgradeable — plain AccessControl)
                         │  bytes32 key → addr  │
                         └──────────┬───────────┘
                                    │ every manager resolves peers through this
              ┌─────────────────────┼─────────────────────┬───────────────────┐
              │                     │                     │                   │
    ┌─────────▼────────┐  ┌─────────▼────────┐  ┌─────────▼────────┐ ┌────────▼─────────┐
    │   AccessManager   │  │  BitScoreManager │  │     Treasury     │ │   PoolManager     │
    │ (UUPS proxy)       │  │ (UUPS proxy)     │  │ (UUPS proxy)     │ │ (UUPS proxy)      │
    └─────────┬──────────┘  └────────▲─────────┘  └────────▲─────────┘ └────────▲──────────┘
              │ requireCapability     │ reportEvent          │ collectFee          │ borrowFromPool
              │                       │                      │                     │ notifyRepay
    ┌─────────▼──────────────────────┴──────────────────────┴─────────────────────┴──────────┐
    │                              LendingManager (UUPS proxy)                                 │
    │        collateral · debt · health factor · liquidation · under-collateralized credit     │
    └─────────┬─────────────────────────────────────────────────────────────────────────────┬─┘
              │                                                                               │
    ┌─────────▼──────────┐                                                          ┌─────────▼──────────┐
    │   VaultManager      │                                                          │ CleanverseIdentity  │
    │ (UUPS proxy)         │──── requireCapability / isEligibleForPool ─────────────▶│      Adapter        │
    │ permissioned vaults  │                                                          │ (plain AccessControl)│
    └──────────────────────┘                                                          └─────────┬───────────┘
                                                                                                   │
                                                                                        ┌──────────▼──────────┐
                                                                                        │ Cleanverse on-chain │
                                                                                        │  A-Pass / Validator │
                                                                                        │  (external, ABI     │
                                                                                        │   unconfirmed)      │
                                                                                        └─────────────────────┘
```

`IIdentityOracle` is the seam: every manager depends on that interface only, never on Cleanverse's contracts directly. `CleanverseIdentityAdapter` is the sole implementation. If Cleanverse's on-chain ABI differs from what `ICleanverseAPass`/`ICleanverseValidator` assume (their REST-derived best-effort shape — see the provenance notes in those files), only the adapter changes.

`IPriceOracle` is a second, independent seam. `StaticPriceOracle` is an honestly-labelled placeholder (governance-set prices with staleness enforcement) — see its NatSpec for the production migration path to a real feed aggregator.

### Contract responsibilities

| Contract | Owns | Depends on |
|---|---|---|
| `ProtocolRegistry` | Address resolution | nothing |
| `AccessManager` | Roles, capability → Validator pool bindings | `IIdentityOracle` |
| `BitScoreManager` | Reputation score, credit-limit curve | nothing (pure function of its own state + `identityTier` param) |
| `Treasury` | Protocol fee/reserve custody | nothing |
| `PoolManager` | Single-asset liquidity pools — supply-side accounting AND pool-level debt accounting (liquidity index + borrow index, both) | `IInterestRateModel`, `IAccessManager`, `IIdentityOracle`, `ITreasury` |
| `LendingManager` | Per-account collateral & debt positions, liquidation, credit lines — reads/writes pool-level debt state exclusively through `PoolManager` | `IPoolManager`, `IAccessManager`, `IIdentityOracle`, `IBitScoreManager`, `IPriceOracle` |
| `VaultManager` | Permissioned yield vaults | `IAccessManager`, `IIdentityOracle`, `ITreasury` |
| `CleanverseIdentityAdapter` | Cleanverse ABI translation | `ICleanverseAPass`, `ICleanverseValidator`, `ICleanverseAccessCore` |
| `StaticPriceOracle` | Asset USD prices | nothing |
| `KinkedInterestRateModel` | Utilization → rate curve | nothing (pure) |
| `BitVReceiptToken` | Scaled-balance ERC20 (aToken / vault share) | its owning manager (mint/burn only) |

---

## 2. Deployment order

Executable version: `script/Deploy.s.sol`. The ordering constraint, in words:

1. **`ProtocolRegistry`** — first, unconditionally. Every proxy below needs an address to point at even before the registry has any entries.
2. **`CleanverseIdentityAdapter`, `StaticPriceOracle`** — standalone, no registry dependency at construction.
3. **Five UUPS-proxied managers** (`AccessManager`, `BitScoreManager`, `Treasury`, `PoolManager`, `LendingManager`, `VaultManager`) — order among these five doesn't matter to each other; none call a peer during `initialize`.
4. **Registry population** — `setAddress` for all eight keys. Nothing above depends on this having happened yet, which is exactly why it's safe to do after all eight addresses exist.
5. **Cross-module role grants** — `PoolManager.LENDING_MANAGER_ROLE` → `LendingManager`; `Treasury.FEE_COLLECTOR_ROLE` → `PoolManager` and `VaultManager`; `BitScoreManager` reporter authorization → `LendingManager`.
6. **Market creation** (not in `Deploy.s.sol` — a governance action) — `PoolManager.createPool`, `LendingManager.setBorrowConfig`, `VaultManager.createVault` per listed asset.
7. **Capability binding** (governance) — `AccessManager.setCapabilityRequirement` per `Capability`, once the corresponding Cleanverse Validator pool is registered.

Steps 6–7 are deliberately excluded from the deploy script: market parameters and capability gating are governance decisions with their own review process, not deployment constants.

---

## 3. Storage layout

Every UUPS-proxied contract (`BaseModule` and its six subclasses) uses **ERC-7201 namespaced storage** — each contract's state lives in a struct at `keccak256(abi.encode(uint256(keccak256("bitv.storage.<Name>")) - 1)) & ~0xff`, accessed via inline assembly, rather than sequential storage variables.

**Why this matters for upgrades**: sequential storage (`contract Foo { uint256 x; }`) ties a variable's slot to its *declaration order*. Adding a field in an upgrade, or a base contract gaining a field, shifts every subsequent variable's slot — the classic proxy-upgrade storage collision. A namespaced slot is a fixed, content-addressed location independent of declaration order or inheritance depth: `BaseModule`'s storage slot never moves regardless of what `PoolManager` (which inherits it) declares, and `PoolManager` can add new namespaced structs in a future version without touching `BaseModule`'s or its own existing slot.

Slot constants are committed as literals (see each contract's `STORAGE_LOCATION`), not computed at runtime — computing them via `keccak256` at deploy time would cost gas on every read through the assembly accessor; as compile-time constants they cost nothing.

`ProtocolRegistry` and `CleanverseIdentityAdapter` are **not** proxied and use ordinary sequential storage — see their own NatSpec for why a full upgrade story isn't needed there.

---

## 4. Event documentation

Every state-changing function emits an event. Grouped by what an indexer would actually want to watch:

**Access & identity**
- `AccessManager.CapabilityRequirementSet(capability, validatorPool)` — governance changed which Validator pool gates a capability, or removed the gate (`validatorPool == 0`).
- `AccessManager.RoleGranted` / `RoleRevoked` — inherited from `IAccessControl`, re-emitted (not duplicated) for every role change including `AccessManager`'s own custom roles.
- `CleanverseIdentityAdapter.APassSet` / `ValidatorSet` — the adapter's upstream Cleanverse contract addresses changed.

**Liquidity (`PoolManager`)**
- `PoolCreated(asset, aToken, rateModel)`
- `Supplied` / `Withdrawn(asset, supplier, amount, scaledAmount)` — both the underlying amount and the scaled (index-independent) amount, so an indexer can reconstruct a point-in-time balance without re-deriving the liquidity index itself.
- `InterestAccrued(asset, liquidityIndexRay, borrowIndexRay, supplyRateRay)` — emitted on every accrual, which is the append-only history a rate chart is built from. Both indices are emitted together because both are always advanced together, from one accrual call — see §5.
- `PoolStateUpdated`, `ValidatorPoolSet` — governance actions.

**Debt (`LendingManager`)**
- `CollateralDeposited` / `CollateralWithdrawn`
- `Borrowed(account, asset, amount, underCollateralized)` — the boolean flag is what lets a dashboard distinguish "ordinary collateralized borrow" from "identity-based credit line used" without re-deriving it from collateral state.
- `Repaid(account, asset, amount, payer)` — `payer` separate from `account` because `repay` supports repaying on behalf of another account.
- `Liquidated(borrower, liquidator, debtAsset, collateralAsset, debtRepaid, collateralSeized)`

**Vaults (`VaultManager`)**
- `VaultCreated`, `VaultDeposited`, `VaultWithdrawn`, `RewardsDistributed`, `VaultStateUpdated`

**Reputation (`BitScoreManager`)**
- `ScoreUpdated(account, previousScore, newScore, reason, reporter)` — `reason` is the `ScoreEvent` enum, `reporter` is the authorized contract that triggered it. Both indexed, so "show me every liquidation-driven score change" is a single filtered log query, not a full-history replay.

**Treasury**
- `FeeCollected(asset, source, amount)`, `LiquidationProceedsReceived`, `ReserveWithdrawn`

---

## 5. Security considerations

**Reentrancy.** `ReentrancyGuardTransient` (EIP-1153 transient storage, not the old storage-slot guard — see the note in `BaseModule.sol` on why this is the correct choice post the OpenZeppelin version pinned here removing the upgradeable storage-based variant) on every state-changing external entry point across all five managers.

**Access control.** Every privileged action (`createPool`, `setBorrowConfig`, `pause`, upgrades) is role-gated via `AccessControlUpgradeable`, with distinct roles for distinct blast radii — `PAUSER_ROLE` (fast, narrow: freeze a module) is separate from `GOVERNANCE_ROLE` (slower, broad: unpause, change parameters) is separate from `UPGRADER_ROLE` (rarest, highest-consequence: swap implementation code).

**Identity gating fails closed.** An unconfigured or paused Cleanverse Validator pool reverts (`ValidatorPoolNotConfigured`, `ValidatorPoolPaused`) rather than silently passing every check — see `AccessManager.requireCapability` and `CleanverseIdentityAdapter.isEligibleForPool`.

**Decimals normalization.** Every USD valuation in `LendingManager` (collateral, debt, borrow eligibility, liquidation seizure) routes through `_toWad`/`_fromWad`, which read the actual token's `decimals()` rather than assuming 18. **This was found as a real bug during testing** — mispricing every 6-decimal asset (e.g. USDC) by exactly 10¹² — and is exactly the kind of defect a per-call-site ad hoc conversion invites; centralizing it is what makes it auditable once instead of six times.

**Liquidation cannot seize more than is posted.** Because BitV's health factor counts BitScore-derived unsecured credit alongside real collateral (see `LendingManager`'s contract-level NatSpec — its risk model is genuinely under-collateralized by design, not a bug), a liquidation can only ever recover value from actual posted collateral. `liquidate` reverts rather than partially executing when the computed seizure exceeds available collateral, so the function's accounting stays exact; residual unsecured bad debt is an accepted, documented risk premium of the product, not a silent shortfall.

**Upgrade authorization is explicit and narrow.** `_authorizeUpgrade` is gated to `UPGRADER_ROLE`, never left to the default admin — see `BaseModule.sol`.

**Cleanverse ABI risk.** `ICleanverseAPass`, `ICleanverseValidator`, `ICleanverseAccessCore` are best-effort interfaces derived from Cleanverse's REST API documentation (`docs/cleanverse-integration.md`), not a published Solidity ABI. Every one of these files states this explicitly and names `CleanverseIdentityAdapter` as the sole point of change if the deployed ABI differs. **Do not deploy to mainnet without confirming these against Cleanverse's actual deployed contracts.**

---

## 6. Interest accrual — the unified-index fix

An earlier design split interest accrual across two contracts: `PoolManager` maintained its own `liquidityIndexRay`, and `LendingManager` separately maintained its own `borrowIndexRay` in `DataTypes.BorrowConfig`, each independently calling `IInterestRateModel.getRates` and compounding on its own schedule — triggered by whichever transaction happened to touch that contract next. Because the two indices integrated two different rate PATHS over time rather than one shared one, the invariant `cash + totalBorrowed >= totalSupplied` (PoolManager can never owe suppliers more than it holds plus what's out on loan) drifted apart under sustained usage — confirmed via fuzzing to exceed 1% of pool size, a real, usage-scaling gap, not rounding noise.

**Fix**: both indices now live on ONE struct — `DataTypes.Pool.liquidityIndexRay` and `DataTypes.Pool.borrowIndexRay`, advanced together by ONE function (`PoolManager._accrue`) from ONE `IInterestRateModel.getRates` call per accrual, against ONE shared `lastUpdateTimestamp`. `totalScaledDebt` moved from `LendingManager` to `PoolManager` alongside `borrowIndexRay` for the same reason: `totalBorrowed` is now *derived* (`totalScaledDebt.rayMul(borrowIndexRay)`, exposed via `IPoolManager.totalBorrowed`), never separately mirrored — there is no reconciliation step left for the two sides to drift apart on.

`LendingManager` no longer maintains any interest-rate state. It owns exactly two things per account — `collateral` and `DebtPosition.scaledDebt` (a share of PoolManager's pool-wide total, scaled at PoolManager's index) — and reads the current index from PoolManager on every operation:

- **Mutating paths** (`borrow`, `repay`, `liquidate`) call `PoolManager.accrueInterest(asset)` first, then `PoolManager.borrowFromPool`/`notifyRepay`, which compute the scaled amount at the exact index they just used and **return it** to `LendingManager`. Applying that returned value (rather than recomputing it locally from a value read a moment earlier) is what guarantees `sum(account.scaledDebt) == pool.totalScaledDebt` exactly.
- **View paths** (`healthFactor`, `debtOf`) call `PoolManager.previewAccruedIndices(asset)` — a `view`-safe projection of what the indices would be if accrued right now, computed with the identical math as `_accrue` but writing nothing, since a `view` function cannot call the mutating version.

Reserve accrual also became exact rather than modeled as a side effect: the reserve's cut is now `(debtAfter - debtBefore).percentMul(reserveFactorBps)`, where both values are derived from the *same* `totalScaledDebt` before/after the index moves — no second, independent rate-model estimate.

Verified via `test/invariant/PoolSolvency.invariant.t.sol`: 32,768 calls across 128 runs (4x the configured default), zero violations at a 1 basis-point tolerance retained only for `WadRayMath`'s round-to-nearest behavior on scaled-amount conversions.

---

## 7. Testing strategy

`contracts/test/`:

- **`BaseTest.sol`** — deploys the full protocol behind real proxies (not simplified stand-ins), wires every role and registry entry exactly as `Deploy.s.sol` would, and seeds two markets (USDC, WETH) with realistic risk parameters. Every unit test inherits this, so tests exercise the real deployment topology.
- **`test/unit/*.t.sol`** — one file per manager, covering the success path, every documented revert condition, and the specific bugs found and fixed during this pass (decimals normalization, BitScore zero-vs-uninitialized sentinel collision, receipt-token-transfer balance accounting).
- **`test/unit/InterestMath.t.sol`** — property-based fuzz tests on the interest math library: compounding must never be less than simple interest for a non-negative rate; index accrual must never decrease for a non-negative multiplier.
- **`test/invariant/PoolSolvency.invariant.t.sol`** — a stateful handler contract performing randomized supply/withdraw/borrow/repay/time-warp sequences against the real contracts, checking the pool-solvency invariant after every call. This is what surfaced the decimals bug, the BitScore sentinel bug, and the interest-accrual drift documented in §6 — invariant testing found three real defects that example-based unit tests alone did not, and verified the fix for all three.

Run: `forge test` (unit + fuzz + invariant, all active). `forge test -vvv` for traces on failure. Fuzz/invariant run counts are configured in `foundry.toml` (`[profile.default.fuzz]` 512 runs, `[profile.default.invariant]` 64 runs × 64 depth; `[profile.ci]` raises both for pre-merge/release checks). The invariant suite was additionally stress-tested at 128 runs × 256 depth (32,768 calls) before this fix was considered verified.
