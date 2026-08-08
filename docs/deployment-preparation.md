# BitV Testnet Deployment Preparation (Build 10)

This is the top-level index for Build 10's deployment-preparation work.
Nothing was deployed or broadcast — see each linked document for detail.

## What this milestone did

1. **Fixed two deployment-safety gaps** flagged (not fixed) by Build 09:
   `BitVAccessManager`'s constructor now reverts on `admin == address(0)`
   (previously would have permanently bricked administration of the
   whole protocol); `BitVYieldVault`'s constructor now reverts on
   `asset_ == address(0)`. Both have regression tests
   (`contracts/test/unit/BitVAccessManager.t.sol`,
   `test_Constructor_ZeroAsset_Reverts` in
   `contracts/test/unit/BitVYieldVault.t.sol`). No other Solidity file
   was touched.
2. **Documented the full admin-key privilege inventory** and split it
   into a TESTNET (single EOA, everything) vs. PRODUCTION (multisig for
   the highest-consequence roles) model — see
   `docs/admin-key-strategy.md`. No multisig was implemented; none is
   required for testnet.
3. **Audited environment configuration** end to end
   (`.env.example`, the new `contracts/.env.example`,
   `contracts/script/Deploy.s.sol`, `contracts/script/
   ValidateDeployment.s.sol`, `config/chains.ts`, `config/wagmi.ts`,
   `services/contracts/addresses.ts`) and created a complete
   deployment-time environment template
   (`contracts/.env.example`) — no real credential anywhere, every
   `NEXT_PUBLIC_` variable confirmed to be genuinely public data.
4. **Re-verified Monad Testnet configuration** (chain ID 10143, RPC
   handling, explorer, native currency decimals) — unchanged from Build
   09's confirmation; no new primary-source access was available in this
   environment, so no stronger confirmation is claimed than before.
5. **Audited WalletConnect configuration** — confirmed the project ID is
   consumed in exactly one place (`config/wagmi.ts`), warns loudly (not
   silently) when unset, and never falls back to a fake ID.
6. **Wrote the oracle deployment plan**
   (`docs/oracle-deployment-plan.md`) — maps exactly which contracts need
   oracle data and for what, separates the existing `StaticPriceOracle`
   (testnet-only, explicitly documented limitations) from a production
   oracle (not selected — remains a hard blocker for real value,
   deliberately not resolved by inventing a provider address).
7. **Wrote the testnet asset strategy**
   (`docs/testnet-assets.md`) — no real asset address is confirmed
   anywhere; recorded as an explicit blocker with two documented paths
   forward (BitV-issued test tokens vs. sourcing a verified real
   address), neither executed this milestone.
8. **Wrote the Cleanverse dependency lock table**
   (`docs/cleanverse-dependency-lock.md`) — consolidates every CVI/CVA
   fact's confirmation status into the exact format this milestone asks
   for. `BitVCVAAdapter` remains unchanged; no new Cleanverse
   functionality was implemented.
9. **Reviewed (did not broadcast) `Deploy.s.sol` and
   `ValidateDeployment.s.sol`** — both already fail loudly and completely
   on a missing/zero `CLEANVERSE_VALIDATOR_ADDRESS` or missing deployed
   addresses; no weakening, no silent partial deployment path exists in
   either script.
10. **Ran a local Anvil dry-run** of the deployment sequence using
    test-only keys — see `docs/deployment-readiness.md`'s updated dry-run
    section (or the chat final report) for the exact result. Never
    touched Monad Testnet.
11. **Confirmed the frontend already consumes deployment addresses
    cleanly** — no UI component hardcodes an address; everything routes
    through `services/contracts/addresses.ts`, unchanged this milestone.
    Added `docs/deployment-addresses-template.md` as the operator-facing
    record to fill in after a real deployment.
12. **Ran the full verification suite** — see the chat final report for
    live Foundry/Vitest/lint/build results.

## What this milestone deliberately did not do

- No broadcast, no deployment transaction, no real private key used
  anywhere.
- No Cleanverse address, oracle address, or token address invented.
- No multisig contract implemented.
- No CVA transfer enforcement implemented.
- No protocol economics changed.
- No `contracts/src/**` file changed beyond the two explicit,
  minimal zero-address guards in Phase 1.

## Document map

| Document | Covers |
|---|---|
| `docs/admin-key-strategy.md` | Phase 2 — full role/ownership inventory, testnet vs. production admin model |
| `docs/oracle-deployment-plan.md` | Phase 6 — oracle data requirements, testnet vs. production oracle |
| `docs/testnet-assets.md` | Phase 7 — asset requirements, blocker status, paths forward |
| `docs/cleanverse-dependency-lock.md` | Phase 8 — final Cleanverse requirement/status/source/next-action table |
| `docs/deployment-addresses-template.md` | Phase 12 — empty operator-facing address record |
| `docs/deployment-readiness.md` | Build 09's original audit, plus this milestone's updates where noted |
| `docs/testnet-smoke-test.md` | Build 09's smoke-test plan (unchanged — still not executed) |
| `docs/development-log.md` | Milestone-by-milestone history, including this one |
