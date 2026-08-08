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
