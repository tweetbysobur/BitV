import type { Address } from "viem";

/**
 * Smart-contract integration boundary — TYPE DEFINITIONS ONLY.
 *
 * No BitV protocol contracts (lending, pools, vaults, BitScore) exist yet.
 * This module exists so the frontend has one place to import contract
 * addresses/ABIs from once contracts are designed and deployed to Monad
 * Testnet — it must stay empty of protocol-specific shapes until then.
 */
export interface DeployedContract {
  address: Address;
  chainId: number;
}

/**
 * Names this registry will hold entries for once each contract is designed
 * and deployed. Listing the key set (with no addresses/ABIs attached yet)
 * lets `contractAddresses` be typed as this milestone's contracts land,
 * without the shape changing later.
 */
export type BitVContractName =
  | "AccessManager"
  | "PoolManager"
  | "LendingManager"
  | "VaultManager"
  | "BitScoreManager"
  | "Treasury";
