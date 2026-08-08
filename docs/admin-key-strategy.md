# BitV Admin Key Strategy (Build 10)

This document inventories every privileged key/role in the codebase and
states which model applies for the first Monad Testnet deployment versus
what should change before any deployment holds real value. No multisig
contract is implemented or required by this milestone — this is a
documentation and planning deliverable only.

## Privilege inventory

| Privilege | Mechanism | Contract(s) | What it controls |
|---|---|---|---|
| Deployer (transaction signer) | EOA, external to any contract | all of `Deploy.s.sol` | Can execute the deployment transactions themselves; has no ongoing privilege once deployment completes unless also granted a role below |
| `DEFAULT_ADMIN_ROLE` | OZ `AccessControl` | `BitVAccessManager` | Grant/revoke every other role on `BitVAccessManager` — the root of trust for the entire role system |
| `PROTOCOL_ADMIN_ROLE` | `BitVAccessManager` role | `BitVPoolManager` (createPool, setLendingManager), `BitVLendingManager` (setBitScoreManager, setRwaRegistry), `BitVTreasury` (withdraw) | Highest operational privilege: create pools, wire core managers together, move treasury funds out |
| `RISK_MANAGER_ROLE` | `BitVAccessManager` role | `BitVPoolManager` (risk params, caps, reserve factor, rate model, oracle), `BitVLendingManager` (close factor), `BitScoreManager` (params, tier adjustments, emergency score reset), `BitVYieldVault` (performance fee, fee collection) | Tunes every economic/risk parameter in the protocol |
| `POOL_MANAGER_ROLE` | `BitVAccessManager` role | `BitVPoolManager` (enable/disable borrowing & collateral per asset) | Day-to-day pool operations |
| `PAUSER_ROLE` | `BitVAccessManager` role | `BitVPoolManager` (pool pause), `BitVYieldVault` (deposits/withdrawals/strategy pause) | Emergency stop only — cannot change parameters or move funds |
| `VAULT_MANAGER_ROLE` | `BitVAccessManager` role | `BitVYieldVault` (cap, min deposit, allocate/withdraw from strategy, min idle reserve) | Day-to-day vault liquidity operations |
| `STRATEGY_MANAGER_ROLE` | `BitVAccessManager` role | `BitVYieldVault` (setStrategy, max strategy allocation, emergency exit) | Decides which external strategy contract the vault trusts — can redirect vault funds to new code |
| `RWA_ADMIN_ROLE` | `BitVAccessManager` role | `BitVRWACollateralRegistry` (register/update RWA assets, status, caps, allowed debt assets, CVA attestation, CVA adapter wiring), `BitVCVAAdapter` (setPolicyContract, verifyInterface) | Registers/administers RWA collateral and CVA claims |
| `ORACLE_MANAGER_ROLE` | `BitVAccessManager` role | `BitVRWACollateralRegistry` (oracle config, price-freshness attestation) | Wires/attests RWA asset pricing |
| `Ownable` owner (3 separate instances) | OZ `Ownable`, one per compliance-guarded contract | `BitVPoolManager`, `BitVLendingManager`, `BitVYieldVault` (each via `BitVComplianceGuard`) | Cleanverse `RuleV2` rule management (`setRuleV2FromContract`/`addRuleV2FromContract`/`removeRuleV2FromContract`) for that specific contract only — **not** the same as any `BitVAccessManager` role |
| `Ownable` owner (oracle/rate model) | OZ `Ownable` | `StaticPriceOracle`, `KinkedInterestRateModel` | Price-setting / rate-parameter changes — separate ownership per contract instance, not part of `BitVAccessManager` at all |

**There is no `LENDING_MANAGER_ROLE`.** `BitVLendingManager` is trusted by
`BitVPoolManager`/`BitScoreManager` via a single stored `address`
(`lendingManager`), set once by `PROTOCOL_ADMIN_ROLE`/deployer via
`setLendingManager` — an identity check (`onlyLendingManager`), not an
`AccessControl` role. Listed here for completeness since Build 10's
brief names it explicitly; it does not exist as a distinct role and this
audit does not invent one.

## Two structurally separate systems — do not conflate

1. **`BitVAccessManager` roles** (above) — BitV's own internal
   protocol-administration system, checked via `BitVRoleConsumer.onlyRole`.
