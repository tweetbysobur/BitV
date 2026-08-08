# Contract Integration

How the BitV frontend talks to the on-chain protocol: deployment status,
addresses, ABI management, and the read/write flow behind every contract
interaction in the app.

For contract *design* — why the interest index is unified, storage layout,
the security model — see [`contracts-architecture.md`](./contracts-architecture.md).
This document is the frontend's view: what's deployed, where, and how the
integration layer consumes it.

---

## 1. Deployment status

**The protocol has not been deployed to any network.** `contracts/` compiles
and passes its full test suite (47 tests, including a 4,096-call solvency
invariant — see `contracts-architecture.md` §7), but no deployment has been
broadcast. There are no addresses to publish yet, and every table below is
the *shape* the integration expects once there are.

This is a real, representable state in the frontend, not an oversight to
paper over. `src/config/contracts.ts` exposes `isProtocolDeployed(chainId)`,
and every contract-reading hook checks it before issuing a call. When
addresses are unset, the UI renders an explicit "Protocol not deployed" card
(`src/components/web3/protocol-gate.tsx`) naming exactly which env vars are
missing — never a page that silently shows zero balances, which would be
indistinguishable from a real empty portfolio.

### Deploying

```bash
cd contracts
cp .env.example .env        # set DEPLOYER_PRIVATE_KEY and MONAD_TESTNET_RPC_URL
forge script script/Deploy.s.sol \
  --rpc-url monad_testnet \
  --broadcast \
  --verify
```

The deployer key must hold testnet MON for gas. See `contracts/script/Deploy.s.sol`
for the exact deployment order (`ProtocolRegistry` → `AccessManager` →
`BitScoreManager` → `Treasury` → `PoolManager` → `LendingManager` →
`VaultManager` → wiring) — `contracts-architecture.md` §6 documents why that
order is load-bearing, not arbitrary.

After deploying:

1. Copy each address from `contracts/broadcast/Deploy.s.sol/10143/run-latest.json`
   into the frontend's `.env.local` (see §2 below for the exact variable names).
2. Create at least one pool: `PoolManager.createPool(asset, rateModel, reserveFactorBps, supplyCap, validatorPool)`.
3. Set `NEXT_PUBLIC_BITV_MARKET_ASSETS` to that asset's `symbol:address:decimals`.
4. Run `npm run contracts:build` to regenerate ABIs against the deployed bytecode.

---

## 2. Contract addresses

Populated in `.env.local`, read by `src/config/contracts.ts`. All are public
on-chain addresses — the `NEXT_PUBLIC_` prefix is correct and intentional,
not an oversight (contrast with `CLEANVERSE_API_KEY`, which must never carry
that prefix; see `cleanverse-integration.md` §1).

| Env var | Contract | Required |
| --- | --- | --- |
| `NEXT_PUBLIC_BITV_REGISTRY_ADDRESS` | `ProtocolRegistry` | For completeness; the frontend does not call it directly |
| `NEXT_PUBLIC_BITV_ACCESS_MANAGER_ADDRESS` | `AccessManager` | For completeness; capability checks happen inside the other managers |
| `NEXT_PUBLIC_BITV_POOL_MANAGER_ADDRESS` | `PoolManager` | **Yes** |
| `NEXT_PUBLIC_BITV_LENDING_MANAGER_ADDRESS` | `LendingManager` | **Yes** |
| `NEXT_PUBLIC_BITV_VAULT_MANAGER_ADDRESS` | `VaultManager` | **Yes** |
| `NEXT_PUBLIC_BITV_BITSCORE_MANAGER_ADDRESS` | `BitScoreManager` | **Yes** |
| `NEXT_PUBLIC_BITV_TREASURY_ADDRESS` | `Treasury` | **Yes** |
| `NEXT_PUBLIC_BITV_PRICE_ORACLE_ADDRESS` | `StaticPriceOracle` (or its production replacement) | For completeness; not read directly by the frontend |

`isProtocolDeployed()` requires the five **Yes** rows. The other three are
recorded for operational completeness (e.g. linking to them on an explorer)
but nothing in the UI calls them directly.

