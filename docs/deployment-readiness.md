# BitV Deployment Readiness Audit (Build 09, updated by Build 10)

Audit only — nothing was deployed, no transaction was broadcast, no
economics or Cleanverse functionality were changed. See
`docs/testnet-smoke-test.md` for the manual test sequence to run only
after deployment, and `contracts/script/Deploy.s.sol` /
`contracts/script/ValidateDeployment.s.sol` for the (unrun) deployment
and validation scripts this audit prepared.

> **Build 10 update:** the two safety gaps flagged below (§14, "flagged,
> not fixed") — `BitVAccessManager`'s missing zero-address guard and
> `BitVYieldVault.asset_`'s missing zero-address guard — are now FIXED,
> with regression tests. See `docs/deployment-preparation.md` for the
> full Build 10 summary, `docs/admin-key-strategy.md`,
> `docs/oracle-deployment-plan.md`, `docs/testnet-assets.md`, and
> `docs/cleanverse-dependency-lock.md` for the deeper treatment of topics
> this document's Phase 4/6/7/8 originally covered at audit depth only.
> The external blockers below (Cleanverse validator address/Monad
> support, production oracle, real testnet assets) remain unresolved —
> Build 10 could not resolve them, since they require Cleanverse or
> external infrastructure BitV does not control.

## 1. Contract inventory

| Contract | Path | Type | Constructor args | Depends on | Deploy independently? |
|---|---|---|---|---|---|
| `BitVAccessManager` | `core/BitVAccessManager.sol` | Deployable | `address admin` | none | Yes |
| `BitVRoleConsumer` | `access/BitVRoleConsumer.sol` | Abstract base (not deployed directly) | — | — | — |
| `BitVComplianceGuard` | `compliance/BitVComplianceGuard.sol` | Abstract base (not deployed directly) | — | — | — |
| `BitVTreasury` | `core/BitVTreasury.sol` | Deployable | `address accessManager` | AccessManager | Yes, after AccessManager |
| `BitScoreManager` | `core/BitScoreManager.sol` | Deployable | `address accessManager` | AccessManager | Yes, after AccessManager |
| `BitVPoolManager` | `core/BitVPoolManager.sol` | Deployable | `address complianceValidator, address owner_, address accessManager, address treasury_` | AccessManager, Treasury, **Cleanverse CVI validator** | No — needs Cleanverse validator address |
| `BitVLendingManager` | `core/BitVLendingManager.sol` | Deployable | `address complianceValidator, address owner_, address accessManager, address poolManager, address treasury_` | AccessManager, Treasury, PoolManager, **Cleanverse CVI validator** | No — needs PoolManager + Cleanverse validator |
| `BitVRWACollateralRegistry` | `core/BitVRWACollateralRegistry.sol` | Deployable | `address accessManager, address poolManager` | AccessManager, PoolManager | No — needs PoolManager (which needs Cleanverse) |
| `BitVCVAAdapter` | `core/BitVCVAAdapter.sol` | Deployable | `address accessManager` | AccessManager | Yes, after AccessManager |
| `BitVYieldVault` | `core/BitVYieldVault.sol` | Deployable (one instance per underlying asset) | `IERC20 asset_, string name_, string symbol_, address complianceValidator, address complianceOwner, address accessManager, address treasury_, uint256 vaultCap_, uint256 minDeposit_` | AccessManager, Treasury, a real underlying ERC-20, **Cleanverse CVI validator** | No — needs a real asset + Cleanverse validator |
| `BitVVaultManager` | `core/BitVVaultManager.sol` | Deployable, but **superseded** | `address complianceValidator, address owner_` | Cleanverse CVI validator | Dead code — every function reverts `NotImplemented()`; superseded by `BitVYieldVault`. **Exclude from production deployment.** |
| `StaticPriceOracle` | `oracles/StaticPriceOracle.sol` | Deployable, **not production-suitable** | `address owner_` | none | Yes, but see Phase 6 |
| `KinkedInterestRateModel` | `oracles/KinkedInterestRateModel.sol` | Deployable | `address owner_, uint256 baseRateRay_, uint256 slope1Ray_, uint256 slope2Ray_, uint256 kinkRay_` | none | Yes |
| `TestYieldStrategy` | `vault/TestYieldStrategy.sol` | Deployable, **test-only** | `address asset_, address vault_, bool confirmedTestOnlyDeployment` | a deployed BitVYieldVault | **Exclude from production deployment** — see NatSpec: non-production, no real yield source |

**Test-only / mock contracts excluded from production deployment** (all under `contracts/test/mocks/`, not part of `contracts/src/`): `MockERC20`, `MockComplianceValidator`, `MockReentrantVaultERC20`, `MockReentrantERC20`, `MockCVAPolicy`. None of these should ever be referenced by a production deployment script.

## 2. Dependency graph

```
BitVAccessManager
  │
  ├──> BitVTreasury
  │
  ├──> BitScoreManager
  │
  ├──> BitVCVAAdapter
  │
  └──> BitVPoolManager  (also needs: Cleanverse CVI validator, BitVTreasury)
         │
         ├──> BitVLendingManager  (also needs: BitVTreasury, Cleanverse CVI validator)
         │      │
         │      ├── setBitScoreManager(BitScoreManager)   [post-deploy config]
         │      └── setRwaRegistry(BitVRWACollateralRegistry)  [post-deploy config]
         │
         ├──> BitVRWACollateralRegistry  (also needs: BitVAccessManager)
         │      └── setCVAAdapter(BitVCVAAdapter)  [post-deploy config]
         │
         └──> BitVYieldVault (per asset)  (also needs: BitVTreasury, Cleanverse CVI validator, a real underlying ERC-20)
                └──> TestYieldStrategy or a real strategy (optional, set via setStrategy)  [post-deploy config, EXCLUDE TestYieldStrategy from production]
```

`BitScoreManager.setLendingManager(BitVLendingManager)` and
`BitVPoolManager.setLendingManager(BitVLendingManager)` are the two
"points backward" links — **not** circular dependencies in the deployment
sense, since both are ordinary post-deployment setter calls (already
present in the contracts, `PROTOCOL_ADMIN_ROLE`-gated), not constructor
arguments. No genuine circular *constructor* dependency exists anywhere
in the graph: every contract that needs another contract's address takes
it in its constructor only after that other contract already exists, and
the two "backward" references are resolved via existing setters after
both sides are deployed. **No architecture change is needed to remove a
circular dependency — none exists.**

`IPriceOracle` and `IInterestRateModel` are wired per-pool via
`BitVPoolManager.setPriceOracle`/`setInterestRateModel` (or at
`createPool` time) — also post-deployment configuration, not constructor
arguments, so they don't appear in the constructor graph above.

## 3. Constructor audit

| Contract | Zero-address protected? | Notes |
|---|---|---|
| `BitVAccessManager(admin)` | No explicit check — `AccessControl._grantRole` with `address(0)` would grant roles to the zero address rather than revert | **Flag**: pass a real, confirmed admin address; do not pass `address(0)`. Low risk (deployer controls the input) but no on-chain guard exists. |
| `BitVTreasury(accessManager)` | Yes, via `BitVRoleConsumer` (`ProtocolErrors.ZeroAddress()`) | Ready |
| `BitScoreManager(accessManager)` | Yes, via `BitVRoleConsumer` | Ready; constructor also sets default `Params`/`TierAdjustment[4]` — reviewed, matches `docs/bitscore-specification.md`'s approved 0–100 rescale (start 30, cap 70, tiers 25/50/75) |
| `BitVPoolManager(complianceValidator, owner_, accessManager, treasury_)` | `complianceValidator` via `BitVComplianceGuard` (`ComplianceErrors.ZeroValidatorAddress()`); `accessManager` via `BitVRoleConsumer`; `treasury_` explicitly checked; `owner_` passed straight to OZ `Ownable`, which itself reverts on `address(0)` | Ready, **blocked only on a real `complianceValidator` value** |
| `BitVLendingManager(complianceValidator, owner_, accessManager, poolManager, treasury_)` | `complianceValidator`/`accessManager` as above; `poolManager`/`treasury_` explicitly checked; `owner_` via OZ `Ownable` | Ready, **blocked only on a real `complianceValidator` value** |
| `BitVRWACollateralRegistry(accessManager, poolManager)` | `accessManager` via `BitVRoleConsumer`; `poolManager` explicitly checked | Ready (does not itself need the Cleanverse validator — only its upstream `poolManager` does) |
| `BitVCVAAdapter(accessManager)` | Yes, via `BitVRoleConsumer` | Ready — does not need any Cleanverse address at construction time |
| `BitVYieldVault(asset_, name_, symbol_, complianceValidator, complianceOwner, accessManager, treasury_, vaultCap_, minDeposit_)` | `treasury_` explicitly checked; `complianceValidator`/`accessManager` as above; `asset_` is NOT explicitly zero-checked here, but OZ's `ERC4626`/`ERC20` constructors will behave degenerately (not usefully) against `address(0)` | **Flag**: pass a real, deployed ERC-20 address for `asset_`; do not deploy against a placeholder. `vaultCap_`/`minDeposit_` of `0` is intentionally the safe default in the prepared `Deploy.s.sol` (0 cap = no deposits accepted until `VAULT_MANAGER_ROLE` explicitly raises it) |
| `StaticPriceOracle(owner_)` | Via OZ `Ownable` | Ready, but see Phase 6 — do not treat this as production-suitable regardless of constructor safety |
| `KinkedInterestRateModel(owner_, baseRateRay_, slope1Ray_, slope2Ray_, kinkRay_)` | `kinkRay_` checked (`0 < kinkRay_ <= RAY`); `owner_` via OZ `Ownable`; rate params unchecked (any value accepted) | Ready — rate parameters are a governance/risk decision, not a safety defect |
| `TestYieldStrategy(asset_, vault_, confirmedTestOnlyDeployment)` | `asset_`/`vault_` explicitly checked; `confirmedTestOnlyDeployment` must be `true` or it reverts | Excluded from production deployment regardless of safety — see inventory |

No constructor argument is invented or guessed anywhere in this audit or
in the prepared deployment script — every address argument is read from
an environment variable at deploy time, and the script reverts if the one
value with no safe placeholder (`CLEANVERSE_VALIDATOR_ADDRESS`) is unset.

## 4. Role matrix

All roles live on `BitVAccessManager`, checked via `BitVRoleConsumer.onlyRole`, except `BitVComplianceGuard`'s `onlyOwner` (OpenZeppelin `Ownable`, one owner per compliance-guarded contract — see note below the table) and `TREASURY`'s deposit function (unrestricted, by design).

| Role | Contract(s) that check it | Purpose | Who receives it at deploy | Deployer receives it? | Should be transferred/revoked post-deploy? |
|---|---|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` | `BitVAccessManager` (OZ `AccessControl`) | Can grant/revoke every other role | `admin` constructor arg | Yes, if deployer is also `admin` | **Yes** — highest privilege; move to a multisig/governance address before real value is at risk |
| `PROTOCOL_ADMIN_ROLE` | `BitVPoolManager` (createPool, setLendingManager), `BitVLendingManager` (setBitScoreManager, setRwaRegistry), `BitVTreasury` (withdraw) | Highest operational privilege — pool creation, wiring managers, treasury withdrawal | `admin` | Yes | **Yes** — same reasoning as `DEFAULT_ADMIN_ROLE` |
| `RISK_MANAGER_ROLE` | `BitVPoolManager` (risk params, caps, reserve factor, interest rate model, price oracle), `BitVLendingManager` (close factor), `BitScoreManager` (params, tier adjustments, emergency reset), `BitVYieldVault` (performance fee, collectPerformanceFee) | Tunes risk/economic parameters | `admin` | Yes | Recommended — narrow to an actual risk-management address/multisig once one exists |
| `POOL_MANAGER_ROLE` | `BitVPoolManager` (enable/disable borrowing & collateral) | Day-to-day pool operations | `admin` | Yes | Recommended, lower urgency than admin/risk roles |
| `PAUSER_ROLE` | `BitVPoolManager` (pool pause), `BitVYieldVault` (deposits/withdrawals/strategy pause) | Emergency pause only | `admin` | Yes | Recommended to keep with an incident-response-capable address (can stay with deployer/ops longer than admin roles, by design — see `BitVAccessManager`'s NatSpec) |
| `VAULT_MANAGER_ROLE` | `BitVYieldVault` (cap, min deposit, allocate/withdraw from strategy, min idle reserve) | Day-to-day vault operations | `admin` | Yes | Recommended |
| `STRATEGY_MANAGER_ROLE` | `BitVYieldVault` (setStrategy, max strategy allocation, emergency exit) | Controls which external code the vault trusts | `admin` | Yes | **Yes, high priority once a real (non-test) strategy exists** — this role can point vault funds at new external code |
| `RWA_ADMIN_ROLE` | `BitVRWACollateralRegistry` (register/update assets, status, caps, allowed debt assets, CVA attestation, CVA adapter wiring), `BitVCVAAdapter` (setPolicyContract, verifyInterface) | Registers/administers RWA assets and CVA claims | `admin` | Yes | Recommended — this role can set `adminAttestedCVA`, which is user-facing signal (with disclaimer) about CVA status |
| `ORACLE_MANAGER_ROLE` | `BitVRWACollateralRegistry` (oracle config, markPriceFresh) | Wires/attests RWA asset pricing | `admin` | Yes | Recommended |

**No other production role exists.** `BitVComplianceGuard`'s `onlyOwner` (OpenZeppelin `Ownable`, one distinct owner per compliance-guarded contract instance — `BitVPoolManager`, `BitVLendingManager`, `BitVYieldVault` each has its own) is a **separate mechanism from `BitVAccessManager`**, gating only the Cleanverse RuleV2 rule-management wrappers (`setRuleV2FromContract` etc.). The prepared `Deploy.s.sol` passes `deployer` as `owner_`/`complianceOwner` for all three — **this is excessive, undocumented-elsewhere deployer privilege** (single EOA can rewrite each contract's Cleanverse compliance rules) that must be explicitly called out: transfer each `Ownable` to a multisig/governance address, or accept and document the risk, before real value is at stake. This is flagged here rather than silently left as a loose end.

`BitVVaultManager`'s constructor takes its own separate `owner_` too, but that contract is dead code excluded from deployment (see inventory).

## 5. External dependencies

| Dependency | Status | Notes |
|---|---|---|
| Monad Testnet RPC | CONFIRMED (public default `https://testnet-rpc.monad.xyz`, rate-limited) | `NEXT_PUBLIC_MONAD_TESTNET_RPC_URL`; use a dedicated provider for anything beyond light testing |
| Monad Testnet chain ID (10143) | CONFIRMED via cross-referenced public registries (chainlist.org, chainid.network, Alchemy, thirdweb) — not yet directly confirmed against `docs.monad.xyz` from this environment (network-blocked) | Re-verify directly before deployment if possible |
| WalletConnect / RainbowKit project ID | REQUIRED BUT ADDRESS UNKNOWN — no `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` value is set in this repo | Obtain a real project ID before frontend wallet connection works end-to-end; not a contract blocker |
| OpenZeppelin Contracts | CONFIRMED | Standard library dependency, already vendored via `lib/` |
| Cleanverse CVI validator address (any network) | **REQUIRED BUT ADDRESS UNKNOWN — BLOCKED** | Not given by either official Cleanverse PDF for any network, per `docs/cleanverse-integration.md`/`docs/cleanverse-integration-todo.md`. `CLEANVERSE_VALIDATOR_ADDRESS` is empty in `.env.example` and must stay empty until Cleanverse confirms one |
| Cleanverse support for Monad Testnet at all | **REQUIRED BUT UNCONFIRMED — BLOCKED** | The CVA guide's network list ("Ethereum, Base, BSC, Arbitrum, Polygon, etc.") does not name Monad; the CVI guide gives no network list at all. This is a precondition to the validator-address question above, not a separate later step |
| Cleanverse CVA policy contract(s) for any specific token | NOT REQUIRED FOR MVP | CVA is per-token, issued via Cleanverse's Launch/Register flow — nothing to wire until BitV or a partner actually issues/holds a CVA-designated token |
| Production price oracle (any asset) | REQUIRED BUT ADDRESS UNKNOWN | See Phase 6 — no production-suitable oracle exists in this codebase or has been selected |
| Real ERC-20 assets to list (lending pools, RWA collateral, vault underlying) | REQUIRED BUT ADDRESS UNKNOWN | See Phase 7 — no real Monad Testnet asset addresses are confirmed in this repo |
| Multisig/governance address for `DEFAULT_ADMIN_ROLE`/`PROTOCOL_ADMIN_ROLE`/`Ownable` owners | OPTIONAL for a first testnet deployment, RECOMMENDED before any real value | See role matrix — not itself a hard blocker for a testnet-only deployment under a single EOA the team controls |

## 6. Oracle audit

- **Required interface**: `IPriceOracle.getPrice(address asset) returns (uint256 price, uint8 decimals)` — a single synchronous read, no round/timestamp data in the interface itself.
- **Supported assets**: whatever `StaticPriceOracle.setPrice` has been called for (owner-set, no default assets).
- **Price decimals**: caller-supplied per asset (`uint8`), used directly by `BitVLendingManager._valueOf`/`_tryValueOf`; the code requires the oracle's `decimals` to be `<= 18` (undocumented as an explicit revert — an oracle with `decimals > 18` would underflow `10 ** (18 - priceDecimals)` and revert at the call site, which is a safe failure mode, not silent corruption).
- **Freshness assumptions**: `IPriceOracle` itself has **no timestamp/staleness concept at all**. `BitVRWACollateralRegistry` layers its own freshness attestation (`markPriceFresh`/`maxOracleStalenessSeconds`) on top for RWA assets specifically; ordinary (non-RWA) pool collateral/debt pricing via `BitVLendingManager` has **no staleness protection whatsoever** — a stale-but-nonzero price from `StaticPriceOracle` (or any future oracle) is used as-is.
- **Zero-price behavior**: `BitVLendingManager._tryValueOf` treats a zero price the same as "no oracle configured" — the asset is silently skipped from that user's aggregated position (documented, existing risk — see `docs/economic-engine-review.md`, `_tryValueOf`'s NatSpec). `BitVRWACollateralRegistry.isEligibleForNewActivity` explicitly rejects a zero price.
- **Stale-price behavior**: not detected at all outside the RWA registry's own attestation layer, as above.
- **Can a test oracle be safely used on Monad Testnet?** Yes, for a genuine testnet-only, no-real-value deployment, **provided this is explicitly documented as such everywhere it's referenced** (dashboard, docs, any public-facing testnet materials) — `StaticPriceOracle`'s own NatSpec already states plainly that its owner can single-handedly manipulate liquidations, which is unacceptable for anything holding real value.

