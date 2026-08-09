# BitV Monad Testnet — Deployment Addresses

First real deployment (Build 11), executed 2026-08-09 via `contracts/script/Deploy.s.sol`, broadcast from a GitHub Codespace by the BitV team (deployer: `0xa26ee13a084c756a3a44dda68f0547a1e654fb81`). Independently verified on-chain via `contracts/script/ValidateDeployment.s.sol`, run from the same Codespace against Monad Testnet RPC — result: `Validation passed.`

**No YieldVault, RWA asset, or pool has been created/registered yet.** These addresses are the 7 core contracts only — see `docs/deployment-readiness.md`'s "Post-deployment configuration" for what's still separate, deliberate governance action (pool creation, RWA registration, vault deployment, oracle/rate-model wiring per asset).

Any field still marked `(empty)` below means genuinely not deployed — never filled with a placeholder.

## Monad Testnet (chain ID 10143)

| Contract | Address | Deployed | Validated (`ValidateDeployment.s.sol`) |
|---|---|---|---|
| AccessManager | `0xbc45739e380322f8620687f30a58be2fc391181f` | Yes | Yes |
| Treasury | `0x0c73ca421732511617c99b17f552738a2155f79e` | Yes | Yes |
| BitScoreManager | `0x70aed4ba41319e5e1d53484306859af88051afd8` | Yes | Yes |
| KinkedInterestRateModel | _(empty)_ | No | No |
| PoolManager | `0x46f89aeee3af4c77c2c77ad3b05412404100cc93` | Yes | Yes |
| LendingManager | `0x9e1b4a5e49186b732265fea4388f3f16b303decf` | Yes | Yes |
| YieldVault | _(empty)_ | No | No |
| RWACollateralRegistry | `0x5f0b02b6ba612cf5512fc01c6e20abf5f859df77` | Yes | Yes |
| CVAAdapter | `0x2d2f0bdfea5e7e8c7dda7a6cd9dbd6f93ffd03e8` | Yes | Yes |
| CVIValidator (Cleanverse-owned, not deployed by BitV) | `0xaC7e5179C2C7f03f209136886c172eb34F161792` | N/A — Cleanverse's own contract, per BitV team confirmation this is the Monad Testnet instance | Confirmed consistent across both `PoolManager.COMPLIANCE_VALIDATOR` and `LendingManager.COMPLIANCE_VALIDATOR` by `ValidateDeployment.s.sol` |

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

## Known orphaned deployment

A first `Deploy.s.sol` run produced a separate, complete set of the same 7 contracts before this one (re-run due to a terminal working-directory mixup during manual phone-based deployment). That earlier set is **not used anywhere** — not referenced in this document, `services/contracts/addresses.ts`, or any validation. It remains live on-chain (Monad Testnet contracts can't be un-deployed) but is simply unreferenced dead weight, costing nothing beyond the gas already spent.

## Notes

- No test asset, oracle, or pool has been deployed yet — `contracts/script/DeployTestnetAssets.s.sol` is prepared and dry-run tested but not yet broadcast to Monad Testnet.
- `YieldVault` may have more than one row once multiple vaults exist (one per underlying asset).
- This file is a human-readable record for operators. The frontend never reads this file directly — it reads `services/contracts/addresses.ts`, which is updated separately (see next step).
