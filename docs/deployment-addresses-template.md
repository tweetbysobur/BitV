# BitV Monad Testnet — Deployment Addresses

Template only. Every address below is empty because nothing is deployed.
**Do not fill any field with a placeholder, example, or guessed value —
an empty field means "not deployed yet," which is meaningfully different
from a filled-in field, and must stay that way until a real deployment
transaction actually produces the address.**

Once a real deployment happens, fill in this table from the actual
transaction receipts / `Deploy.s.sol` console output, then transfer the
confirmed values into `services/contracts/addresses.ts` (see
`docs/dashboard-implementation.md` for how the frontend consumes that
file) — never edit UI components directly with an address.

## Monad Testnet (chain ID 10143)

| Contract | Address | Deployed | Validated (`ValidateDeployment.s.sol`) |
|---|---|---|---|
| AccessManager | _(empty)_ | No | No |
| Treasury | _(empty)_ | No | No |
| BitScoreManager | _(empty)_ | No | No |
| KinkedInterestRateModel | _(empty)_ | No | No |
| PoolManager | _(empty)_ | No | No |
| LendingManager | _(empty)_ | No | No |
| YieldVault | _(empty)_ | No | No |
| RWACollateralRegistry | _(empty)_ | No | No |
| CVAAdapter | _(empty)_ | No | No |
| CVIValidator (Cleanverse-owned, not deployed by BitV) | _(empty — BLOCKED, see docs/cleanverse-dependency-lock.md)_ | N/A | N/A |

## Notes

- `CVIValidator` is not a BitV deployment — it is Cleanverse's own
  contract. This row stays empty until Cleanverse confirms an address;
  see `docs/cleanverse-dependency-lock.md`.
- `YieldVault` may have more than one row once multiple vaults exist
  (one per underlying asset) — this template shows a single row because
  no vault plan beyond "one, if `YIELD_VAULT_ASSET` is configured" exists
  yet (see `contracts/script/Deploy.s.sol`).
- This file is a human-readable record for operators. The frontend never
  reads this file directly — it reads `services/contracts/addresses.ts`,
  which must be updated separately and explicitly, and which fails safe
  (empty/unavailable dashboard state) exactly as this table does when a
  row is blank.
