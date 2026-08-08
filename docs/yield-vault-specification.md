# BitV Permissioned Yield Vault Specification (Build 05, part 1)

**Status: design specification only. No Solidity has been written or
modified for this milestone.** `contracts/src/core/BitVVaultManager.sol`
exists today only as a Build-01.5-era compliance-boundary stub (every
function checks `_requireCompliance` then `revert
ComplianceErrors.NotImplemented()`) — this document defines what should
replace it in a future implementation milestone, not what exists now.

This document is deliberately conservative about Cleanverse: every CVI
claim is grounded in the same official CVI Integration Guide V2 already
implemented in `BitVComplianceGuard`/`IAPassComplianceValidator`
(§3, §5). No CVA claim is made unless traceable to the CVA Integration
Guide the user provided in Build 02.1. Where CVA cannot be confirmed for
this deployment, that is stated explicitly rather than assumed.

---

## 1. Purpose

Add a permissioned yield vault product to BitV: verified users deposit a
single approved underlying asset, receive shares representing a claim on
the vault's assets, and redeem those shares later for the underlying
plus any yield the vault's strategy generated. This is a new, separate
product surface — it does not modify pool/lending/liquidation/BitScore
behavior, and (per this milestone's MVP decision, §15) does not route
vault liquidity into the lending pools.

Explicitly out of scope for this milestone: Solidity implementation,
RWA vault strategies (kept extensible for later, §19), and any live
strategy that generates real yield (the MVP ships a test-only
placeholder strategy, §6).

## 2. User flow

```
User
  │
  ▼
Cleanverse compliance check (CVI, complianceVerify)
  │  reverts ComplianceCheckFailed if not verified
  ▼
Vault eligibility (compliant + vault not paused + within caps)
  │
  ▼
Deposit approved underlying asset
  │
  ▼
Receive vault shares (ERC-4626 accounting, §4)
  │
  ▼
Vault strategy generates yield (or, in MVP, does not — §6)
  │
  ▼
Share value increases as totalAssets() grows
  │
  ▼
User withdraws / redeems
  │  compliance re-checked at withdrawal time too (§7)
  ▼
Assets returned
```

Every arrow into a protected action is a compliance checkpoint, not just
the first one — see §7 for exactly which functions check compliance and
why.

## 3. Vault architecture

Two-contract separation, mirroring the "vault accounting / strategy
execution" split the task requires:

- **`BitVYieldVault`** — one per approved underlying asset. Owns
  ERC-4626 accounting (shares, `totalAssets`, conversion), Cleanverse
  compliance gating, deposit/withdrawal limits, vault-level pause, and
  the *decision* of how much idle capital to push to/pull from its
  currently-approved strategy. Never touches strategy internals
  directly — only calls the narrow `IBitVVaultStrategy` interface.
- **`IBitVVaultStrategy`** (interface) / concrete strategy contracts —
  each strategy is a separate contract implementing a small interface
  (`deposit`, `withdraw`, `totalAssets`, `emergencyWithdraw`). The vault
  holds a reference to at most one *active* strategy at a time (§6);
  swapping strategies is a `STRATEGY_MANAGER_ROLE`-gated admin action,
  never a user choice.

This mirrors the existing separation pattern in the codebase
(`BitVPoolManager` owns pool accounting, `KinkedInterestRateModel` is a
narrow interface it calls into) rather than inventing a new
architectural style.

```
BitVYieldVault (per asset)
  ├─ ERC-4626 share accounting
  ├─ BitVComplianceGuard (CVI gate)
  ├─ BitVRoleConsumer (BitV's own RBAC)
  ├─ deposit/withdrawal limits, vault cap, pause state
  └─ IBitVVaultStrategy currentStrategy  ──▶  strategy contract
                                                 ├─ deposit(amount)
                                                 ├─ withdraw(amount)
                                                 ├─ totalAssets() view
                                                 └─ emergencyWithdraw()
```

One vault instance per underlying asset (§5) — not a single
multi-asset vault — so a strategy failure or compliance-rule change on
one asset's vault cannot affect another's accounting.

## 4. ERC-4626 decision

**Decision: use ERC-4626 (OpenZeppelin's `ERC4626`) as the share
accounting standard**, not a custom share system.

**Benefits:**
- Battle-tested `convertToShares`/`convertToAssets`/`previewDeposit`/
  `previewMint`/`previewWithdraw`/`previewRedeem` math, including
  OpenZeppelin's built-in decimal-offset mitigation for the classic
  first-depositor inflation attack (§10).
- Standard interface other tools/integrators/front-ends already know
  how to read (`asset()`, `totalAssets()`, `convertToShares`), reducing
  BitV-specific surface area to audit.
- Composable with the existing `IERC20`/`SafeERC20` patterns already
  used throughout `BitVPoolManager`/`BitVTreasury` — no new token
  standard to reason about.

**Risks / things ERC-4626 does NOT solve automatically, and this
specification must still address explicitly:**
- ERC-4626 by itself does not add compliance gating, deposit/withdrawal
  limits, pausability, or strategy routing — all of that is BitV-specific
  logic layered on top in `BitVYieldVault`, overriding the relevant
  hooks (`_deposit`, `_withdraw`, `maxDeposit`, `maxMint`, `maxWithdraw`,
  `maxRedeem`).
- The standard's donation-attack surface (an attacker directly
  transferring underlying tokens to the vault to manipulate
  `totalAssets()`) is mitigated by OpenZeppelin's decimal offset but
  not eliminated in every configuration — §10 and §17 address this
  directly rather than assuming the standard makes it moot.
- **Transferability**: ERC-4626 shares are ERC-20 by default, i.e.
  freely transferable unless overridden. This directly conflicts with
  the permissioned design (§7) unless explicitly restricted — resolved
  in §7's MVP decision to disable transfers.

**Why ERC-4626 is still the right choice despite these risks**: every
risk above is an *additional* control BitV must layer on regardless of
which accounting model is chosen (a custom share system would face the
identical donation-attack and inflation-attack classes, just with
less-audited math). Using ERC-4626 gets the hard rounding/precision
math for free and lets BitV's own additions focus entirely on the parts
that are actually BitV-specific: compliance, limits, pause, and
strategy routing.

## 5. Asset model

- **One underlying asset per vault**, set immutably at construction
  (`ERC4626`'s `asset()`, backed by an `immutable IERC20` reference) —
  matches `BitVPoolManager`'s existing one-asset-per-pool model.
- **Explicitly configured, not arbitrary**: a vault is deployed by
  `PROTOCOL_ADMIN_ROLE` for one specific, pre-selected token address.
  There is no "deposit any ERC-20" path and no automatic conversion
  (no swap, no wrap/unwrap) between what the user holds and what the
  vault accounts for — the user must already hold the exact underlying
  asset.
- **CVA labeling**: do not call the underlying asset a CVA (Cleanverse
  Verified Asset) unless Cleanverse's own CVA registration for that
  specific token is confirmed off-chain. Nothing in this repository's
  Cleanverse documentation confirms any asset is CVA-registered on
  Monad Testnet today (the same "UNCONFIRMED" status already
  established in `docs/cleanverse-integration.md` for CVA generally).
  Until that is confirmed for a specific token, every MVP vault's
  underlying asset should be documented plainly as "an
  admin-configured ERC-20," not as "a CVA."

## 6. Strategy architecture

```solidity
interface IBitVVaultStrategy {
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function deposit(uint256 amount) external;      // vault -> strategy
    function withdraw(uint256 amount) external;      // strategy -> vault
    function emergencyWithdraw() external returns (uint256 recovered);
}
```

- Called only by the vault that owns it (`onlyVault`-style check inside
  the strategy, mirroring `BitVPoolManager.onlyLendingManager`'s
  single-trusted-caller pattern already used elsewhere in this
  codebase).
- The vault never deploys 100% of assets into a strategy (§14 —
  minimum liquidity reserve).

**TEST STRATEGY vs. PRODUCTION STRATEGY — explicitly distinguished, not
blurred:**

- **`TestYieldStrategy` (development/testing only)**: holds deposited
  funds and, at most, exposes an admin-only "simulate yield" hook that
  mints/transfers additional underlying into itself for test
  determinism. **This does not generate real yield from any real
  source.** It must be named and documented unambiguously as a test
  fixture (e.g. constructor reverts or is guarded so it cannot be
  deployed against a value bearing configuration without an explicit
  test flag), and must never be described in user-facing documentation
  or UI copy as a yield source.
- **Production strategy**: not designed in this milestone. Any future
  production strategy (e.g. deploying into a specific external
  protocol, or — subject to a future, separately-approved
  specification — into BitV's own lending pools, §15) needs its own
  security review before `STRATEGY_MANAGER_ROLE` may ever point a
  vault at it. This document defines the *interface* such a strategy
  must satisfy, not its contents.

**Strategy security controls:**
- **Approved strategy**: a vault's `currentStrategy` address is set
  only by `STRATEGY_MANAGER_ROLE` via an explicit `setStrategy(address)`
  call — never inferred, never user-selectable.
- **Strategy manager**: `STRATEGY_MANAGER_ROLE` (§8) is the only role
  that can set, replace, or trigger allocation changes for a strategy.
- **Strategy allocation / maximum allocation**: a vault-level
  `maxStrategyAllocationBps` (basis points of `totalAssets()`) bounds
  how much of the vault's assets may ever sit in the active strategy at
  once; enforced whenever the vault pushes funds to the strategy, not
  just at configuration time.
- **Strategy withdrawal**: the vault can call `strategy.withdraw(amount)`
  at any time `VAULT_MANAGER_ROLE` or the vault's own liquidity logic
  requires it (e.g. to satisfy a large user withdrawal that exceeds idle
  reserves).
- **Emergency strategy exit**: `STRATEGY_MANAGER_ROLE` (or
  `PROTOCOL_ADMIN_ROLE`) can call `strategy.emergencyWithdraw()`, which
  the strategy must implement to return whatever it can recover
  immediately, even at a loss — used when a strategy is believed
  compromised or failing, so the vault is never structurally forced to
  keep funds allocated to a strategy the admins no longer trust.

## 7. Cleanverse integration

Reuses the existing `BitVComplianceGuard`/`IAPassComplianceValidator`
architecture exactly as already implemented and tested for
`BitVPoolManager`/`BitVLendingManager` — no new CVI fields, no new
validator, no bypass path.

**Protected actions evaluated:**

| Action | Compliance check? | Rationale |
|---|---|---|
| Deposit | **Yes** — `_requireCompliance(msg.sender)` before minting shares | Primary eligibility gate; matches the spec's "CVI determines whether a user can access the vault." |
| Withdraw / redeem | **Yes** — `_requireCompliance(msg.sender)` before burning shares and returning assets | See below — withdrawal is not exempted, but see the emergency-controls carve-out in §11. |
| Share transfer | **N/A for MVP — transfers are disabled entirely (see decision below)** | Removes the bypass vector rather than trying to gate it. |
| Strategy interaction (vault↔strategy) | No — the strategy only ever talks to the vault contract itself, never to an end user directly, so there is no end-user compliance surface at this boundary | Consistent with `BitVPoolManager`/`BitVLendingManager`'s existing pattern of gating the user-facing entry point, not every internal call. |

**Share transfer decision — disabled for the MVP.** ERC-4626 shares are
ERC-20 and transferable by default. If BitV allowed transfers, a
verified user could deposit, then transfer shares to an unverified
wallet, which could then redeem — a direct compliance bypass, exactly
the risk this task calls out explicitly. Two options were evaluated:

- **(A) Gate `transfer`/`transferFrom` behind `_requireCompliance` on
  both `from` and `to`.** Technically closes the bypass, but adds a
  second, less-tested compliance-checkpoint surface (transfers are not
  today gated anywhere else in the codebase) and doesn't remove the
  underlying risk that a future code change forgets the check.
- **(B) Disable transfers entirely for the MVP** — override
  `_update`/`transfer`/`transferFrom` to revert unconditionally (shares
  can still move via mint on deposit and burn on withdraw/redeem, which
  are not "transfers" in the ERC-20 sense). This is the **chosen MVP
  architecture**: the safest option, structurally rather than
  procedurally correct (there is no transfer path to forget to gate,
  because there is no transfer path). Revisit in a future milestone if
  a real product need for share transferability (e.g. secondary
  liquidity) emerges — that would need its own compliance-bypass
  analysis at that time.

**CVI**: no personal identity data is stored by the vault or by
`BitScoreManager` — exactly the existing model. `complianceVerify`
returns a boolean; BitV never sees or stores CVI tier/group/subgroup
values beyond what `RuleV2` already encodes on Cleanverse's own
validator.

## 8. Access control

Extends `BitVAccessManager` (today: `PROTOCOL_ADMIN_ROLE`,
`RISK_MANAGER_ROLE`, `POOL_MANAGER_ROLE`, `PAUSER_ROLE`) with exactly
two new roles — no more:

- **`VAULT_MANAGER_ROLE`** — day-to-day vault operations: setting
  deposit/withdrawal limits, vault cap, minimum liquidity reserve,
  triggering strategy withdraw-to-vault for liquidity management.
  Mirrors `POOL_MANAGER_ROLE`'s scope for pools.
- **`STRATEGY_MANAGER_ROLE`** — setting/replacing the active strategy,
  setting `maxStrategyAllocationBps`, triggering
  `emergencyWithdraw()`. Kept separate from `VAULT_MANAGER_ROLE`
  because strategy risk (which external code the vault trusts) is a
  materially different decision from liquidity/limit management, and
  the task explicitly asks for a dedicated `STRATEGY_MANAGER` role.

`PROTOCOL_ADMIN_ROLE` retains the power to deploy new vaults and set
each vault's fee recipient/treasury address (§11). `PAUSER_ROLE` covers
vault-level and deposit/withdrawal-level pausing (§12) — reused as-is,
no new pauser role needed. **`RISK_MANAGER_ROLE` and `POOL_MANAGER_ROLE`
are not given any vault permissions** — they remain scoped to lending
pool risk parameters, consistent with "do not create unnecessary
roles."

Users are never granted any role — identical to every existing BitV
contract.

## 9. CVI integration

Already covered in full in §7. No new CVI fields are invented beyond
`RuleV2`'s existing `allowedGroup`/`allowedSubGroup`/`minTier`/
`minSubTier`/`poolCountryBitmap` — a vault registers its own RuleV2
rule(s) with Cleanverse exactly the way `BitVPoolManager` does today
(Single-Contract Mode, `setRuleV2FromContract`/`addRuleV2FromContract`,
owner-gated). A vault may reuse the same eligibility rule as its
underlying asset's lending pool, or configure a stricter one — that is
an operational decision for `PROTOCOL_ADMIN_ROLE` at deployment time,
not something this specification hardcodes.

## 10. CVA integration

**Evaluated for: vault deposits, vault assets, yield generation,
withdrawals. Conclusion: CVA integration is not confirmed for any of
these on the current deployment target, and this specification does
not claim otherwise.**

- **Vault assets / deposits**: per §5, whether a given vault's
  underlying token is a registered CVA is an off-chain Cleanverse fact
  this repository cannot self-certify. The architecture should remain
  *compatible* with a future CVA-gated asset (i.e. nothing in the vault
  design assumes the asset is *not* a CVA — the deposit/withdrawal path
  doesn't inspect or depend on CVA status either way), but no vault
  should be marketed or documented as "CVA-backed" until Cleanverse
  confirms it.
- **Yield generation**: the CVA Integration Guide the user provided in
  Build 02.1 describes CVA as an asset-verification primitive
  (`IComplianceRule`/`IATokenPolicy`, separate from CVI), not a
  yield-generation mechanism — nothing in that document connects CVA
  status to how yield is produced. This specification does not invent
  such a connection.
- **Withdrawals**: no CVA dependency — withdrawal eligibility is
  governed by CVI (§7), same as deposit.
- **Explicit integration dependency, if CVA is required later**: were a
  future vault to require its underlying asset be a verified CVA, the
  dependency would be: (1) Cleanverse confirms the specific token is
  CVA-registered off-chain, (2) the vault's compliance check would need
  to additionally consult the separate CVA `IComplianceRule`/
  `IATokenPolicy` interface (not `IAPassComplianceValidator`, which is
  CVI-only) — this is new interface surface not implemented anywhere in
  this repository today, and is out of scope until a specific vault
  needs it.

## 11. Share accounting

Standard ERC-4626 surface (`asset`, `totalAssets`, `convertToShares`,
`convertToAssets`, `maxDeposit`/`previewDeposit`/`deposit`,
`maxMint`/`previewMint`/`mint`, `maxWithdraw`/`previewWithdraw`/
`withdraw`, `maxRedeem`/`previewRedeem`/`redeem`), with BitV-specific
overrides:

- `maxDeposit`/`maxMint` return `0` when the caller is not compliant,
  the vault is paused, or the vault cap would be exceeded — signals
  ineligibility through the standard's own hooks rather than only
  reverting deep in `_deposit`, so integrators calling `previewDeposit`
  first see a sane number of `0`.
- `maxWithdraw`/`maxRedeem` return `0` when the caller is not compliant
  or withdrawals are paused (§12 addresses why withdrawal pausing needs
  extra care), otherwise return the actual redeemable amount, capped by
  currently-available (idle + emergency-recoverable) liquidity, never
  the theoretical full share value if the vault genuinely cannot honor
  it right now.

**First-depositor inflation attack**: mitigated by OpenZeppelin's
`ERC4626` decimal-offset mechanism (`_decimalsOffset()`), which the
vault should set to a non-zero value (e.g. matching OpenZeppelin's own
recommended default) so that manipulating the initial share price via a
1-wei first deposit followed by a large donation becomes economically
irrational rather than merely "difficult." This is a configuration
decision made explicit here, not a claim that ERC-4626 alone prevents
the attack — see also §17.

**Donation attacks**: an attacker can still transfer underlying tokens
directly to the vault (bypassing `deposit()`) to inflate `totalAssets()`
relative to `totalSupply()`. The decimal offset (above) makes this
economically unattractive for the classic first-depositor variant, but
this specification does not claim donation-attack immunity outright —
§17 requires this be part of the test plan (`test_DonationAttack_*`)
and code review before any implementation is considered acceptable.

**Rounding**: OpenZeppelin's `ERC4626` already rounds in the
protocol-favorable direction (down on deposit/mint's share-out
calculation, up on withdraw's share-burn calculation) — BitV's overrides
must not alter this rounding direction when adding compliance/limit
checks on top.

**Empty vault**: `totalSupply() == 0` is exactly the state the
decimal-offset mechanism protects; no additional special-casing should
be needed beyond correctly setting `_decimalsOffset()`.

**Zero-share deposits**: `deposit()`/`mint()` must revert (not silently
no-op) if the computed share amount would be zero — prevents a caller
from spending gas to receive nothing, and prevents a griefing pattern of
many zero-effect deposits.

**Minimum deposit**: a vault-level `minDeposit` (in underlying-asset
units, `VAULT_MANAGER_ROLE`-configurable) additionally guards against
dust deposits that could otherwise interact badly with rounding at very
small amounts, independent of the zero-share check above.

## 12. Fees

**Kept deliberately minimal for the MVP — a performance fee only, no
management fee, no withdrawal fee**, per "do not introduce unnecessary
fees" / "prefer the simplest fee structure":

- **Performance fee**: a `performanceFeeBps` (basis points) taken from
  realized yield only (the positive delta in `totalAssets()` growth
  attributable to strategy performance, not from user principal),
  `RISK_MANAGER_ROLE`-configurable, hard-capped at a constant maximum
  (e.g. 2,000 bps / 20%) enforced in the setter so no configuration
  can ever exceed it.
- **Management fee**: not included in the MVP — there's no ongoing
  operational cost this vault design needs to cover beyond what the
  performance fee already funds, and adding a second fee stream this
  early adds complexity without a demonstrated need.
- **Withdrawal fee**: not included in the MVP — nothing in this design
  creates a withdrawal-timing externality (no lock-up, no
  epoch-batching) that a withdrawal fee would need to price in.

**Every fee must satisfy (explicit per-fee, not just in aggregate):**
- **Maximum cap**: enforced in the setter function itself (revert if
  exceeded), not just documented.
- **Explicit recipient**: `BitVTreasury` (§14) — no fee is ever sent to
  an arbitrary or admin-supplied address other than the treasury.
- **Access control**: `RISK_MANAGER_ROLE` sets the rate; no one else can.
- **Transparent accounting**: an event on every fee accrual/collection
  (`PerformanceFeeAccrued(vault, amount)`), and the fee amount must be
  independently derivable from `totalAssets()` growth, not hidden inside
  opaque strategy internals.

## 13. Access control

(See §8 — consolidated there per the task's numbering to avoid
duplication; this section number is preserved for the task's requested
outline but content lives in §8.)

## 14. Emergency controls

Three independent, differently-scoped pause switches (finer-grained than
a single global pause), all `PAUSER_ROLE`-gated:

- **Vault pause**: blocks deposits, mints, and strategy allocation
  changes. Does **not** block withdrawals or redemptions — a paused
  vault must still let users exit.
- **Deposit pause**: narrower than vault pause — blocks only new
  deposits/mints (e.g. because the vault cap policy is being revised),
  leaving withdrawals and any other vault operation unaffected.
- **Withdrawal pause**: the task explicitly warns to be careful here.
  **Decision: withdrawal pause, if ever triggered, must be time-bounded
  and paired with a mandatory emergency-withdrawal path that remains
  open even while normal withdrawals are paused.** Rationale: users
  must never permanently lose access to funds because of a strategy
  failure. Concretely:
  - Normal `withdraw`/`redeem` (which may attempt to pull from the
    strategy if idle reserves are insufficient) can be paused if the
    strategy itself is in a failure state where calling into it could
    revert unpredictably or be exploited.
  - **Emergency withdrawal path**: a separate function
    (`emergencyWithdraw()`/`emergencyRedeem()`) that returns the user's
    pro-rata share of whatever the vault can *actually* account for
    right now — idle reserves plus whatever `strategy.emergencyWithdraw()`
    already recovered — even at a loss relative to the pre-failure share
    price, rather than reverting. This path stays available regardless
    of the withdrawal-pause flag; the pause only affects the "try to make
    the user whole via the strategy" path, never the "let the user exit
    with what's actually there" path.

## 15. Risk controls

- **Vault cap**: a `VAULT_MANAGER_ROLE`-configurable maximum
  `totalAssets()`; deposits reverting (via `maxDeposit`/`maxMint`
  returning `0`, §11) once it would be exceeded.
- **Strategy cap**: `maxStrategyAllocationBps` (§6) — the vault must
  never blindly push 100% of assets into a strategy.
- **Maximum strategy exposure**: identical control to strategy cap,
  re-checked on every allocation-changing action, not just at
  configuration time (defense in depth, matching the "triple-clamp"
  pattern already established for BitScore's LTV adjustment in Build
  04 — re-validate at the point of use, don't just trust a
  previously-set configuration value).
- **Approved asset**: immutable per-vault underlying asset (§5) — no
  path to change it post-deployment (a vault holding the wrong asset
  would need to be retired and redeployed, not "fixed in place").
- **Minimum liquidity reserve**: a `VAULT_MANAGER_ROLE`-configurable
  `minIdleReserveBps` — the vault always keeps at least this fraction of
  `totalAssets()` un-deployed (not sent to the strategy), so a
  reasonably-sized withdrawal can be served immediately without needing
  to call into the strategy at all. Directly implements "the vault must
  not blindly deploy 100% of assets into a strategy if that creates
  withdrawal risk."
- **Emergency exit**: §6/§14's `emergencyWithdraw()` paths, both at the
  strategy level (strategy → vault) and the vault level (vault → user).

## 16. Pool relationship

**Two options evaluated, per the task's explicit request:**

**(A) Vault liquidity completely separate from lending pools.**
- *Benefit*: strict isolation — a vault strategy failure cannot affect
  `BitVPoolManager`'s supply/borrow accounting or any lending user's
  funds, and vice versa; a lending-pool liquidity crunch (e.g. high
  utilization, paused borrowing) cannot block vault withdrawals. Each
  system's invariant tests (already 71/71 passing for the lending side)
  remain independently valid without needing to model cross-system
  interaction.
- *Risk*: vault yield is whatever the (initially test-only, §6)
  strategy produces — no yield "for free" from existing lending
  utilization.

**(B) Vault liquidity deployed into BitV lending pools as a yield
strategy** (i.e. a production `IBitVVaultStrategy` that itself calls
`BitVPoolManager.deposit`/`withdraw`, earning the pool's supply-side
interest as the vault's "yield").
- *Benefit*: reuses already-implemented, already-tested lending economics
  as a real (if modest) yield source, no new yield mechanism needed.
- *Risk*: couples two systems that were built and audited independently.
  A vault's large withdrawal could compete for the same pool liquidity
  lending users depend on (`BitVPoolManager.withdraw` already reverts if
  liquidity is insufficient — a vault-as-lender doesn't get special
  priority, so vault withdrawals could revert or be delayed by
  unrelated borrower activity, directly working against §14's promise
  that users can always exit). It also means a vault's `totalAssets()`
  now depends on `BitVPoolManager`'s scaled-balance accounting being
  correct in ways not yet analyzed together with ERC-4626's own
  accounting — two independently-correct systems composed together are
  not automatically jointly correct without dedicated integration
  analysis and tests, which this milestone has not done.

**Decision for the MVP: (A), completely separate.** This is the safer
architecture — it keeps the already-validated lending engine's
invariants untouched and avoids introducing withdrawal risk into the
vault from a system (pool utilization) the vault does not control.
Option (B) is not rejected permanently — it is exactly the kind of
"production strategy" §6 already scopes out for a dedicated future
specification, at which point the interaction above would need its own
integration-invariant test suite (e.g. "vault withdrawal never reverts
solely due to pool utilization" or an explicit, documented acceptance
that it can, with a mitigation) before being approved.

## 17. BitV component integration

- **`BitVAccessManager`**: extended with `VAULT_MANAGER_ROLE` and
  `STRATEGY_MANAGER_ROLE` (§8). Required dependency — every vault is a
  `BitVRoleConsumer`.
- **`BitVPoolManager`**: **no dependency** in the MVP (§16 decision A).
  A future production strategy *could* depend on it, but the vault
  contract itself does not import or call it.
- **`BitVTreasury`**: required dependency — the sole destination for
  performance fees (§12), via the same `receiveFee(asset, amount)`
  entry point `BitVPoolManager`/`BitVLendingManager` already use, so
  `BitVTreasury` needs no changes.
- **`BitVComplianceGuard`**: required dependency — every vault inherits
  it exactly as `BitVPoolManager`/`BitVLendingManager` do (§7).
- **`BitScoreManager`**: **not a dependency**. Per the task's explicit
  instruction, BitScore is not made a vault requirement unless this
  specification proves a strong reason to integrate it — it does not.
  BitScore's entire design (Build 04) is scoped to *lending risk*
  (LTV/interest adjustments tied to borrowing behavior); a yield vault
  has no borrowing, no liquidation, no credit risk for BitScore to
  price. Revisit only if a future feature genuinely needs it (e.g. a
  BitScore-tiered vault cap or fee discount) — no such feature is
  proposed here.

No unnecessary dependencies are introduced beyond
`BitVAccessManager`/`BitVTreasury`/`BitVComplianceGuard`/the Cleanverse
validator itself.

## 18. Security model

Explicit review of every item the task lists, with resolution status
for this design (not "solved," since nothing is implemented yet —
"addressed by design" means the specification has a concrete answer to
be verified in implementation and testing):

| Risk | Addressed by design |
|---|---|
| ERC-4626 inflation attack | Decimal offset (§11) |
| Donation attack | Decimal offset mitigates the classic variant; explicit test requirement (§19), no claim of full immunity |
| Share price manipulation | Same mitigations as above; compliance gating limits who can even attempt it, but does not by itself prevent it — economic mitigation, not access-control mitigation |
| Strategy insolvency | `emergencyWithdraw` at both strategy and vault level (§6, §14); minimum liquidity reserve limits blast radius (§15) |
| Oracle dependency | **None** — this vault design has no price oracle dependency; share price is purely `totalAssets()/totalSupply()`-derived, unlike `BitVPoolManager`'s LTV calculations |
| Reentrancy | `ReentrancyGuard` on all state-changing external entry points, mirroring `BitVPoolManager`/`BitVLendingManager`'s existing pattern (both already inherit it) |
| Precision loss | Inherits OpenZeppelin `ERC4626`'s reviewed rounding behavior (§11); no additional custom fixed-point math introduced |
| Rounding | Same as above — direction preserved, not reintroduced by BitV's overrides |
| Unauthorized strategy replacement | `STRATEGY_MANAGER_ROLE`-only `setStrategy` (§6, §8) |
| Fee manipulation | Hard-capped setter, `RISK_MANAGER_ROLE`-only, transparent events (§12) |
| Emergency withdrawal | §14 — always-available path, decoupled from the withdrawal-pause flag |
| Compliance bypass | Deposit and withdrawal both gated; transfers disabled entirely rather than gated, removing that bypass class structurally (§7) |

**This design is not claimed to be production-ready, audited, or free
of undiscovered vulnerabilities.** It is a specification to be
implemented, tested, and reviewed — exactly the posture taken for every
prior BitV milestone (compliance, pool/lending, BitScore).

## 19. Test plan

Mirrors the task's requested categories exactly; each maps to a
concrete scenario a future implementation milestone's Foundry suite
must cover (none of these tests exist yet — this is the plan for the
implementation milestone, not a report of tests already run):

**Access**
- `test_VerifiedUser_CanDeposit`
- `test_UnverifiedUser_DepositReverts`
- `test_UnverifiedUser_WithdrawReverts` (compliance is re-checked at
  withdrawal too, per §7)
- `test_ShareTransfersAreDisabled` (proves the §7 MVP decision holds —
  no unverified-recipient path exists because no transfer path exists)

**Accounting**
- `test_Deposit_MintsExpectedShares`
- `test_Withdraw_ReturnsExpectedAssets`
- `test_Mint_ChargesExpectedAssets`
- `test_Redeem_BurnsExpectedShares`
- `test_SharePrice_ReflectsTotalAssetsGrowth`
- `test_MultipleUsers_ProRataAccounting`
- `test_YieldIncrease_IncreasesSharePriceForAllHolders`

**Security**
- `test_Reentrancy_MaliciousTokenCannotReenterDeposit` /
  `..._Withdraw` (same pattern as the existing
  `BitVPoolManager.t.sol` reentrancy test)
- `test_DonationAttack_CannotStealFromExistingDepositors`
- `test_FirstDepositorInflationAttack_Mitigated`
- `test_Rounding_NeverFavorsDepositor`
- `test_ZeroDeposit_Reverts`
- `test_ZeroShareDeposit_Reverts`
- `test_UnauthorizedCaller_CannotChangeStrategy`
- `test_UnauthorizedCaller_CannotChangeFee`
- `test_UnauthorizedCaller_CannotPause`
- `test_StrategyLoss_SharePriceReflectsLossHonestly` (a strategy that
  loses funds must not let the vault overstate `totalAssets()`)

**Strategy**
- `test_Strategy_ReceivesAllocationUpToCap`
- `test_Strategy_WithdrawalReturnsFundsToVault`
- `test_Strategy_AllocationCannotExceedMaxBps`
- `test_Strategy_EmergencyExit_RecoversAvailableFunds`
- `test_Strategy_Failure_DoesNotBlockEmergencyWithdrawal`

**Fees**
- `test_PerformanceFee_ChargedOnlyOnRealizedYield`
- `test_PerformanceFee_CannotExceedConfiguredMax`
- `test_PerformanceFee_AccruesToTreasury`

**Compliance**
- `test_ComplianceRequired_BeforeDeposit`
- `test_ComplianceRequired_BeforeWithdrawal`
- `test_ComplianceCannotBeBypassed_ViaShareTransfer` (proves the
  transfer-disable decision, not a gated-transfer test, since there is
  no transfer path in the MVP)

**Invariants** (fuzzed, mirroring
`contracts/test/invariant/BitVInvariant.t.sol`'s existing style)
- `invariant_TotalAssetsAlwaysCoversRedeemableShares` (excluding
  amounts genuinely lost to strategy failure, which the share price
  must reflect honestly rather than hide)
- `invariant_SharesNeverExceedConfiguredCap`
- `invariant_StrategyAllocationNeverExceedsMaxBps`
- `invariant_UnauthorizedCallerCannotChangeStrategy`
- `invariant_FeeNeverExceedsConfiguredMaximum`
- `invariant_ComplianceRemainsMandatory` (mirrors the existing
  `invariant_UncompliantWalletStillRejected` pattern for pools)

## 20. Future RWA compatibility

Not implemented in this milestone, per instruction. The
`IBitVVaultStrategy` interface (§6) is intentionally minimal
(`deposit`/`withdraw`/`totalAssets`/`emergencyWithdraw`) specifically so
a future verified-RWA strategy could implement the same interface
without requiring changes to `BitVYieldVault` itself — the vault does
not need to know what a strategy invests in, only that it satisfies the
interface's accounting contract. Any future RWA strategy would need its
own dedicated specification (asset verification requirements, likely
CVA integration per §10's dependency description, redemption liquidity
characteristics specific to RWA) before implementation — this milestone
does not attempt to anticipate those details beyond keeping the
interface boundary clean.

## 21. Open questions

1. **Decimal offset value**: what specific `_decimalsOffset()` should
   BitV standardize on across all vaults? OpenZeppelin's own
   documentation discusses the tradeoff; this specification recommends
   a non-zero value but leaves the exact constant to be settled during
   implementation with accompanying inflation-attack test evidence.
2. **Per-vault vs. shared compliance rule**: should every vault
   register its own independent `RuleV2`, or should vaults for the same
   underlying asset's ecosystem share a rule with that asset's lending
   pool? Left as an operational (not architectural) decision.
3. **Should `emergencyWithdraw` be forced to socialize strategy losses
   pro-rata, or first-come-first-served?** This specification assumes
   pro-rata (consistent with ERC-4626's share-based accounting
   throughout), but a first-come-first-served emergency path is a
   simpler implementation that trades fairness for urgency — worth an
   explicit decision before implementation, not an implicit one.
4. **Multi-strategy vaults**: this specification assumes one active
   strategy per vault at a time. A future milestone could consider
   multiple concurrent strategies with per-strategy allocation splits —
   not needed for the MVP and adds meaningful complexity to the
   allocation-cap and emergency-exit logic.
5. **Vault-to-pool integration (§16 option B)**: left as a possible,
   not decided, future direction — needs its own specification and
   integration-invariant test suite before being pursued, not a default
   next step.
6. **Should performance fees be assessed continuously (high-water-mark
   style) or only at withdrawal?** Continuous accrual is simpler to
   reason about for `totalAssets()` transparency but needs a defined
   "high water mark" concept to avoid charging fees on a loss-then-
   recovery cycle that never actually profited the user net; this
   specification leaves the exact mechanism to implementation-time
   design, flagging only that a naive "fee on every totalAssets()
   increase" would double-charge across a dip-and-recover cycle.
