"use client";

import { useReadContracts } from "wagmi";
import { bitVRWACollateralRegistryAbi, erc20Abi, priceOracleAbi } from "@/services/contracts/abis";
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
  /** Testnet oracle is the only implementation deployed — never
   * production market pricing. See docs/oracle-deployment-plan.md. */
  oraclePrice: bigint | undefined;
  oraclePriceDecimals: number | undefined;
  maxOracleStalenessSeconds: number;
  lastPriceVerifiedTimestamp: number;
  eligibleForNewActivity: boolean;
  adminAttestedCVA: boolean;
}

/** Reads BitVRWACollateralRegistry.getAssetConfig +
 * isEligibleForNewActivity, plus a live IPriceOracle.getPrice read, for
 * every RWA asset BitV has registered (services/contracts/
 * addresses.ts's `rwaAssets` — empty until real assets are registered
 * and confirmed). The price/staleness fields exist so the UI can
 * explain *why* an asset isn't eligible (stale/zero price vs. Frozen/
 * Delisted status) instead of only reporting the boolean result. */
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

  const oracleAddresses = rwaAssets.map((asset, i) => {
    const config = data?.[i * 3];
    if (config?.status !== "success") return undefined;
    const cfg = config.result as { oracle: Address };
    return cfg.oracle;
  });

  const oraclesEnabled = enabled && !isLoading && !isError && oracleAddresses.some((o) => o !== undefined);

  const { data: priceData, isLoading: pricesLoading } = useReadContracts({
    contracts: rwaAssets.map((asset, i) => ({
      address: oracleAddresses[i],
      abi: priceOracleAbi,
      functionName: "getPrice" as const,
      args: [asset.address] as const,
    })),
    query: { enabled: oraclesEnabled },
  });

  if (!registryAddress) {
    return { status: "unavailable", reason: "BitVRWACollateralRegistry is not configured for this network." };
  }
  if (rwaAssets.length === 0) return { status: "empty" };
  if (isLoading) return { status: "loading" };
  if (isError || !data) return { status: "error", message: "Could not read RWA asset data from the registry." };
  if (oraclesEnabled && pricesLoading) return { status: "loading" };

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
        oraclePrice: undefined,
        oraclePriceDecimals: undefined,
        maxOracleStalenessSeconds: 0,
        lastPriceVerifiedTimestamp: 0,
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
      maxOracleStalenessSeconds: number;
      lastPriceVerifiedTimestamp: number;
      adminAttestedCVA: boolean;
    };
    const priceResult = priceData?.[i];
    const price = priceResult?.status === "success" ? (priceResult.result as readonly [bigint, number]) : undefined;
    return {
      assetAddress: asset.address,
      symbol: symbol?.status === "success" ? (symbol.result as string) : undefined,
      status: getRWAAssetStatusFromIndex(cfg.status),
      ltvBps: cfg.ltvBps,
      liquidationThresholdBps: cfg.liquidationThresholdBps,
      collateralCap: cfg.collateralCap,
      oracle: cfg.oracle,
      oraclePrice: price?.[0],
      oraclePriceDecimals: price?.[1],
      maxOracleStalenessSeconds: Number(cfg.maxOracleStalenessSeconds),
      lastPriceVerifiedTimestamp: Number(cfg.lastPriceVerifiedTimestamp),
      eligibleForNewActivity: eligible?.status === "success" ? (eligible.result as boolean) : false,
      adminAttestedCVA: cfg.adminAttestedCVA,
    };
  });

  return { status: "loaded", data: rows };
}