**Deployment blocker or testnet-only dependency?** `StaticPriceOracle` is a **testnet-only dependency, not a production blocker for a testnet deployment** — but it **is a hard blocker for any deployment holding real value**, since no production-quality oracle exists in this codebase or has been selected. This audit does not silently substitute the mock as if it were acceptable for anything beyond testnet.

## 7. Token / asset audit

No asset addresses are confirmed for Monad Testnet in this repository. `services/contracts/addresses.ts`'s `poolAssets`/`rwaAssets`/`yieldVaults` registries are empty by design (see Build 08). This audit does not create arbitrary fake assets. Until real, confirmed asset addresses exist:

| Symbol | Address | Decimals | Source | Deployed? | Verified? | Suitable for testing? |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | No real asset is currently confirmed for Monad Testnet in this repo |

For an initial testnet-only deployment, the safest path is deploying BitV's own test ERC-20s (mirroring `contracts/test/mocks/MockERC20.sol`, explicitly labeled test-only, never presented as a CVA or as having real value) rather than guessing at a real Monad Testnet token's address. No asset should ever be labeled a CVA without confirmed Cleanverse evidence — none exists in this repo today (see Phase 8).

## 8. Cleanverse audit

No new Cleanverse functionality was implemented in this milestone — this is a classification of what already exists.

