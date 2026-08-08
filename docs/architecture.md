# BitV Architecture

## Summary

BitV is an identity-native DeFi protocol on Monad Testnet, built on
Cleanverse identity and verified-asset infrastructure. The protocol has two
halves: a Foundry Solidity workspace (`contracts/`) implementing pooled
lending, a risk-scoring layer, ERC-4626 yield vaults, an RWA collateral
registry, and Cleanverse compliance/CVA integration; and a Next.js frontend
that reads that state through a strictly layered data path and never
fabricates values it can't read on-chain.

## Contracts (`contracts/`)

```
contracts/src/
  core/          BitVPoolManager, BitVLendingManager, BitScoreManager,
                 BitVYieldVault, BitVRWACollateralRegistry, BitVCVAAdapter,
                 BitVTreasury, BitVVaultManager, BitVAccessManager
  compliance/    BitVComplianceGuard
  access/        BitVRoleConsumer
  oracles/       StaticPriceOracle, KinkedInterestRateModel
  vault/         TestYieldStrategy (non-production reference strategy)
  interfaces/    Protocol interfaces + external/ (Cleanverse-facing:
                 IAPassComplianceValidator, IATokenPolicy)
  libraries/     DataTypes, WadRayMath, PercentageMath, per-domain error libs
contracts/test/  Unit suites per contract + invariant/ (protocol-wide
                 invariant tests: core, RWA, vault, CVA)
```

Key design points:

- **Ray-scaled math** (`WadRayMath`, 1e27 precision) throughout interest
  accrual, health factors, and utilization — never floating point.
- **BitScore** is a 0–100 on-chain score with four tiers (Restricted 0–24,
  Standard 25–49, Established 50–74, Trusted 75–100) that adjusts borrowing
  terms via `BitScoreManager`.
- **RWA collateral** is tracked in a registry separate from the core pool
  logic, with its own per-asset LTV, liquidation threshold, and cap, wired
  into lending through an optional interface so core lending logic doesn't
  hard-depend on RWA existing.
- **CVA (Cleanverse Verified Asset) integration** (`BitVCVAAdapter`,
  `IBitVCVAAdapter`, `IATokenPolicy`) is read-only recognition/policy
  checking. `previewTransfer` is intentionally unimplemented and always
  reverts — Cleanverse's `canTransfer` signature is not yet confirmed, and
  BitV does not guess at external interfaces it hasn't verified.
- **Compliance (CVI)** goes through `BitVComplianceGuard` and Cleanverse's
  `IAPassComplianceValidator`, and is kept structurally separate from CVA
  everywhere — a verified identity says nothing about an asset being a
  recognized CVA, and vice versa.
- Every economic/compliance/RWA/vault domain has both unit tests and a
  dedicated Foundry invariant suite under `test/invariant/`.

## Frontend (`app/`, `components/`, `hooks/`, `services/`, `lib/`)

```
app/            Next.js App Router — routes, layouts, pages (UI only)
                includes app/dashboard/* — the protocol dashboard
components/     components/ui = shared primitives (shadcn-derived);
                components/dashboard = dashboard-specific components
hooks/          Client hooks — the only place UI is allowed to call
                wagmi's useReadContracts; one hook per data domain
                (wallet status, BitScore, lending position, CVI, CVA,
                RWA assets, vault positions, pool positions, activity)
services/contracts/
                abis/       hand-transcribed viem-style ABIs, sourced
                            directly from contracts/src/**/*.sol
                addresses.ts static registries: contractAddresses,
                            yieldVaults, rwaAssets, poolAssets — all
                            empty until BitV deploys and confirms them
                types.ts    shared contract-layer types
lib/            Framework-agnostic pure logic: DataState<T> union,
                formatting, BitScore tier mapping, health-factor math,
                CVI/CVA status derivation, wallet-network state
config/         Chain definitions (Monad Testnet only) and
                wagmi/RainbowKit wallet configuration
tests/          Vitest unit tests over lib/ (pure functions only)
```

Data flow is strictly one-directional:

```
UI component → hook (hooks/use*.ts) → services/contracts (abis + addresses)
             → wagmi/viem → Monad Testnet RPC
```

No component imports a blockchain SDK or ABI directly. Every contract-backed
hook returns a `DataState<T>` (`loading | loaded | empty | unavailable |
error`) rather than a bare value, so the UI can never render as if data
loaded when it didn't — an "Unavailable" state is shown instead of
substituting zero.

## Principles enforced across the codebase

- The frontend never fabricates balances, transactions, scores, health
  factors, or protocol statistics. If a contract read fails or a registry
  entry doesn't exist, the UI shows "Unavailable" / "Not connected" /
  "Loading" / an empty state — never a fake number.
- CVI (compliance) and CVA (verified-asset) status are never merged into a
  single "verified" concept, in contracts, hooks, or components.
- BitScore is always treated as 0–100; `lib/bitscore.ts` throws rather than
  silently rendering a value from the protocol's earlier 0–1000 scale.
- `TestYieldStrategy` and any other non-production vault strategy are
  labeled as such wherever shown — never presented as real yield.
- No secrets in the frontend. External credentials are read from
  environment variables server-side only; nothing prefixed `CLEANVERSE_*`
  is exposed with `NEXT_PUBLIC_`.
- Monad Testnet is the only configured chain (`config/chains.ts`); mainnet
  is never implied as supported.

## Monad Testnet configuration (verified)

Verified 2026-08-08 via cross-checked public registries (chainlist.org,
chainid.network, Alchemy, thirdweb). Re-confirm directly against
`docs.monad.xyz/developer-essentials/network-information` before any
mainnet cutover.

| Parameter | Value |
|---|---|
| Chain ID | `10143` (`0x279f`) |
| Network name | Monad Testnet |
| Native currency | MON, 18 decimals |
| RPC URL | Not hardcoded — see `NEXT_PUBLIC_MONAD_TESTNET_RPC_URL` in `.env.example`; public default `https://testnet-rpc.monad.xyz` is rate-limited and for reference only |
| Block explorer | Monad Explorer — `https://testnet.monadexplorer.com` |

Implemented in `config/chains.ts` via `viem`'s `defineChain`. The RPC URL is
read only from the env var at runtime (no hardcoded fallback in code), so
`next build` never needs a real RPC endpoint to succeed, and each
environment can point at its own non-rate-limited RPC.

## Deployment status

No BitV contracts are deployed anywhere. `services/contracts/addresses.ts`'s
registries are intentionally empty until real deployments exist and are
confirmed — see `docs/development-log.md` for the full build history and
`docs/dashboard-implementation.md` for how the dashboard behaves against an
undeployed protocol.

## Further reading

- `docs/development-log.md` — dated, milestone-by-milestone build history
- `docs/dashboard-implementation.md` — dashboard data flow and component map
- `docs/bitscore-specification.md` / `docs/bitscore-implementation.md`
- `docs/rwa-market-specification.md` / `docs/rwa-market-implementation.md`
- `docs/yield-vault-specification.md` / `docs/yield-vault-implementation.md`
- `docs/cva-integration-specification.md` / `docs/cva-integration-implementation.md`
- `docs/cleanverse-integration.md` / `docs/cleanverse-cva-verification.md`
