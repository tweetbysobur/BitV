"use client";

import { useReadContracts } from "wagmi";
import { bitVRWACollateralRegistryAbi, erc20Abi } from "@/services/contracts/abis";
import { useContractAddress } from "./useContractAddress";
import { rwaAssets } from "@/services/contracts/addresses";
import { getRWAAssetStatusFromIndex, type RWAAssetStatus } from "@/lib/rwa";
import type { DataState } from "@/lib/data-state";
import type { Address } from "viem";

export interface RWAAssetRow {
  assetAddress: Address;
  symbol: string | undefined;
  status: RWAAssetStatus;
  ltvBps: number;
  liquidationThresholdBps: number;
  collateralCap: bigint;
  oracle: Address;
  eligibleForNewActivity: boolean;
  adminAttestedCVA: boolean;
}

/** Reads BitVRWACollateralRegistry.getAssetConfig +
 * isEligibleForNewActivity for every RWA asset BitV has registered
 * (services/contracts/addresses.ts's `rwaAssets` — empty until real
 * assets are registered and confirmed). */
export function useRWAAssets(): DataState<RWAAssetRow[]> {
  const registryAddress = useContractAddress("RWACollateralRegistry");
  const enabled = Boolean(registryAddress) && rwaAssets.length > 0;

  const { data, isLoading, isError } = useReadContracts({
    contracts: rwaAssets.flatMap((asset) => [
      {
        address: registryAddress,
        abi: bitVRWACollateralRegistryAbi,
        functionName: "getAssetConfig",
        args: [asset.address],
      },
      {
        address: registryAddress,
        abi: bitVRWACollateralRegistryAbi,
        functionName: "isEligibleForNewActivity",
        args: [asset.address],
      },
      { address: asset.address, abi: erc20Abi, functionName: "symbol", args: [] },
    ]),
    query: { enabled },
  });

  if (!registryAddress) {
    return { status: "unavailable", reason: "BitVRWACollateralRegistry is not configured for this network." };
  }
  if (rwaAssets.length === 0) return { status: "empty" };
  if (isLoading) return { status: "loading" };
  if (isError || !data) return { status: "error", message: "Could not read RWA asset data from the registry." };

  const rows: RWAAssetRow[] = rwaAssets.map((asset, i) => {
    const [config, eligible, symbol] = data.slice(i * 3, i * 3 + 3);
    if (config?.status !== "success") {
      return {
        assetAddress: asset.address,
        symbol: undefined,
        status: "Unregistered",
        ltvBps: 0,
        liquidationThresholdBps: 0,
        collateralCap: 0n,
        oracle: "0x0000000000000000000000000000000000000000",
        eligibleForNewActivity: false,
        adminAttestedCVA: false,
      };
    }
    const cfg = config.result as {
      status: number;
      ltvBps: number;
      liquidationThresholdBps: number;
      collateralCap: bigint;
      oracle: Address;
      adminAttestedCVA: boolean;
    };
    return {
      assetAddress: asset.address,
      symbol: symbol?.status === "success" ? (symbol.result as string) : undefined,
      status: getRWAAssetStatusFromIndex(cfg.status),
      ltvBps: cfg.ltvBps,
      liquidationThresholdBps: cfg.liquidationThresholdBps,
      collateralCap: cfg.collateralCap,
      oracle: cfg.oracle,
      eligibleForNewActivity: eligible?.status === "success" ? (eligible.result as boolean) : false,
      adminAttestedCVA: cfg.adminAttestedCVA,
    };
  });

  return { status: "loaded", data: rows };
}
