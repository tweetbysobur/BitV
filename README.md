# BitV

**The trust layer for DeFi.**

Identity-native DeFi on Monad Testnet, built on Cleanverse identity and
verified-asset infrastructure. Built by Gentlesoul Hub.

BitV combines an on-chain lending/borrowing engine, a risk-scoring layer
(BitScore), real-world-asset collateral support, and Cleanverse compliance
and verified-asset (CVA) integration, behind a single protocol dashboard.

## Status

Contracts and frontend are both implemented and under active development.
Nothing is deployed to a live network yet — see
[Deployment status](#deployment-status) below.

| Layer | State |
|---|---|
| Core pools, lending, liquidation | Implemented, tested |
| BitScore risk layer (0–100 scale) | Implemented, tested |
| ERC-4626 yield vaults | Implemented, tested |
| RWA collateral registry | Implemented, tested |
| Cleanverse CVI compliance | Integrated |
| Cleanverse CVA (verified assets) | Integrated (read-only; transfer enforcement not implemented) |
| Protocol dashboard (frontend) | Implemented |

See [`docs/development-log.md`](docs/development-log.md) for the full,
dated build history and [`docs/architecture.md`](docs/architecture.md) for
how the repo is laid out.

## Repository structure

```
contracts/    Solidity source (Foundry) — pools, lending, BitScore, vaults,
              RWA registry, CVA adapter, compliance guard
app/          Next.js App Router pages, including /dashboard
components/   React UI components (shared + dashboard-specific)
hooks/        Client hooks bridging UI to contract reads
services/     Contract ABIs, addresses, typed contract layer
lib/          Framework-agnostic pure logic (formatting, BitScore tiers,
              health-factor math, CVI/CVA status derivation)
config/       Chain/wallet configuration (Monad Testnet, wagmi/RainbowKit)
tests/        Vitest unit tests for the frontend's pure logic
docs/         Architecture notes, compliance docs, development log
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
  accrual, health-factor-based liquidation.
- **BitScore** — an on-chain, 0–100 risk score with four tiers (Restricted,
  Standard, Established, Trusted) that adjusts borrowing terms.
- **Yield vaults** — permissioned ERC-4626 vaults with a pluggable strategy
  interface; the only strategy implemented so far (`TestYieldStrategy`) is
  explicitly non-production and labeled as such everywhere it's shown.
- **RWA collateral registry** — a separate registry for real-world-asset
  collateral, with its own LTV/liquidation-threshold/caps configuration per
  asset.
- **Cleanverse integration** — CVI (identity/compliance verification) and
  CVA (verified-asset recognition) are deliberately kept separate end to
  end, in contracts, hooks, and UI. BitV's CVA checks confirm that an
  asset's configured contract responds the way a CVA policy contract is
  expected to — they do not assert that Cleanverse has approved the asset,
  since no on-chain query for that fact exists yet.
- **Dashboard** — `/dashboard/*` reads all of the above through a layered
  `UI → hooks → services/contracts → chain` data path, using multicall
  batched reads and an explicit loading/loaded/empty/unavailable/error
  state for every contract-backed section. It never fabricates balances,
  scores, health factors, or activity — unavailable data is shown as
  "Unavailable," not zero.

## Deployment status

No BitV contracts are deployed to any network, testnet or mainnet. The
frontend's contract address registries (`services/contracts/addresses.ts`)
are intentionally empty until real deployments exist, so the dashboard
currently renders its empty/unavailable states by design. Monad Testnet is
the only network BitV targets; mainnet is not supported or implied anywhere
in the app.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — repository and system
  architecture
- [`docs/development-log.md`](docs/development-log.md) — full milestone-by-
  milestone build history
- [`docs/dashboard-implementation.md`](docs/dashboard-implementation.md) —
  dashboard data flow, component structure, and known limitations
- Additional design/compliance docs under [`docs/`](docs/)

## Contributing

This is currently developed as a single continuous build history (see the
development log). If you're picking up work here, read the relevant
milestone entries first — the log documents intentional constraints (e.g.
CVI/CVA separation, BitScore's 0–100 scale, no fabricated dashboard data)
that later work is expected to preserve.
