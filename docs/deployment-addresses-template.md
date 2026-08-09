# BitV Monad Testnet — Deployment Addresses

First real deployment (Build 11), executed 2026-08-09 via `contracts/script/Deploy.s.sol`, broadcast from a GitHub Codespace by the BitV team (deployer: `0xa26ee13a084c756a3a44dda68f0547a1e654fb81`). Independently verified on-chain via `contracts/script/ValidateDeployment.s.sol`, run from the same Codespace against Monad Testnet RPC — result: `Validation passed.`

A testnet-only oracle, test token, and one pool were added in a second
broadcast (`DeployTestnetAssets.s.sol`) — see the asset table below. A
testnet vault + strategy pair were added in a third broadcast
(`DeployTestnetVault.s.sol`), and BVTEST was registered as an RWA
collateral asset. See `docs/testnet-smoke-test.md`'s Results section for
the full verification these addresses underwent.

Any field still marked `(empty)` below means genuinely not deployed — never filled with a placeholder.

## Prompt 15 status (2026-08-09) — redeployment not executed this session

Prompt 15 asked for a fresh Monad Testnet deployment, explicitly not
assuming the addresses below are still valid. That redeployment was
**not executed**: this session's sandbox has confirmed-blocked network
egress to `testnet-rpc.monad.xyz` (`403 CONNECT tunnel failed`,
verified live during this milestone, same restriction documented
throughout Build 11), so no transaction could be broadcast without
fabricating a result — which this milestone's stop conditions
explicitly forbid.

