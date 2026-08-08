import type { BitVContractName, DeployedContract, YieldVaultRegistryEntry } from "./types";

/**
 * Deployed BitV contract addresses on Monad Testnet, keyed by contract
 * name. Empty until each contract is actually deployed — do not populate
 * with placeholder/fake addresses. Every dashboard read must treat a
 * missing entry as "not connected," never as "zero"/"empty."
 */
export const contractAddresses: Partial<Record<BitVContractName, DeployedContract>> = {};

/** Deployed BitVYieldVault instances. Empty until real vaults are
 * deployed and their strategy composition is confirmed — see
 * YieldVaultRegistryEntry's NatSpec for why `isTestStrategy` must never
 * be guessed. */
export const yieldVaults: readonly YieldVaultRegistryEntry[] = [];

/** RWA collateral assets the dashboard should query
 * BitVRWACollateralRegistry about. Empty until real assets are
 * registered and their addresses are confirmed — never invented. */
export const rwaAssets: readonly DeployedContract[] = [];

/** Debt/collateral pool assets the dashboard should query
 * BitVPoolManager about. Empty until real pools exist. */
export const poolAssets: readonly DeployedContract[] = [];