Two more env vars complete market discovery — see `.env.example` for the
full format:

```bash
# symbol:address:decimals, comma-separated
NEXT_PUBLIC_BITV_MARKET_ASSETS="USDC:0x...:6,WETH:0x...:18"

# bytes32 vault ids, comma-separated — see §5 for why these are
# configured rather than enumerated on-chain
NEXT_PUBLIC_BITV_VAULT_IDS="0xabc...,0xdef..."
```

---

## 3. ABI management

ABIs are **generated**, not hand-maintained. `scripts/extract-abis.mjs` pulls
each contract's ABI from its Foundry build artifact (`contracts/out/`) into
`src/lib/contracts/abis/*.ts`, `as const`-asserted so wagmi/viem infer every
function's argument and return types directly from the ABI.

```bash
npm run contracts:build   # forge build && npm run abis
npm run abis               # regenerate only (artifacts must already exist)
```

Ten contracts are extracted — every one the frontend calls, explicitly
listed in the script rather than globbed, so vendored OpenZeppelin bases,
tests, and mocks in `contracts/out/` never leak into the client bundle:
`PoolManager`, `LendingManager`, `VaultManager`, `BitScoreManager`,
`Treasury`, `AccessManager`, `ProtocolRegistry`, `BitVReceiptToken`,
`StaticPriceOracle`, `KinkedInterestRateModel`.

**Never hand-edit a file under `src/lib/contracts/abis/`.** Every file
starts with an auto-generated banner; regenerate after any contract change
via `npm run contracts:build`, then re-run `npm run typecheck` — a changed
function signature becomes a compile error at every call site immediately,
which is the entire reason this is generated rather than copied by hand.

---

## 4. Architecture

```
src/
├─ config/
│  └─ contracts.ts             Addresses, deployment-state checks, market asset list
├─ lib/contracts/
│  ├─ abis/                    AUTO-GENERATED — see §3
│  ├─ types.ts                 Domain types: PoolData, UserMarketPosition, BitScoreData, VaultData…
│  ├─ math.ts                  WAD/RAY fixed-point math mirroring the Solidity libraries exactly
│  └─ errors.ts                Revert → user-facing message mapping
├─ hooks/contracts/
│  ├─ use-protocol-status.ts   The gate every other hook checks first
│  ├─ use-pools.ts             PoolManager state, Multicall-batched
│  ├─ use-borrow-configs.ts    LendingManager risk parameters (LTV, liquidation threshold…)
│  ├─ use-lending-position.ts  Account-level collateral/debt/health factor
│  ├─ use-bitscore.ts          BitScoreManager + Cleanverse identity tier → credit line
│  ├─ use-vaults.ts            VaultManager state + user share positions
│  ├─ use-transaction-history.ts   Event-log-derived activity (no indexer yet — see §7)
│  └─ use-protocol-write.ts    The transaction lifecycle — see §6
├─ components/web3/
│  ├─ protocol-gate.tsx        Renders the not-deployed / wrong-network / no-markets states
│  ├─ transaction-dialog.tsx   Confirm → sign → pending → success/error, one component
│  └─ amount-input.tsx         Token amount input with exact-balance Max button
└─ features/
   ├─ lending/                 SupplyPanel, BorrowPanel, metrics
   ├─ pools/                   PoolMetrics (SupplyPanel is shared — pools ARE supply)
   ├─ vaults/                  VaultPanel, metrics
   └─ portfolio/                PortfolioOverview, BitScoreView, ProtocolStats, live activity feed
```

### Why `bigint` everywhere

Every on-chain amount is a raw `bigint` in the asset's own decimals, from the
RPC boundary to the render boundary. `lib/contracts/math.ts` reimplements
the contracts' `WadRayMath`/`PercentageMath` in `bigint` space — including
matching their round-to-nearest behaviour exactly, not truncation — so a
value the UI derives (a pool's `totalSupplied`, a position's current debt)
never disagrees with what the contract itself would compute. `Number()`
appears nowhere in this path: 18-decimal token amounts routinely exceed
`Number.MAX_SAFE_INTEGER`, and a single silent float conversion is how a
displayed balance quietly stops matching the chain.

