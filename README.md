# BitV

**The trust layer for DeFi.**

Identity-native DeFi on Monad Testnet, built on Cleanverse identity and
verified-asset infrastructure.

**Live app:** [bitvapp.vercel.app](https://bitvapp.vercel.app)

BitV combines an on-chain lending/borrowing engine, a risk-scoring layer
(BitScore), real-world-asset collateral support, and Cleanverse compliance
and verified-asset (CVA) integration, behind a single protocol dashboard.

## Status

Deployed and live on Monad Testnet (chain ID 10143). Contracts and
frontend are both implemented, Foundry-tested (240/240 passing), and
exercised end-to-end against real testnet transactions — see
[Deployment status](#deployment-status) below.

| Layer | State |
|---|---|
| Core pools, lending, liquidation | Deployed, live, tested |
| BitScore risk layer (0–100 scale) | Deployed, live, tested |
| ERC-4626 yield vaults | Deployed, live, tested (test strategy — see below) |
| RWA collateral registry | Deployed, live, tested |
| Cleanverse CVI compliance | Integrated, live-verified on Monad Testnet |
| Cleanverse CVA (verified assets) | Integrated (read-only; transfer enforcement not implemented) |
| Treasury reserve-claim | Implemented, Foundry-tested — **not yet on the live deployment** (predates this feature; redeploy required) |
| Protocol dashboard (frontend) | Deployed at [bitvapp.vercel.app](https://bitvapp.vercel.app) |

See [`docs/development-log.md`](docs/development-log.md) for the full,
dated build history and [`docs/architecture.md`](docs/architecture.md) for
how the repo is laid out.

## Repository structure

```
contracts/    Solidity source (Foundry) — pools, lending, BitScore, vaults,
              RWA registry, CVA adapter, compliance guard
app/          Next.js App Router pages, including /dashboard
components/   React UI components (shared + dashboard-specific)
hooks/        Client hooks bridging UI to contract reads and writes
services/     Contract ABIs, deployed addresses, typed contract layer
lib/          Framework-agnostic pure logic (formatting, BitScore tiers,
              health-factor math, CVI/CVA status derivation)
config/       Chain/wallet configuration (Monad Testnet, wagmi/RainbowKit)
tests/        Vitest unit tests for the frontend's pure logic
docs/         Architecture notes, compliance docs, deployment records,
              development log
```

## Getting started

### Frontend

```bash
cp .env.example .env.local   # fill in the values you have
npm install
npm run dev
```

Useful scripts:

```bash
npm run lint     # ESLint
npm run build    # production build
npm run test     # Vitest unit tests
```

### Contracts

```bash
cd contracts
forge install
forge build
forge test
```

Invariant and unit suites live under `contracts/test/`. All contract logic
is developed and verified with Foundry before any frontend integration is
written against it.

## Architecture at a glance

- **Lending core** — pooled supply/borrow per asset, ray-scaled interest
  accrual, health-factor-based liquidation. Real supply, collateral,
  borrow, repay, and withdraw actions are wired end-to-end in the
  dashboard, not just readable.
- **BitScore** — an on-chain, 0–100 risk score with four tiers (Restricted,
  Standard, Established, Trusted) that adjusts borrowing terms.
- **Yield vaults** — permissioned ERC-4626 vaults with a pluggable strategy
  interface; the only strategy deployed so far (`TestYieldStrategy`) is
  explicitly non-production and labeled as such everywhere it's shown —
  never presented as real yield.
- **RWA collateral registry** — a separate registry for real-world-asset
  collateral, with its own LTV/liquidation-threshold/caps configuration per
  asset, plus live oracle price/freshness display.
- **Cleanverse integration** — CVI (identity/compliance verification) and
  CVA (verified-asset recognition) are deliberately kept separate end to
  end, in contracts, hooks, and UI. Every compliance-gated contract calls
  Cleanverse's `IAPassComplianceValidator.complianceVerify` as the first
  check before any protected action. BitV's CVA checks confirm that an
  asset's configured contract responds the way a CVA policy contract is
  expected to — they do not assert that Cleanverse has approved the asset,
  since no on-chain query for that fact exists yet. BitV never displays
  "Cleanverse approved/certified" anywhere.
- **Dashboard** — `/dashboard/*` reads all of the above through a layered
  `UI → hooks → services/contracts → chain` data path, using multicall
  batched reads and an explicit loading/loaded/empty/unavailable/error
  state for every contract-backed section, plus a full idle → pending →
  confirming → confirmed/failed state machine for every write
  transaction. It never fabricates balances, scores, health factors, or
  activity — unavailable data is shown as "Unavailable," not zero.

## Deployment status

Deployed and live on **Monad Testnet (chain ID 10143)**. Real addresses
are recorded in `services/contracts/addresses.ts` and
[`docs/deployment-addresses-template.md`](docs/deployment-addresses-template.md)
(deployer, transaction hashes, `ValidateDeployment.s.sol` results). A full
supply → collateral → borrow → repay → withdraw journey, plus yield vault
deposit/withdraw, RWA registration, and liquidation, has been exercised
against real testnet transactions — see
[`docs/testnet-smoke-test.md`](docs/testnet-smoke-test.md) for the
recorded results.

**Known gap:** the currently deployed `PoolManager`/`Treasury` predate the
reserve-claim feature — that one admin-only feature is Foundry-tested but
not yet live on testnet; the dashboard reports it as unavailable rather
than pretending it works. Everything else in the table above is deployed
and functioning on the live contracts the frontend reads.

Mainnet is not supported or implied anywhere in the app. Every testnet
asset (BVTEST) and oracle (`StaticPriceOracle`) is clearly labeled as
non-production, no-real-value throughout the UI.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — repository and system
  architecture
- [`docs/development-log.md`](docs/development-log.md) — full milestone-by-
  milestone build history
- [`docs/dashboard-implementation.md`](docs/dashboard-implementation.md) —
  dashboard data flow, component structure, and known limitations
- [`docs/deployment-addresses-template.md`](docs/deployment-addresses-template.md) —
  live Monad Testnet contract addresses and deployment record
- [`docs/testnet-smoke-test.md`](docs/testnet-smoke-test.md) — recorded
  end-to-end live testnet verification results
- [`docs/cleanverse-dependency-lock.md`](docs/cleanverse-dependency-lock.md) —
  exactly what's confirmed vs. unconfirmed about the Cleanverse integration
- Additional design/compliance docs under [`docs/`](docs/)

## Contributing

This is currently developed as a single continuous build history (see the
development log). If you're picking up work here, read the relevant
milestone entries first — the log documents intentional constraints (e.g.
CVI/CVA separation, BitScore's 0–100 scale, no fabricated dashboard data)
that later work is expected to preserve.