2. **Per-contract `Ownable` owners** — Cleanverse-facing rule management
   only, one independent owner per `BitVComplianceGuard`-inheriting
   contract. These do not go through `BitVAccessManager` at all.

`Deploy.s.sol` currently passes the **same deployer address** as both the
`BitVAccessManager` admin and every `Ownable` owner. This is intentional
for a first testnet deployment (single team-controlled key, simple to
operate and debug) but means one compromised key controls both systems —
see the production model below.

## TESTNET ADMIN MODEL

For the first Monad Testnet deployment (test funds, no real user value
at risk, primary goal is verifying the protocol works end-to-end):

- **A single EOA, controlled by the BitV team, holds every role and
  every `Ownable` ownership.** This is acceptable for testnet: the
  purpose of the deployment is to exercise the protocol, not to
  withstand a hostile environment holding real value.
- No multisig is required or implemented for testnet. Introducing one
  before the protocol has been exercised end-to-end would only add
  operational friction to debugging.
- `PAUSER_ROLE` should still be usable quickly by the same EOA — testnet
  incident response (e.g. pausing a pool after finding a bug) should not
  be gated behind anything slower than a single signature during this
  phase.
- The private key backing this EOA **must never be a real/mainnet key
  reused for testnet** — use a dedicated, disposable testnet-only key,
  loaded via `forge script`'s own signing options (`--private-key`,
  `--ledger`, `--trezor`, or a local keystore), never hardcoded into any
  file in this repository.
- Recommended minimum hygiene even at this stage: keep the deployer key
  in a password-managed keystore (`cast wallet import` /
  `--account`) rather than a bare environment variable, so it isn't
  trivially readable from process environment dumps or shell history.

## PRODUCTION ADMIN MODEL

Before any deployment holds real user value, the following should change
— documented here as a plan, not implemented in this milestone:

- **`DEFAULT_ADMIN_ROLE` and `PROTOCOL_ADMIN_ROLE` move to a multisig**
  (e.g. a 2-of-3 or 3-of-5 Safe, or equivalent on Monad once available).
  These two roles can create pools, rewire core contracts, and withdraw
  treasury funds — the highest-consequence actions in the protocol.
- **`STRATEGY_MANAGER_ROLE` moves to a multisig** before any vault holds
  real value — this role can redirect vault funds to new strategy code,
  which is functionally equivalent to a fund-migration decision.
- **Every `Ownable` owner (the 3 compliance-rule-management owners, plus
  any oracle/rate-model owner)** should also move to the same or an
  equivalently governed multisig — a single compromised EOA should never
  be able to rewrite a contract's Cleanverse compliance rules once real
  users are relying on them.
- **`RISK_MANAGER_ROLE` and `RWA_ADMIN_ROLE`** are reasonable candidates
  to stay with a smaller, faster-moving operational multisig (or even a
  dedicated risk-ops EOA with tight monitoring) separate from the
  highest-privilege admin multisig, since risk-parameter tuning and RWA
  onboarding may need faster turnaround than a full governance process —
  this is a design choice for whoever operates the production deployment
  to make deliberately, not something this audit decides on their
  behalf.
- **`PAUSER_ROLE` should remain fast** even in production — a
  single-signer or very-low-threshold multisig/EOA dedicated to incident
  response, since the entire value of an emergency pause is speed. This
  role cannot move funds or change parameters, only stop activity, which
  bounds the risk of keeping it fast.
- **`POOL_MANAGER_ROLE`, `VAULT_MANAGER_ROLE`, `ORACLE_MANAGER_ROLE`**
  are lower-consequence, day-to-day operational roles — reasonable to
  keep with an operations multisig or a monitored operational key,
  separate from the highest-privilege admin multisig, once one exists.
- This document does not specify a multisig contract, address, or
  signer set — per this milestone's explicit scope, no multisig is
  implemented or required for testnet, and choosing the actual
  multisig implementation/signers is a decision for whoever governs the
  production deployment, made when that deployment is actually being
  planned.

## What this milestone did NOT do

- Did not deploy or wire any multisig contract.
- Did not change any role assignment in `Deploy.s.sol` — it still grants
  every role to the single deployer address, matching the TESTNET ADMIN
  MODEL above exactly.
- Did not require a multisig dependency anywhere in the testnet
  deployment path.
