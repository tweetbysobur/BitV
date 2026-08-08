"use client";

import { useReadContracts } from "wagmi";
import { bitVYieldVaultAbi } from "@/services/contracts/abis";
import { yieldVaults } from "@/services/contracts/addresses";
import { useWalletStatus } from "./useWalletStatus";
import type { DataState } from "@/lib/data-state";
import type { Address } from "viem";

export interface VaultPositionRow {
  vaultAddress: Address;
  isTestStrategy: boolean;
  underlyingAsset: Address | undefined;
  underlyingSymbol: string | undefined;
  userShares: bigint | undefined;
  userUnderlyingValue: bigint | undefined;
  totalAssets: bigint | undefined;
  strategyAddress: Address | undefined;
  depositsPaused: boolean | undefined;
  withdrawalsPaused: boolean | undefined;
  performanceFeeBps: bigint | undefined;
}

/** Reads every deployed BitVYieldVault (services/contracts/
 * addresses.ts's `yieldVaults` — empty until real vaults are deployed)
 * for the connected wallet's position. `isTestStrategy` comes only from
 * that static registry, never inferred — see lib/vault.ts. */
export function useVaultPositions(): DataState<VaultPositionRow[]> {
  const { address: userAddress, state: walletState } = useWalletStatus();
  const enabled = walletState === "connected" && Boolean(userAddress) && yieldVaults.length > 0;

  const { data, isLoading, isError } = useReadContracts({
    contracts: yieldVaults.flatMap((vault) => [
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "asset", args: [] },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "balanceOf", args: userAddress ? [userAddress] : undefined },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "totalAssets", args: [] },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "strategy", args: [] },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "depositsPaused", args: [] },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "withdrawalsPaused", args: [] },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "performanceFeeBps", args: [] },
    ]),
    query: { enabled },
  });

  if (yieldVaults.length === 0) return { status: "empty" };
  if (walletState !== "connected") return { status: "unavailable", reason: "Wallet not connected." };
  if (isLoading) return { status: "loading" };
  if (isError || !data) return { status: "error", message: "Could not read vault data from the contract." };

  const rows: VaultPositionRow[] = yieldVaults.map((vault, i) => {
    const [asset, shares, total, strategy, depositsPaused, withdrawalsPaused, feeBps] = data.slice(
      i * 7,
      i * 7 + 7,
    );
    const underlyingAsset = asset?.status === "success" ? (asset.result as Address) : undefined;
    return {
      vaultAddress: vault.address,
      isTestStrategy: vault.isTestStrategy,
      underlyingAsset,
      underlyingSymbol: undefined, // resolved separately per-symbol if the underlying is known
      userShares: shares?.status === "success" ? (shares.result as bigint) : undefined,
      userUnderlyingValue: undefined, // requires convertToAssets(userShares); computed by the component from userShares if needed
      totalAssets: total?.status === "success" ? (total.result as bigint) : undefined,
      strategyAddress: strategy?.status === "success" ? (strategy.result as Address) : undefined,
      depositsPaused: depositsPaused?.status === "success" ? (depositsPaused.result as boolean) : undefined,
      withdrawalsPaused:
        withdrawalsPaused?.status === "success" ? (withdrawalsPaused.result as boolean) : undefined,
      performanceFeeBps: feeBps?.status === "success" ? (feeBps.result as bigint) : undefined,
    };
  });

  return { status: "loaded", data: rows };
}
