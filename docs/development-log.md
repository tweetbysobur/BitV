# BitV Development Log

Every milestone updates this file. Newest entry first.

---

## Milestone 1 — Foundation verification & stabilization (BUILD 01.5)

**Date:** 2026-08-08

**Context:** Verify and stabilize the `claude/bitv-recovery-foundation`
branch before any further feature work. No new product features added.

**Verified / fixed:**

- `npm install` — succeeds (833→853 packages). Existing peer-dependency
  warnings from `wagmi`/`RainbowKit`'s connector tree are pre-existing
  upstream noise, not something introduced here.
- `npm run build` — **initially failed**: RainbowKit's default connector
  set pulls in `@coinbase/cdp-sdk`, whose x402-payments code path imports
  `@x402/core`, `@x402/evm`, `@x402/svm`, `@x402/extensions` as real peer
  dependencies that weren't installed. Fixed by adding those four real
  npm packages (`^2.21.0`, matching cdp-sdk's declared peer range) to
  `package.json` — not stubbed or ignored.
- `npm run build` — **second failure**: static prerendering of `/`
  instantiated the RainbowKit/Wagmi config at build time, which throws
  without a real `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` ("No projectId
  found"). Since we don't fake credentials, the fix is architectural: added
  `export const dynamic = "force-dynamic"` to `app/layout.tsx` so the
  Web3-wrapped shell renders at request time (when a real env var is
  present) instead of at build time. No projectId was invented.
- `npm run build` — now **passes**. Two remaining compiler warnings
  (`@react-native-async-storage/async-storage` from MetaMask SDK,
  `pino-pretty` from WalletConnect's logger) are optional deps for
  code paths that only run in React Native / Node pretty-printing contexts,
  never reached from this browser app — left as warnings rather than
  silenced with fake stub packages.
- `npm run lint` — **initially failed** (285 errors): (1) ESLint config had
  no `.next/**` / `next-env.d.ts` ignore, so it was linting Next's own
  generated type-check files; fixed by adding those to `eslint.config.mjs`
  ignores. (2) Our own `services/cleanverse/types.ts` used empty
  `interface` placeholders, which `@typescript-eslint/no-empty-object-type`
  correctly flags as accepting any value; changed to
  `Record<string, never>` type aliases, which express "empty object,
  fields TBD" without that loophole. Also added an
  `argsIgnorePattern: "^_"` rule override so intentionally-unused stub
  params (`_address` in the Cleanverse client) don't warn.
- `npm run lint` — now passes clean (0 errors, 0 warnings).
- `npm run typecheck` (`tsc --noEmit`) — passes.
- Monad Testnet config (`config/chains.ts`) — chain ID `10143`, native
  currency MON (18 decimals), and block explorer
  `https://testnet.monadexplorer.com` cross-checked via web search against
  chainlist.org / chainid.network / Alchemy / thirdweb (direct fetch of
  `docs.monad.xyz` was blocked by this sandbox's egress policy). Removed
  the hardcoded RPC URL fallback from code — the chain now only resolves
  its RPC from `NEXT_PUBLIC_MONAD_TESTNET_RPC_URL`, per instruction not to
  hardcode a public RPC where an env var is expected. See
  `docs/architecture.md` for the full verified table and re-confirmation
  note.
- Cleanverse (`services/cleanverse/`) — reviewed and left as throwing
  stubs; no implementation added. This sandbox located Cleanverse's real
  docs URL (`docs.cleanverse.com`) via search but could not fetch its
  content (egress blocked), so nothing from search-result snippets (e.g.
  the terms "CVI"/"CVA") was implemented — see the rewritten
  `docs/cleanverse-integration-todo.md` for the exact 13-item checklist
  still outstanding, marked unverified where search surfaced candidate
  terminology.
- Contracts (`services/contracts/`) — added a `BitVContractName` union
  (`AccessManager | PoolManager | LendingManager | VaultManager |
  BitScoreManager | Treasury`) and typed `contractAddresses` as
  `Partial<Record<BitVContractName, DeployedContract>>`, so the registry
  shape is ready for all six protocol contracts without changing again
  when they're deployed. No addresses or ABIs added — still empty.
- `.env.example` — regrouped into Public frontend / Blockchain
  configuration / Cleanverse credentials (private, server-only) sections
  with an explicit warning that `NEXT_PUBLIC_*` is bundled client-side and
  must never hold a real credential. No new private-variable category was
  needed yet (no server-only, non-Cleanverse secrets exist in this
  foundation).

**Build result:** PASS
**Lint result:** PASS
**Typecheck result:** PASS

**Remaining blockers:**

- Cleanverse's real API/SDK content is still unread by this environment —
  blocks any real `services/cleanverse` implementation.
- Monad Testnet values are cross-source-verified but not confirmed against
  the primary `docs.monad.xyz` page directly (egress blocked here).
- No Solidity contracts exist yet — `services/contracts` is a typed but
  empty boundary.

**Next recommended milestone:** Get direct access to `docs.cleanverse.com`
(different network context, or the values manually provided) to resolve
the 13-item checklist in `docs/cleanverse-integration-todo.md`, then
implement `services/cleanverse` for real. In parallel, contract design for
`AccessManager` (the dependency root for the other five) can start once
Cleanverse's identity primitive shape is known, since access control will
likely gate on it.

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
