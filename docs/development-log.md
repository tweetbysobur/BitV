# BitV Development Log

Every milestone updates this file. Newest entry first.

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
