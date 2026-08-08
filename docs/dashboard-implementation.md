# BitV Protocol Dashboard + Risk Intelligence (Build 08)

Implements the product dashboard described in Build 08 exactly. No
Cleanverse CVA interface was modified, `canTransfer` was not
implemented, no economic logic was touched, and nothing was deployed —
the dashboard is a read-only presentation layer over the existing
protocol.

## Dashboard architecture

Follows the existing, required layering exactly:

```
UI (app/dashboard/**, components/dashboard/**)
  ↓
hooks (hooks/use*.ts) — one hook per data need, always returning DataState<T>
  ↓
services/contracts (abis/, addresses.ts, types.ts) — typed ABI + address registry
  ↓
wagmi (useReadContract / useReadContracts) → viem → Monad Testnet RPC
```

No component imports `viem`/`wagmi` contract-call primitives directly
against a raw address/ABI — every read goes through a `hooks/use*.ts`
function, which itself only ever reads from `services/contracts/`. No
third-party blockchain SDK is imported into a UI component.

**Multicall/batching**: every hook that reads more than one value uses
wagmi's `useReadContracts` (Multicall3-batched under the hood) rather
than issuing N separate `useReadContract` calls — see
`useLendingPosition`, `useBitScore`, `useRWAAssets`, `useVaultPositions`,
`usePoolPositions`.

## Routes

`app/dashboard/{overview,lending,vaults,rwa,pools,risk,activity,settings}/page.tsx`,
plus `app/dashboard/layout.tsx` (wraps every route in `DashboardShell`)
and `app/dashboard/page.tsx` (redirects to `/dashboard/overview`, the
main entry point). All are dynamically rendered — the wallet connection
required to show any real data cannot be known at build time, and
`app/layout.tsx`'s existing `export const dynamic = "force-dynamic"`
was left untouched (still load-bearing for the same reason it was
before this build: `Web3Provider` needs `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`
at render time, not build time).

## Data sources

Every contract-backed value traces to one of:

- `services/contracts/addresses.ts` — `contractAddresses` (per-contract-
  name address registry, **empty**, no address deployed anywhere yet),
  `yieldVaults`/`rwaAssets`/`poolAssets` (per-instance registries, also
  **empty**). Every hook checks these before attempting a read; an
  empty/missing entry produces `DataState` `unavailable` or `empty`
  (never a fabricated zero).
- `services/contracts/abis/*.ts` — hand-transcribed, `as const` ABI
  fragments for `BitVPoolManager`, `BitVLendingManager`,
  `BitScoreManager`, `BitVYieldVault` (ERC-4626 + BitV additions),
  `BitVRWACollateralRegistry`, `BitVCVAAdapter`,
  `IAPassComplianceValidator` (Cleanverse), and a minimal standard
  ERC-20 fragment. Every function signature was transcribed directly
  from `contracts/src/**/*.sol` (BitV's own, already-audited-by-tests
  Solidity) — not guessed, not sourced from any Cleanverse
  documentation beyond what `IAPassComplianceValidator.sol` already
  confirms.
- `config/chains.ts`/`config/wagmi.ts`/`config/cleanverse.ts` —
  unchanged from the existing architecture; the dashboard reuses the
  existing `Web3Provider` (`components/providers/web3-provider.tsx`)
  and does not create a second wallet provider.

**No contract is deployed anywhere**, so every dashboard section
currently renders its `unavailable`/`empty` state in practice — this is
correct, expected behavior per the task's explicit instruction to
reflect real contract state, not to fabricate data to make the
dashboard look populated.

## Contract reads (exact functions used)

