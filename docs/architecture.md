# BitV Architecture

## Summary

BitV is an identity-native DeFi protocol on Monad Testnet, built on Cleanverse
identity and verified-asset infrastructure. This document describes the
foundation established in the current milestone — no protocol logic
(lending, borrowing, pools, vaults, BitScore) exists yet.

## Layering

```
app/            Next.js App Router — routes, layouts, pages (UI only)
components/     Reusable UI (components/ui = shadcn primitives) and providers
lib/            Framework-agnostic utilities (cn(), fonts)
hooks/          React hooks — will wrap services/ for data access
services/       Boundary modules to external systems
  cleanverse/   Cleanverse identity + verified-asset integration boundary
  contracts/    On-chain contract addresses/ABIs boundary (empty — no contracts yet)
contracts/      Foundry workspace for BitV Solidity contracts (not yet created)
types/          Shared TypeScript types
config/         Site metadata, chain definitions, wagmi config
docs/           This directory
tests/          Test suite (empty — no logic to test yet)
```

## Principles enforced in this milestone

- The frontend does not talk to Cleanverse or on-chain contracts directly —
  everything routes through `services/`, so a UI component never imports a
  third-party SDK.
- `services/cleanverse` and `services/contracts` are boundary modules with
  real TypeScript interfaces but no working implementation. They throw
  rather than fake success, so nothing downstream can mistake them for a
  real integration.
- No secrets in the frontend. All external credentials are read from
  environment variables server-side only (see `.env.example`); nothing
  prefixed `CLEANVERSE_*` is exposed with `NEXT_PUBLIC_`.
- Monad Testnet is the only configured chain (`config/chains.ts`).

## Open questions

See `docs/cleanverse-integration-todo.md` for what's still required before
Cleanverse functionality can be implemented for real.

## Monad Testnet configuration (verified)

Verified 2026-08-08. This sandbox could not directly fetch
`docs.monad.xyz` (blocked by network egress policy), so these values were
cross-checked via web search against multiple independent
registries/providers (chainlist.org, chainid.network, Alchemy, thirdweb) that
mirror Monad's official published network parameters. Re-confirm directly
against `docs.monad.xyz/developer-essentials/network-information` when this
environment has direct access, before mainnet cutover.

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
