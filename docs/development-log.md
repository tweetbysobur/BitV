# BitV Development Log

Every milestone updates this file. Newest entry first.

---

## Milestone 2 — Cleanverse compliance foundation (BUILD 02)

**Date:** 2026-08-08

**Context:** Build 01.6 (Cleanverse documentation audit) could not proceed
— `docs.cleanverse.com` is hard-blocked by this sandbox's network egress
policy, confirmed on retry and via raw `curl`, even with the access code
provided (the block is at the network layer, before the docs site's own
auth would even apply). The user then supplied Build 02, which relays
specific interface details attributed to a "Cleanverse Compliance
Protocol Integration Guide V2" directly in the task text rather than as a
fetched document. Those relayed details (not independently verified
against a primary source) were implemented; everything not given was left
as `UNCONFIRMED` rather than guessed. Full sourcing caveat and spec in
`docs/cleanverse-integration.md`.

**Contracts created** (new `contracts/` Foundry workspace on this branch
— it didn't exist after the Build 01 clean-slate rebuild):

- `contracts/src/interfaces/external/IAPassComplianceValidator.sol` —
  `complianceVerify(address poolAddress, address userAddress) view returns (bool)`
  and the `RuleV2` struct (`allowedGroup`, `allowedSubGroup`, `minTier`,
  `minSubTier`, `poolCountryBitmap`). Field Solidity types are an
  engineering assumption (`uint256`), flagged in the file header.
- `contracts/src/libraries/ComplianceErrors.sol` — `ComplianceCheckFailed`,
  `ZeroValidatorAddress`, `NotImplemented`.
- `contracts/src/compliance/BitVComplianceGuard.sol` — abstract base:
  holds an `immutable` validator reference (no setter, rejects
  `address(0)`), exposes `_requireCompliance(user)`.
- `contracts/src/core/BitVAccessManager.sol` — OpenZeppelin
  `AccessControl`-based protocol admin roles (distinct from Cleanverse
  compliance).
- `contracts/src/core/BitVPoolManager.sol` — `addLiquidity`,
  `removeLiquidity`, `swap`: compliance-checked, then `NotImplemented`.
- `contracts/src/core/BitVLendingManager.sol` — `supply`, `borrow`,
  `repay`, `withdraw`, `liquidate`, `depositCollateral`,
  `withdrawCollateral` (RWA hooks folded into lending, no separate RWA
  contract — none was in the six-contract list): same pattern.
- `contracts/src/core/BitVVaultManager.sol` — `deposit`, `withdraw`,
  `claimRewards`: same pattern.
- `contracts/src/core/BitScoreManager.sol` — skeleton only, explicitly
  not gated by Cleanverse (BitScore is BitV-native, not a Cleanverse
  primitive) and not calculated yet.
- `contracts/src/core/BitVTreasury.sol` — `AccessControl`-gated skeleton,
  not compliance-gated (internal protocol contract, not in the
  pool/lending/vault/RWA hook list).
- `contracts/test/mocks/MockComplianceValidator.sol` — test-only, clearly
  labeled not-for-production `IAPassComplianceValidator` implementation.
- `contracts/test/unit/BitVComplianceGuard.t.sol` — the 9 required
  scenarios (verified pass, unverified reject, wrong group, wrong tier,
  country restriction, AND-within-rule, OR-across-rules, no-bypass,
  immutable/non-zero validator), plus one supporting test.
- `contracts/lib/openzeppelin-contracts` (pinned `v5.0.2`) and
  `contracts/lib/forge-std` added as git submodules; `foundry.toml` +
  `remappings.txt` added.

**Build/test result:** Foundry (`forge`) is not installed in this sandbox
and its installer host (`foundry.paradigm.xyz`) is network-blocked here —
same limitation as Build 01. As a substitute, every contract, the mock,
and the test file were compiled with `solc@0.8.24` directly (manual
import resolution against the submodule paths): **compiles clean**, only
expected `state mutability can be restricted to view` warnings on the
stub functions (correct — they'll need to be non-`view` once real state
changes are implemented). **Test execution was not run** — solc only
checks compilation, not `forge test`'s VM cheatcodes (`vm.prank`,
`vm.expectRevert`, etc.) used in the test file. Run
`forge test --match-contract BitVComplianceGuardTest -vvv` in an
environment with Foundry installed to get an actual pass/fail result.

**Frontend changes:**

- `services/cleanverse/types.ts` — added `RuleV2` (TS mirror of the
  on-chain struct, same type-assumption caveat) and `ComplianceStatus`
  (BitV's own UI status union: `loading | verification-required |
  eligible | ineligible | error`, explicitly not a Cleanverse type).
- `services/cleanverse/client.ts` — added `checkCompliance` as a
  still-throwing stub (no on-chain call wired up yet).
- `components/compliance/ComplianceStatusBadge.tsx` — presentational
  only; renders whatever `ComplianceStatus` it's given, produces none of
  its own data.
- `config/cleanverse.ts` — new config boundary: validator address (from
  `NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS`, left empty — no guessed
  address), network, and private API config references.
- `app/globals.css` / `tailwind.config.ts` — added a `destructive` color
  token (light/dark) since the compliance status states needed an
  error/ineligible color that didn't exist yet.
- `.env.example` — added `NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS`
  (public — it's a contract address, not a secret) under Blockchain
  configuration, left empty.

**Frontend verification:** `npm run build`, `npm run lint`,
`npm run typecheck` all re-run after these changes — all still **PASS**,
no regressions from Build 01.5.

**Documentation:** `docs/cleanverse-integration.md` created (full spec,
sourcing caveats, and the Single-Contract-Mode-vs-Factory-Mode
rationale). `docs/cleanverse-integration-todo.md` updated with the Build
02 status rather than replaced (prior egress-block findings still hold).

**Remaining before real deployment:** `RuleV2` field types, any
rule-management functions on the real validator, the validator's deployed
address on Monad Testnet, CVA's actual mechanics, and the entire
off-chain API/SDK/auth/webhook surface — all `UNCONFIRMED`, none guessed.

**Next recommended milestone:** Resolve the `UNCONFIRMED` list above via
real documentation access (pasted content is the only channel that's
worked so far), then (a) confirm/adjust `RuleV2` field types and any
missing validator functions, (b) get Foundry running somewhere to
actually execute `contracts/test/unit/BitVComplianceGuard.t.sol`, and (c)
only then move to economic logic (pool accounting, lending interest,
vault strategies) — still explicitly out of scope until compliance is
confirmed correct end-to-end.

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
