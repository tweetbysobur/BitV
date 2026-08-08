import type { BitVContractName, DeployedContract } from "./types";

/**
 * Deployed BitV contract addresses on Monad Testnet, keyed by contract
 * name. Empty until each contract (AccessManager, PoolManager,
 * LendingManager, VaultManager, BitScoreManager, Treasury) is designed,
 * written, and actually deployed — do not populate with placeholder/fake
 * addresses.
 */
export const contractAddresses: Partial<Record<BitVContractName, DeployedContract>> = {};