### Why reads are batched

`useReadContracts` routes through Multicall3 (configured on `monadTestnet` in
`config/chains.ts`). A single lending position read is `4n + 2` contract
calls (per-market aToken balance, debt, collateral, wallet balance, plus
account-level health factor and borrowing power) — unbatched, that's a
double-digit round trip count on a page load, visibly slow and enough to hit
public RPC rate limits. Multicall collapses it into one request.

---

## 5. Contract interaction flows

### Lending — supply / withdraw (`PoolManager`)

`src/features/lending/supply-panel.tsx` — shared between the Lending and
Liquidity Pools pages, because supplying liquidity **is** joining a pool in
this protocol; there is no separate AMM-pool contract.

```
supply:    ERC20.approve(PoolManager, amount)  [only if allowance insufficient]
        →  PoolManager.supply(asset, amount)

withdraw:  PoolManager.withdraw(asset, amount)   [no approval — burns caller's own aToken]
```

### Borrowing — collateral, borrow, repay, withdraw (`LendingManager`)

`src/features/lending/borrow-panel.tsx` — one panel, four actions, because
they share one position and one health factor.

```
deposit collateral:  ERC20.approve(LendingManager, amount)
                   →  LendingManager.depositCollateral(asset, amount)

borrow:               LendingManager.borrow(asset, amount)
                       [no approval — LendingManager sends the borrowed asset out]

repay:                ERC20.approve(LendingManager, amount)
                   →  LendingManager.repay(asset, amount, onBehalfOf)

withdraw collateral:  LendingManager.withdrawCollateral(asset, amount)
                       [reverts if it would drop health factor below 1.0 —
                        checked contract-side, not just in the UI]
```

A health-factor warning renders in `TransactionDialog` whenever a borrow or
collateral withdrawal would leave the position below 1.5 — *before* the
wallet prompt, so the user can reconsider the amount while it's still free
to change.

### Vaults — deposit / withdraw (`VaultManager`)

`src/features/vaults/vault-panel.tsx`.

```
deposit:   ERC20.approve(VaultManager, amount)
        →  VaultManager.deposit(vaultId, assets)

withdraw:  VaultManager.withdraw(vaultId, shares)
           [shares, not assets — see the panel's inline note on why the
            input unit changes between the two modes]
```

There is no "claim rewards" call: `VaultManager` has no separate reward
token or claim function. Yield arrives via `distributeRewards` (governance/
strategy-only) increasing `totalAssets`, which raises `pricePerShare` for
every holder automatically — "claiming" is simply withdrawing at the new,
higher price. The vault table shows price-per-share rather than an APY
figure for the same reason: there is no rate model to derive one from, and
back-computing an annualized rate from irregular distributions would present
a projection as a fact.

**Vault discovery.** `VaultManager` assigns each vault a `bytes32` id at
creation (`keccak256(asset, nonce)`) and exposes no on-chain enumeration —
maintaining an array of every vault ever created would be unbounded storage
growth for a contract that otherwise has none. The frontend discovers vaults
from `NEXT_PUBLIC_BITV_VAULT_IDS` (populated from the `VaultCreated` events
emitted by your creation transactions) rather than a getter. The documented
next step, once there's enough vault activity to justify it, is `getLogs`-
based discovery matching the pattern already used for transaction history
(§7) — no contract change required, only a frontend one.

### BitScore (`BitScoreManager`, read-only from the frontend)

`src/hooks/contracts/use-bitscore.ts`. There is no write path from the
frontend: `BitScoreManager.reportEvent` is called by `LendingManager`
itself, authorized as a reporter, after a repayment or liquidation — a
user's score changes as a *side effect* of their protocol activity, never as
a direct action they take. The credit line combines two independent reads:
`BitScoreManager.creditLimitUsd(account, identityTier)` where `identityTier`
comes from **Cleanverse** (`useIdentity()`), not from any BitV contract — see
`cleanverse-integration.md` for why identity and reputation are deliberately
separate systems.