| Domain | Contract | Functions read |
|---|---|---|
| CVI | `IAPassComplianceValidator` (Cleanverse) | `complianceVerify(poolAddress, userAddress)` |
| BitScore | `BitScoreManager` | `getScore`, `getTier` |
| Lending | `BitVLendingManager` | `getUserAccountData`, `getUserAccountDataForBorrow`, `getEffectiveAvailableBorrowValue`, `getCollateralBalance`, `getCurrentDebt` |
| Pools | `BitVPoolManager` | `getPool`, `totalSupplied`, `totalBorrowed`, `availableLiquidity`, `utilizationRay`, `balanceOf` |
| RWA | `BitVRWACollateralRegistry` | `getAssetConfig`, `isEligibleForNewActivity`, `isCVAAdminAttested`, `isCVAInterfaceVerified` |
| CVA | `BitVCVAAdapter` | (read indirectly via the registry's `isCVAInterfaceVerified`, which itself calls `isRecognizedCVA`) |
| Vaults | `BitVYieldVault` | `asset`, `balanceOf`, `totalAssets`, `strategy`, `depositsPaused`, `withdrawalsPaused`, `performanceFeeBps` |
| Token metadata | ERC-20 | `symbol`, `decimals` |

`BitVCVAAdapter.previewTransfer` is **not called anywhere** — it always
reverts on-chain (per Build 07.1's own design, since Cleanverse's
`canTransfer` return/rejection behavior is unconfirmed) and is
deliberately excluded from `bitVCVAAdapterAbi`.

## Component structure

`components/dashboard/`: `DashboardShell`, `Sidebar` (+ exported
`NavLinks` reused by the mobile menu), `Topbar`, `WalletStatus`,
`CVIStatus`, `BitScoreCard`, `RiskTierBadge`, `HealthFactorCard`,
`CollateralTable` (+ `DebtTable`, a thin wrapper reusing the same
rendering logic), `BorrowingCapacityCard`, `RWAStatusCard`,
`VaultPositionCard`, `PoolPositionCard`, `ActivityTable`,
`ProtocolAlert`, `EmptyState`, `ErrorState` (+ `UnavailableState`),
`LoadingState`, `DataStateView` (the shared dispatcher between all
five). `components/ui/`: `Card`, `Badge`, `Table` — minimal, hand-built
primitives (shadcn/ui was configured via `components.json` but had no
generated components yet; these follow the same conventions —
`cn()`-based class merging, CSS-variable-driven tokens — so a future
`shadcn add` can coexist).

## Loading/error behavior

Every contract-backed section's hook returns `DataState<T>` (`lib/data-state.ts`):
`loading | loaded | empty | unavailable | error`. `DataStateView`
(`components/dashboard/DataStateView.tsx`) is the single place that
renders each of the five — no page or card hand-rolls its own
loading/error branching, so no section can silently look successful
while data is missing, loading, or failed to read. `unavailable` (no
data source configured — missing address, wallet disconnected) is kept
visually and semantically distinct from `error` (a real read failure)
and from `empty` (a real, meaningful zero-result, e.g. a wallet with
genuinely zero registered RWA assets to show).

## CVI handling

`hooks/useCVIStatus.ts` reads `complianceVerify(poolAddress, userAddress)`
against the configured Cleanverse validator
(`NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS`, currently unset/
unconfirmed). `lib/cvi.ts`'s `deriveCVIStatus` is a pure function
(tested directly, `tests/cvi.test.ts`) mapping wallet-connected +
validator-configured + read-result + read-error into exactly the three
states the task requires: `verified`, `not-verified`, `unavailable`.
Never conflated with CVA status — `CVIStatus.tsx` and `RWAStatusCard.tsx`
(which shows CVA) are separate components reading separate hooks.

## CVA handling

`hooks/useCVAStatus.ts` reads the registry's two independent flags
(`isCVAAdminAttested`, `isCVAInterfaceVerified`) for one asset.
`lib/cva.ts`'s `deriveCVALabel` (pure, tested in `tests/cva.test.ts`)
produces one of four labels — `"Fully recognized (BitV verification
only)"`, `"Admin attested — interface not verified"`, `"Interface
verified — not admin attested"`, `"Not attested as CVA"` — and every
label, plus the `CVA_RECOGNITION_DISCLAIMER` constant rendered
alongside it in `RWAStatusCard`, is written to never claim "Cleanverse
approved." This mirrors `docs/cva-integration-specification.md` §7's
own discipline exactly: BitV verification confirms interface-shape
behavior, never Cleanverse's off-chain approval.

## BitScore display

`hooks/useBitScore.ts` reads `getScore`/`getTier` (both `uint8`,
0–100/0–3) — the **current** scale, matching `BitScoreManager.sol`
exactly. `lib/bitscore.ts` maps both the raw score and the tier index
to the four confirmed tier labels (Restricted/Standard/Established/
Trusted, 0–24/25–49/50–74/75–100) and throws on any out-of-range input
(0–100 only — a value in the legacy 0–1000 range would deliberately
fail loudly, not silently render). Internal scoring implementation
(decay accumulators, per-event point deltas, liquidation-penalty
bookkeeping) is not exposed — only score, tier, and (where available)
the BitScore-adjusted vs. base borrowing capacity comparison
(`BorrowingCapacityCard`).

## RWA display

`hooks/useRWAAssets.ts` reads `getAssetConfig` + `isEligibleForNewActivity`
per configured RWA asset (`services/contracts/addresses.ts`'s
`rwaAssets`, empty until real assets are registered). `lib/rwa.ts`
maps the on-chain `AssetStatus` enum (0–3) to
Unregistered/Active/Frozen/Delisted and describes exactly what each
status means for *new* activity, matching
`docs/rwa-market-implementation.md`'s frozen/delisted table (repayment/
withdrawal/liquidation always remain available regardless of status —
this dashboard does not claim otherwise).