**Important correctness note:** the addresses below were deployed
*before* Prompt 14's `BitVPoolManager.claimReserve` /
`BitVTreasury.claimPoolReserve` code existed (commit `4a8cd14`,
Build 11, predates Prompt 14's `b751893`). The live `BitVPoolManager`
and `BitVTreasury` bytecode at these addresses does **not** contain the
reserve-claim functions — Prompt 14's fix is verified only in Foundry
(240/240), never on live Monad Testnet. Redeploying (at minimum
`BitVPoolManager` and `BitVTreasury`, which are position-dependency
roots for `BitVLendingManager`/`BitVRWACollateralRegistry`/any vault —
practically, a full redeploy) is required before Build 14 can be
exercised on real testnet state.

## Monad Testnet (chain ID 10143)

| Contract | Address | Deployed | Validated (`ValidateDeployment.s.sol`) |
|---|---|---|---|
| AccessManager | `0xbc45739e380322f8620687f30a58be2fc391181f` | Yes | Yes |
| Treasury | `0x0c73ca421732511617c99b17f552738a2155f79e` | Yes | Yes |
| BitScoreManager | `0x70aed4ba41319e5e1d53484306859af88051afd8` | Yes | Yes |
| KinkedInterestRateModel | `0x68FbDaF34b604872408d36D8b7525da529B7DE51` | Yes | Not covered by `ValidateDeployment.s.sol` (per-asset config, checked separately) |
| PoolManager | `0x46f89aeee3af4c77c2c77ad3b05412404100cc93` | Yes | Yes |
| LendingManager | `0x9e1b4a5e49186b732265fea4388f3f16b303decf` | Yes | Yes |
| YieldVault | `0xe0d6eb07790d367483554d29d3e7f8902b35ec6d` (BVTEST vault) | Yes | Not covered by `ValidateDeployment.s.sol` (deployed in a later, separate broadcast); manually verified (deposit/withdraw/pause/strategy/fee flow — see `docs/testnet-smoke-test.md`) |
| RWACollateralRegistry | `0x5f0b02b6ba612cf5512fc01c6e20abf5f859df77` | Yes | Yes |
| CVAAdapter | `0x2d2f0bdfea5e7e8c7dda7a6cd9dbd6f93ffd03e8` | Yes | Yes |
| CVIValidator (Cleanverse-owned, not deployed by BitV) | `0xaC7e5179C2C7f03f209136886c172eb34F161792` | N/A — Cleanverse's own contract, per BitV team confirmation this is the Monad Testnet instance | Confirmed consistent across both `PoolManager.COMPLIANCE_VALIDATOR` and `LendingManager.COMPLIANCE_VALIDATOR` by `ValidateDeployment.s.sol` |

## Testnet-only assets (via `DeployTestnetAssets.s.sol`)

| Contract | Address | Notes |
|---|---|---|
| StaticPriceOracle | `0x03A2E6d989B573b988c2e063969D29B4E44D1fe8` | **Testnet-only, non-production** — admin-set prices, no economic security. Never use for real value. See `docs/oracle-deployment-plan.md`. |
| BitVTestToken (BVTEST) | `0xD031f2F863dd481a869814CaE6813b17590C3B45` | **Test asset, no real value.** Never a CVA. 1,000,000 BVTEST minted to the deployer for smoke-testing. See `docs/testnet-assets.md`. |
| Pool for BVTEST | on `PoolManager` (`0x46f89aeee3af4c77c2c77ad3b05412404100cc93`) | LTV 70%, liquidation threshold 80%, liquidation bonus 5%, borrowing + collateral enabled, supply cap 500,000 BVTEST, borrow cap 250,000 BVTEST |
| BVTEST test price | $1.00 (8 decimals) set on StaticPriceOracle | Arbitrary, clearly-labeled test price — not a real market price |
| TestYieldStrategy | `0x5df7b517f11963abe6ef5957468c6fb32e18647a` | **Non-production** — bound to the BVTEST vault above; generates no real yield, only `simulateYield`. See `contracts/src/vault/TestYieldStrategy.sol`'s NatSpec. |
| BVTEST as RWA collateral | registered on `RWACollateralRegistry` (`0x5f0b02b6ba612cf5512fc01c6e20abf5f859df77`) | LTV 60%, liquidation threshold 70%, liquidation bonus 5%, collateral cap 50,000 BVTEST, priced by the same StaticPriceOracle above. **Not a CVA** — `isCVAFullyRecognized` confirmed `false` on-chain; no attestation was ever set. |

## Post-deployment wiring (all confirmed by `ValidateDeployment.s.sol`)

- `PoolManager.lendingManager` → `LendingManager` ✓
- `LendingManager.POOL_MANAGER` → `PoolManager` ✓
- `LendingManager.bitScoreManager` → `BitScoreManager` ✓
- `LendingManager.rwaRegistry` → `RWACollateralRegistry` ✓
- `BitScoreManager.lendingManager` → `LendingManager` ✓
- `RWACollateralRegistry.POOL_MANAGER` → `PoolManager` ✓
- `RWACollateralRegistry.cvaAdapter` → `CVAAdapter` ✓
- `PoolManager.TREASURY` / `LendingManager.TREASURY` → `Treasury` ✓
- All roles on `AccessManager` confirmed granted to `0xa26ee13a084c756a3a44dda68f0547a1e654fb81` (the TESTNET ADMIN MODEL single-EOA setup, per `docs/admin-key-strategy.md`)

## Cleanverse sandbox compliance registrations

| Contract | Registered? | Method |
|---|---|---|
| `PoolManager` | Yes | `POST /validator/register` (sandbox), unrestricted rule |
| `LendingManager` | Yes | `POST /validator/register` (sandbox), unrestricted rule |
| `BitVYieldVault` (BVTEST vault) | Yes | `POST /validator/register` (sandbox), unrestricted rule |
| Deployer wallet (`0xa26ee13a084c756a3a44dda68f0547a1e654fb81`) | Holds a sandbox A-Pass | `POST /generate_apass` (sandbox), customer ID `BITVDEPLOYER01`, chain `monad` |

Full detail in `docs/cleanverse-dependency-lock.md`'s "Sandbox compliance
registrations" section. Sandbox only — not production.

## Known orphaned deployment

A first `Deploy.s.sol` run produced a separate, complete set of the same 7 contracts before this one (re-run due to a terminal working-directory mixup during manual phone-based deployment). That earlier set is **not used anywhere** — not referenced in this document, `services/contracts/addresses.ts`, or any validation. It remains live on-chain (Monad Testnet contracts can't be un-deployed) but is simply unreferenced dead weight, costing nothing beyond the gas already spent.

## Notes

- `YieldVault` may have more than one row once multiple vaults exist (one per underlying asset) — none deployed yet.
- This file is a human-readable record for operators. The frontend never reads this file directly — it reads `services/contracts/addresses.ts`, which is updated separately (see next step).