### Treasury (read-only)

`src/features/portfolio/protocol-stats.tsx` reads `Treasury.reserveBalance(asset)`
per listed asset — there is no aggregate getter on-chain (an aggregate would
need a price oracle *inside* the treasury contract), so the frontend lists
reserves individually rather than summing incomparable token units into a
fabricated total.

---

## 6. Transaction lifecycle

Every write goes through `useProtocolWrite` (`src/hooks/contracts/use-protocol-write.ts`),
which is the single place this behaviour is implemented — no feature
reimplements simulate/approve/sign/confirm on its own.

```
idle → simulating → [awaiting-approval → approving] → signing → pending → confirming → success | error
```

1. **Approval** (only if needed): reads current `allowance` first and skips
   the approval transaction entirely when it's already sufficient. Approves
   the **exact amount**, never `type(uint256).max` — infinite approval is a
   materially different risk (a standing authorization over the user's whole
   balance) that should be the user's explicit choice, not this app's
   default.
2. **Simulate**: `publicClient.simulateContract` catches a doomed transaction
   *before* the wallet prompt — a revert surfaces as an inline dialog state,
   not as a signature request the user approves and then watches fail.
3. **Gas estimate**: `estimateContractGas` + `applyGasBuffer` (10%, defined
   in `config/chains.ts`). Monad prices gas on the **limit submitted**, not
   gas consumed — unlike most EVM chains, an over-padded limit here is money
   the user actually loses on every transaction, which is why the buffer is
   deliberately tight rather than generous.
4. **Sign**: `walletClient.writeContract`.
5. **Confirm**: `useWaitForTransactionReceipt`. A receipt with
   `status: 'reverted'` (mined but failed) is treated as a failure — wagmi
   reports that as a *successful query* since the receipt itself fetched
   fine, and conflating the two would tell a user their borrow succeeded
   when the chain rejected it.
6. **Invalidate**: on success, only the specific React Query keys the caller
   named (`queryKeys.pool.all`, `queryKeys.position.all`, …) — not the whole
   cache. A blanket invalidation makes the app feel slower after every
   transaction, not faster.

Errors are classified by `lib/contracts/errors.ts` into `user-rejected |
insufficient-funds | insufficient-gas | contract-revert | network | unknown`.
Every custom Solidity error declared in `contracts/src/libraries/Errors.sol`
has a mapped, plain-language explanation; an unmapped revert shows its raw
name rather than an invented explanation — a gap in that table should be
visible, not papered over with a guess.

---

## 7. What's not wired up, and why

**Transaction history and activity feeds read `getLogs` directly**, bounded
to a recent block window (`HISTORY_BLOCK_RANGE`, ~2 hours of blocks at
Monad's block time). This is a real, working implementation for a testnet
deployment — not a mock — but it has a stated ceiling: wide-range `getLogs`
is slow and most public RPCs cap the range. The correct backend for
production scale is an indexer (Envio HyperIndex, already referenced in
`.env.example` as `INDEXER_URL`); every hook in `hooks/contracts/` is
structured so swapping the data source there is a query-function change, not
a component rewrite.

**No portfolio value-over-time chart.** Charting requires historical
snapshots; the contracts store only current balances. Plotting a line
through a single current reading, or synthesizing history from it, would
present invented data as real — this resolves when the indexer lands.

**No USD-denominated totals outside the borrow/health-factor math that
already needs an oracle.** Metric cards that sum across assets (total
supplied, TVL) are shown as normalized 18-decimal *token-unit* totals, with
an explicit tooltip saying so — pricing every position would mean an oracle
read per asset per card, and mislabeling the result as dollars would be a
fabricated valuation with a confident-looking dollar sign on it.

**`StaticPriceOracle`** is exactly what its name says: a placeholder
returning governance-set prices, suitable for testnet and demonstration, not
mainnet. `contracts-architecture.md` §8 documents the real-oracle
replacement path (Chainlink/Pyth on Monad) as a pre-mainnet requirement.