### CVI

| Item | Status |
|---|---|
| Validator address (any network) | **BLOCKED** — not given by either official Cleanverse PDF, for any network |
| `complianceVerify` | **CONFIRMED** interface (CVI Integration Guide V2 §3.2), fully implemented in `IAPassComplianceValidator.sol` / used throughout via `BitVComplianceGuard._requireCompliance` |
| Registration (`registerV2`, `registerApass`, `setRuleV2FromRegistrar`, `isRegistered`) | **CONFIRMED** interface, declared but not called by BitV (Single-Contract Mode — registration is an off-chain API call outside contract scope) |
| Rule-management (`setRuleV2FromContract`, `addRuleV2FromContract`, `removeRuleV2FromContract`, `getRulesV2`) | **CONFIRMED** interface, implemented and exposed via `BitVComplianceGuard`'s owner-gated wrappers |
| Authentication / off-chain registration process | **UNCONFIRMED** in detail (API key format, endpoint, etc. — see `docs/cleanverse-integration-todo.md` items 4–7) |
| Monad support | **BLOCKED** — "Monad" does not appear in either official PDF; no chain is named as supported or unsupported specifically |

### CVA

| Item | Status |
|---|---|
| `IATokenPolicy` | **PARTIALLY CONFIRMED** — the interface exists and shares `RuleV2` with CVI (confirmed); `getRulesV2(address token)`'s exact signature is a disclosed, reasonable inference by analogy, not independently confirmed |
| `RuleV2` (CVA side) | **CONFIRMED** — identical struct to CVI's, per the CVA guide |
| `canTransfer` | **UNCONFIRMED** — argument list confirmed, but return type/visibility/mutability and revert-vs-boolean rejection behavior are not; deliberately **not declared** in `IATokenPolicy.sol` and **not called anywhere** in this codebase |
| `getRulesV2` (CVA side) | **PARTIALLY CONFIRMED**, as above — used only as a read-only `staticcall` probe (`BitVCVAAdapter.verifyInterface`), never trusted as proof of Cleanverse approval |
| CVA verification (Cleanverse's own off-chain approval of a specific token) | **NOT REQUIRED FOR MVP / structurally unavailable** — no on-chain query for this fact is confirmed to exist anywhere in either guide |
| Freeze/revoke | **UNCONFIRMED** — neither guide's confirmed interface surface includes these |

**The current CVA adapter (`BitVCVAAdapter.previewTransfer`) remains non-executable for transfer validation, by design, and this audit does not change that.** It reverts unconditionally (`CVAErrors.TransferValidationUnconfirmed()`) because `canTransfer`'s signature is unconfirmed — this restriction is not bypassed here, and no new Cleanverse functionality was implemented to work around it.

## 9. Deployment script status

`contracts/script/Deploy.s.sol` has been extended (this milestone) to deploy every contract identified in Phase 1 as safely deployable, in the dependency order from Phase 2, and to perform the post-deployment wiring calls identified in Phase 10's on-chain section. It:

- Deploys in order: `BitVAccessManager` → `BitVTreasury` + `BitScoreManager` → `BitVPoolManager` → `BitVLendingManager` + `BitVRWACollateralRegistry` → `BitVCVAAdapter` → optionally one `BitVYieldVault`.
- Records every address via `console2.log`.
- Wires `setLendingManager`, `setBitScoreManager`, `setRwaRegistry`, `setCVAAdapter` post-deployment.
- Reads `CLEANVERSE_VALIDATOR_ADDRESS` from the environment and **reverts (`require`) if it is unset or zero** — no fallback, no fabricated address.
- Reads the optional yield-vault asset/name/symbol from the environment; skips vault deployment entirely if no asset is configured.
- Uses **no hardcoded private keys or secrets** — the deployer key is supplied to `forge script` externally (e.g. `--private-key`/`--ledger`/`--trezor`, or an unlocked `--sender` with a keystore), never embedded in the script.
- **Deliberately does not deploy** `BitVVaultManager` (dead/superseded), `TestYieldStrategy` (test-only), any mock, `StaticPriceOracle`, or `KinkedInterestRateModel` — oracle/rate-model deployment and pool/RWA-asset registration are left as explicit, separate, asset-specific governance actions per Phase 10, matching the original script's existing design note.

**This script was not run.** It compiles (see Phase 15) but has not been executed against any network, per this milestone's explicit stop condition, and — per its own `require` — cannot be run to completion today because `CLEANVERSE_VALIDATOR_ADDRESS` has no confirmed real value (Phase 5/8).

`contracts/script/ValidateDeployment.s.sol` was created new this milestone (Phase 11) — see below.

## 10. Post-deployment configuration

### On-chain configuration

- Grant/verify roles per the Phase 4 matrix (deployer receives all roles by default via `BitVAccessManager`'s constructor; transfer/revoke per that table's recommendations).
- `BitVPoolManager.createPool(asset, PoolConfigParams)` for each supported asset — sets LTV, liquidation threshold/bonus, reserve factor, caps, interest rate model, price oracle.
- Deploy and wire `KinkedInterestRateModel` (or another `IInterestRateModel`) per asset via `setInterestRateModel`.
- Deploy and wire a price oracle per asset via `setPriceOracle` (or at `createPool` time) — see Phase 6 for why `StaticPriceOracle` is testnet-only.
- `BitVLendingManager.setCloseFactor` if a value other than the 50% default is desired.
- `BitVRWACollateralRegistry.registerAsset` per RWA asset, then `setAllowedDebtAsset`/`setCollateralCap` as needed, then `ORACLE_MANAGER_ROLE`'s `setOracleConfig` + `markPriceFresh` before the asset can become eligible for new activity.
- `BitVRWACollateralRegistry.setCVAAttestation` only for assets an admin is prepared to claim as CVA-intended (never implying Cleanverse approval — see disclaimer already enforced in the frontend, Build 08).
- `BitVCVAAdapter.setPolicyContract` + `verifyInterface` only once a real policy-contract address exists for a given token.
- `BitVYieldVault.setVaultCap`/`setMinDeposit` (both default to 0/no-deposits until explicitly set), `setPerformanceFeeBps`, `setMaxStrategyAllocationBps`/`setMinIdleReserveBps`, and `setStrategy` only once a real (or explicitly-labeled test) strategy is chosen.

### Off-chain configuration

- Register each Cleanverse-gated contract's address with Cleanverse (`POST /api/cooperate/validator/register`, per the CVI guide §5.4) — cannot happen before a validator address and Monad support are confirmed (Phase 5/8).
- Obtain Cleanverse API credentials (`CLEANVERSE_API_KEY`, `CLEANVERSE_API_BASE_URL`) — format/provisioning unconfirmed (Phase 8, `docs/cleanverse-integration-todo.md` items 6–7).
- Obtain a real WalletConnect/RainbowKit project ID (`NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`).
- Populate `services/contracts/addresses.ts`'s `contractAddresses`/`yieldVaults`/`rwaAssets`/`poolAssets` with real, deployed, verified addresses only (see Phase 12).
- Verify contract source on whatever block explorer Monad Testnet provides, if supported.
- Decide and execute the multisig/governance transfer for `DEFAULT_ADMIN_ROLE`/`PROTOCOL_ADMIN_ROLE`/each `Ownable` owner, if moving beyond a single-EOA testnet deployment.

## 11. Deployment validation plan

`contracts/script/ValidateDeployment.s.sol` (created this milestone, not run) checks, given deployed addresses supplied via environment variables:

- Chain ID matches `EXPECTED_CHAIN_ID` (fails loudly otherwise).
- Every core contract address is non-zero and has code (`addr.code.length > 0`).
- `EXPECTED_ADMIN_ADDRESS` actually holds `DEFAULT_ADMIN_ROLE`, `PROTOCOL_ADMIN_ROLE`, `RISK_MANAGER_ROLE`, `PAUSER_ROLE`, and `RWA_ADMIN_ROLE`.
- `BitVPoolManager.lendingManager` / `BitVLendingManager.POOL_MANAGER` point at each other correctly.
- `BitVLendingManager.bitScoreManager` / `BitScoreManager.lendingManager` point at each other correctly.
- `BitVLendingManager.rwaRegistry` / `BitVRWACollateralRegistry.POOL_MANAGER` reference the expected addresses.
- `BitVRWACollateralRegistry.cvaAdapter` references the expected `BitVCVAAdapter`.
- `BitVPoolManager.TREASURY` / `BitVLendingManager.TREASURY` both reference the expected treasury.
- `BitScoreManager.MAX_SCORE() == 100` (guards against ever validating against a stale 0–1000-scale deployment).

Not yet checked by this script (left for asset-specific validation once pools/RWA assets/vaults actually exist): per-pool configuration validity, RWA per-asset configuration validity, vault cap/fee sanity, oracle price sanity. These depend on asset-specific decisions this audit does not make up.

## 12. Frontend address configuration status

`services/contracts/addresses.ts` (Build 08) is already structured correctly for this milestone's purpose: `contractAddresses`, `yieldVaults`, `rwaAssets`, and `poolAssets` are all empty, typed registries with NatSpec explicitly forbidding placeholder/invented entries. **No change was made to this file** — it already does exactly what Phase 12 asks (stay empty until verified deployment addresses exist, so the dashboard continues rendering its empty/unavailable states rather than switching to a false "live" state). Populating it is future work, gated on Phase 5/8's Cleanverse blockers and real deployment.

## 13. Testnet smoke-test plan

See `docs/testnet-smoke-test.md` (created this milestone). Not executed — no deployment exists to test against yet.

## 14. Security check

| Item | Status |
|---|---|
| No private keys in repository | Confirmed — `Deploy.s.sol` reads the deployer key externally via `forge script`'s own signing options, never embeds one |
| No secrets in frontend | Confirmed — `.env.example` keeps every Cleanverse credential unprefixed (server-only); only public data (RPC URL, WalletConnect project ID, contract addresses) is `NEXT_PUBLIC_` |
| No hardcoded deployer credentials | Confirmed |
| No unrestricted admin paths | One item flagged, not a defect: every `Ownable`/role-gated function requires an explicit role or ownership — see Phase 4's flagged item about `owner_`/`complianceOwner` all being set to the deployer at deploy time, which is excessive concentrated privilege to carry forward, not an unrestricted path |
| No missing role assignments | Confirmed for the roles this audit checked (Phase 4); `BitVAccessManager`'s constructor grants every defined role to `admin` |
| No zero-address configuration | One item flagged: `BitVAccessManager(admin)` and `BitVYieldVault`'s `asset_` have no explicit zero-address guard (Phase 3) — not exploitable by anyone but the deployer, but worth deploy-time care |
| No accidental test contracts in deployment | Confirmed — `Deploy.s.sol` deploys none of `BitVVaultManager`, `TestYieldStrategy`, or any `contracts/test/mocks/*` contract |
| No fake Cleanverse addresses | Confirmed — `CLEANVERSE_VALIDATOR_ADDRESS` has no fallback and the script reverts if unset; `.env.example` leaves it empty |
| No fake oracle addresses | Confirmed — no oracle address is deployed or wired in `Deploy.s.sol`; `StaticPriceOracle` is explicitly documented as non-production wherever it appears |
| No fake token addresses | Confirmed — no asset address appears anywhere in this audit or the deployment script; `YIELD_VAULT_ASSET` is opt-in via env var and vault deployment is skipped entirely if unset |
| No CVA claims unsupported by Cleanverse documentation | Confirmed — Phase 8's table marks every unconfirmed CVA item as such; `BitVCVAAdapter.previewTransfer` still reverts unconditionally |

## 15. Build verification

- `forge build`: **PASS** (`Compiler run successful!`, via-ir profile, solc 0.8.24) — after this milestone's two new/changed script files.
- `forge test`: see chat final report for this run's live output (invariant suites run 256 fuzzed runs each and take several minutes) — baseline going into this milestone was 218/218 (12 suites, all 4 invariant suites 7+8+10+8=33 invariant tests), unchanged by this audit since no `contracts/src/**` file was modified.
- `npm run lint` / `npm run build`: see chat final report.

No test was weakened, no compiler error was suppressed, no `contracts/src/**` production contract was modified during this audit.

## 16. Deployment readiness table

| Requirement | Status | Evidence | Blocker | Action required |
|---|---|---|---|---|
| Monad Testnet RPC | READY | `.env.example`, `config/chains.ts` | — | none |
| Monad Testnet chain ID (10143) | READY (cross-checked, not primary-source-confirmed from this sandbox) | `docs/architecture.md` | — | re-verify against `docs.monad.xyz` when reachable |
| WalletConnect project ID | UNCONFIRMED | `.env.example` has empty value | Real project ID not yet obtained | Obtain and set `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` |
| `BitVAccessManager` deployment | READY | Phase 1/3 | — | none |
| `BitVTreasury` deployment | READY | Phase 1/3 | — | none |
| `BitScoreManager` deployment | READY | Phase 1/3 | — | none |
| `BitVCVAAdapter` deployment | READY | Phase 1/3 | — | none |
| Cleanverse CVI validator address | **BLOCKED** | Phase 5/8, `docs/cleanverse-integration-todo.md` | Cleanverse has not published a validator address for any network, including whether Monad is supported at all | Obtain confirmation directly from Cleanverse before deploying `BitVPoolManager`/`BitVLendingManager`/`BitVYieldVault` |
| `BitVPoolManager` deployment | **BLOCKED** | Constructor requires `complianceValidator` | Cleanverse validator address | Same as above |
| `BitVLendingManager` deployment | **BLOCKED** | Constructor requires `complianceValidator` + `poolManager` | Cleanverse validator address (transitively via PoolManager) | Same as above |
| `BitVRWACollateralRegistry` deployment | **BLOCKED** (transitively) | Constructor requires `poolManager` | PoolManager blocked | Resolves once PoolManager deploys |
| `BitVYieldVault` deployment | **BLOCKED** | Constructor requires `complianceValidator` + a real underlying asset | Cleanverse validator address + real asset address | Same as above, plus asset selection |
| Production price oracle | **BLOCKED** for real value; NOT REQUIRED for testnet-only demo | Phase 6 | No production-suitable oracle implemented or selected | Select/build a real oracle before any real-value deployment; `StaticPriceOracle` is acceptable only for an explicitly-labeled testnet demo |
| Real Monad Testnet asset addresses | UNCONFIRMED | Phase 7 | No asset addresses confirmed | Decide: deploy BitV's own labeled test tokens, or source confirmed real testnet asset addresses |
| Deployment script | READY (compiles; not run) | Phase 9, `contracts/script/Deploy.s.sol` | Blocked from actually running by the Cleanverse validator address | Run only once Cleanverse validator address is confirmed |
| Validation script | READY (compiles; not run) | Phase 11, `contracts/script/ValidateDeployment.s.sol` | Nothing to validate yet | Run immediately after any real deployment |
| Frontend address wiring | READY (intentionally empty) | Phase 12 | Waiting on real deployment | Populate `services/contracts/addresses.ts` only with confirmed post-deployment addresses |
| Multisig/governance for admin roles | NOT REQUIRED for MVP testnet deployment | Phase 4 | — | Recommended before any real value is at risk (see role matrix) |
| CVA transfer enforcement | NOT REQUIRED (explicitly out of scope) | Phase 8 | Cleanverse `canTransfer` signature unconfirmed | Do not implement until Cleanverse confirms the signature — this audit does not attempt it |

## 17. Final decision

**1. Is BitV ready to deploy to Monad Testnet?**
No — not as a full protocol. A meaningful subset (see #3) can deploy today.

**2. If NO, list every blocker.**
- Cleanverse has not confirmed a CVI validator address for any network, and has not confirmed Monad Testnet support at all — this blocks `BitVPoolManager`, `BitVLendingManager`, `BitVYieldVault`, and (transitively, since it needs `BitVPoolManager`) `BitVRWACollateralRegistry`.
- No production-suitable price oracle exists or has been selected — blocks any deployment intended to hold real value (does not block a testnet-only, explicitly-labeled demo using `StaticPriceOracle`).
- No real Monad Testnet asset addresses are confirmed in this repo — blocks pool/vault/RWA-asset configuration regardless of the above.
- `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` is unset — blocks full frontend wallet-connect functionality (not a contract blocker).
- Cleanverse API credentials/registration process is unconfirmed in detail — blocks actually registering any deployed contract with Cleanverse even once a validator address exists.

**3. Which contracts can safely deploy without Cleanverse?**
`BitVAccessManager`, `BitVTreasury`, `BitScoreManager`, `BitVCVAAdapter`, `KinkedInterestRateModel`, and (for an explicitly-labeled testnet-only demo) `StaticPriceOracle`. None of these inherit `BitVComplianceGuard`.

**4. Which contracts require the Cleanverse validator?**
`BitVPoolManager`, `BitVLendingManager`, `BitVYieldVault` (each directly, via their constructor), and `BitVRWACollateralRegistry` (transitively, since its constructor requires an already-deployed `BitVPoolManager`).

**5. Which contracts depend on unknown external addresses?**
`BitVPoolManager`/`BitVLendingManager`/`BitVYieldVault` (Cleanverse validator); `BitVYieldVault` also needs a real underlying asset address; any `createPool`/`registerAsset` call needs a real asset + oracle address, none of which are confirmed today.

**6. Can the dashboard be connected immediately after deployment?**
Yes, mechanically — once `services/contracts/addresses.ts` is populated with real addresses, the existing Build 08 dashboard reads live state through its existing hooks with no code change required. It will not show anything meaningful until pools/vaults/RWA assets are actually configured post-deployment, per Phase 10.

**7. What exact information must be obtained before deployment?**
(a) Cleanverse's confirmation of Monad Testnet support and a real `IAPassComplianceValidator` deployment address on it; (b) Cleanverse API credentials and the exact validator-registration process; (c) a decision on price oracle strategy (testnet-labeled `StaticPriceOracle` vs. a real feed) and, if real, its address; (d) confirmed real (or deliberately BitV-issued test) asset addresses for whichever pools/vaults/RWA collateral will be configured first; (e) a real WalletConnect/RainbowKit project ID; (f) a decision on whether the first deployment uses a single EOA admin or a multisig from day one.

**8. What is the safest deployment sequence?**
1. Deploy `BitVAccessManager`, `BitVTreasury`, `BitScoreManager`, `BitVCVAAdapter` (no external blockers).
2. Once Cleanverse's validator address is confirmed: deploy `BitVPoolManager`, then `BitVLendingManager`, then `BitVRWACollateralRegistry`; wire `setLendingManager`/`setBitScoreManager`/`setRwaRegistry`/`setCVAAdapter`.
3. Run `ValidateDeployment.s.sol` immediately and confirm every check passes before any asset-specific configuration.
4. Deploy/confirm a price oracle (testnet-labeled `StaticPriceOracle` for a demo, or a real feed) per asset.
5. `createPool` for the first supported asset(s), one at a time, with conservative caps.
6. Only then consider `BitVYieldVault` deployment (per asset) and `BitVRWACollateralRegistry.registerAsset` for any RWA collateral — both are separate, deliberate governance actions, not part of core deployment.
7. Register each Cleanverse-gated contract's address with Cleanverse off-chain before expecting `complianceVerify` to return anything but `false` for real users.
8. Only after all of the above: populate `services/contracts/addresses.ts` with the confirmed, verified addresses so the dashboard switches from empty/unavailable to live state.

## Prompt 15 status (2026-08-09)

Prompt 15 requested a full fresh Monad Testnet deployment and live
verification cycle (Phases 4-11 of that milestone). This session's
sandbox has confirmed-blocked network egress to
`testnet-rpc.monad.xyz`, `docs.cleanverse.com`, and
`uatapi.cleanverse.com` (all three tested live this milestone —
`403 CONNECT tunnel failed`), so none of the broadcast, live-validation,
or live-Cleanverse-verification phases could be executed. Phases 1-3
(repository/deployment-order audit, environment/secret-safety audit,
`forge build`/`forge test`/`npm run lint`/`npm run build`/Vitest) were
executed and are recorded in `docs/development-log.md`'s Milestone 15
entry and the Prompt 15 final report. See
`docs/deployment-addresses-template.md`'s "Prompt 15 status" section
for the specific consequence: the live Build 11 addresses predate
Prompt 14's `claimReserve`/`claimPoolReserve` code, so that
functionality has never been exercised on real Monad Testnet state.

## Prompt 16 status (2026-08-09)

Re-checked live this session: `testnet-rpc.monad.xyz`,
`docs.cleanverse.com`, and `uatapi.cleanverse.com` still all return
`403 CONNECT tunnel failed` from this sandbox — no change from Prompt
15. The fresh deployment, live validation, live Cleanverse
re-verification, and 18-step live smoke test Prompt 16 requested remain
unexecuted for the same reason. What Prompt 16 *could* close from this
sandbox was closed: the Treasury reserve-claim dashboard gap Prompt 15
identified now has a real hook, ABI, and UI panel (`/dashboard/settings`),
covered by 8 new Vitest tests — see `docs/development-log.md`'s
Milestone 16 entry. `services/contracts/addresses.ts` is unchanged; no
fresh deployment exists to populate it with.