## Known limitations

- **No contract is deployed anywhere** — every dashboard section
  currently shows its `unavailable`/`empty` state in practice, by
  design; this will change automatically once
  `services/contracts/addresses.ts` is populated with real, confirmed
  deployment addresses.
- **No activity indexer exists** — `hooks/useActivity.ts` always
  returns `unavailable` with an explicit explanation, per the task's
  instruction not to fabricate history. Wiring this up requires a real
  log-scanning service or subgraph, out of scope for this milestone.
- **`isTestStrategy` (vault pages) has no on-chain source** —
  `TestYieldStrategy` exposes no distinguishing on-chain flag; this
  label is sourced entirely from BitV's own static deployment registry
  (`services/contracts/addresses.ts`'s `yieldVaults`), never inferred.
- **`maxWithdraw`/`maxRedeem`-derived "withdrawal status" is not
  separately surfaced** beyond the vault's `withdrawalsPaused` flag —
  matches `docs/yield-vault-implementation.md`'s own documented
  limitation that these aren't overridden for real-time liquidity
  signaling; the dashboard doesn't claim more precision than the
  contract itself provides.
- **Protocol Alerts / Risk restriction feeds are placeholders showing
  "Unavailable"** — no protocol-wide alert or restriction-event source
  exists yet; nothing is fabricated to fill this.
- **Build produces pre-existing, unrelated warnings** from RainbowKit's
  optional peer dependencies (`@react-native-async-storage/async-storage`
  via `@metamask/sdk`, `pino-pretty` via WalletConnect's logger) — both
  are optional dependencies of third-party wallet-connector libraries,
  irrelevant to a web deployment, and were not introduced or modified
  by this milestone.
- **No `symbol`/`decimals` resolution for vault underlying assets yet**
  (`VaultPositionRow.underlyingSymbol` is always `undefined`) — would
  require a second batched read keyed off the on-chain-reported
  `underlyingAsset` address, not implemented this milestone to keep the
  vault hook's shape simple while no real vault exists to test it
  against.

## Tests

`tests/*.test.ts` (Vitest, newly introduced — no test framework existed
before this milestone): `bitscore.test.ts`, `health-factor.test.ts`,
`cvi.test.ts`, `cva.test.ts`, `rwa.test.ts`, `network.test.ts`,
`positions.test.ts` (multi-asset collateral/debt rendering),
`data-state.test.ts`, `vault.test.ts` — 41 tests total, all pure-logic
(no DOM rendering, no wagmi mocking required), covering every item the
task's TESTING section lists. A real, non-hypothetical bug was found
and fixed during this test-writing process (see the development log's
entry and `lib/health-factor.ts`'s own inline documentation): converting
a ray-scaled (1e27) `bigint` through `Number()` silently loses precision
past `Number.MAX_SAFE_INTEGER`, which could flip a health-factor status
right at an exact threshold boundary (e.g. exactly 1.5x reporting as
"warning" instead of "healthy"). Fixed by keeping all health-factor
threshold comparisons and formatting in pure `bigint` arithmetic.
