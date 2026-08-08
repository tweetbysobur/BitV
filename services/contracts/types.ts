import type { Address } from "viem";

/**
 * Smart-contract integration boundary — TYPE DEFINITIONS ONLY.
 *
 * BitV's protocol contracts (compliance, pools, lending, BitScore, yield
 * vaults, RWA collateral registry, CVA adapter, treasury) are designed and
 * implemented in `contracts/` (Foundry) but **not deployed anywhere** —
 * this module stays the single place the frontend imports contract
 * addresses/ABIs from once real deployment addresses exist. Never
 * populate `contractAddresses` with a guessed/placeholder address.
 */
export interface DeployedContract {
  address: Address;
  chainId: number;
}

/**
 * Every BitV protocol contract this dashboard reads from, mirroring
 * `contracts/src/core/*.sol` + `contracts/src/compliance/*.sol` exactly —
 * see docs/dashboard-implementation.md for the mapping.
 */
export type BitVContractName =
  | "AccessManager"
  | "ComplianceGuardPool" // BitVComplianceGuard as inherited by BitVPoolManager (self-scoped RuleV2/getRulesV2)
  | "PoolManager"
  | "LendingManager"
  | "BitScoreManager"
  | "Treasury"
  | "RWACollateralRegistry"
  | "CVAAdapter"
  | "YieldVault"; // a single vault instance; see YieldVaultRegistryEntry for multi-vault support

/** One deployed BitVYieldVault instance, plus the metadata the dashboard
 * needs that isn't derivable on-chain (whether its currently-wired
 * strategy is the non-production `TestYieldStrategy` — no on-chain flag
 * for this exists, so it is tracked here as an explicit, BitV-maintained
 * fact, never inferred or guessed). */
export interface YieldVaultRegistryEntry {
  address: Address;
  chainId: number;
  /** True only when BitV's own deployment records confirm the vault's
   * currently-configured strategy is `TestYieldStrategy` (non-production,
   * generates no real yield) — see docs/yield-vault-implementation.md.
   * Never set `false` without an equally explicit confirmation; when
   * unknown, leave the entry out entirely rather than guessing. */
  isTestStrategy: boolean;
}
