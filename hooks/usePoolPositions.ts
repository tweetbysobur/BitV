"use client";

import { useReadContracts } from "wagmi";
import { bitVPoolManagerAbi, erc20Abi } from "@/services/contracts/abis";
import { useContractAddress } from "./useContractAddress";
import { useWalletStatus } from "./useWalletStatus";
import { poolAssets } from "@/services/contracts/addresses";
import type { DataState } from "@/lib/data-state";
import type { Address } from "viem";

export interface PoolPositionRow {
  assetAddress: Address;
  symbol: string | undefined;
  decimals: number | undefined;
  isActive: boolean;
  isPaused: boolean;
  isBorrowingEnabled: boolean;
  isCollateralEnabled: boolean;
  supplyCap: bigint;
  borrowCap: bigint;
  totalSupplied: bigint | undefined;
  totalBorrowed: bigint | undefined;
  availableLiquidity: bigint | undefined;
  utilizationRay: bigint | undefined;
  userBalance: bigint | undefined;
}

/** Reads BitVPoolManager.getPool + user balance for every known pool
 * asset (services/contracts/addresses.ts's `poolAssets` — empty until
 * real pools exist). */
export function usePoolPositions(): DataState<PoolPositionRow[]> {
  const { address: userAddress, state: walletState } = useWalletStatus();
  const poolManagerAddress = useContractAddress("PoolManager");
  const enabled = Boolean(poolManagerAddress) && poolAssets.length > 0;

  const { data, isLoading, isError } = useReadContracts({
    contracts: poolAssets.flatMap((asset) => [
      { address: poolManagerAddress, abi: bitVPoolManagerAbi, functionName: "getPool", args: [asset.address] },
      { address: poolManagerAddress, abi: bitVPoolManagerAbi, functionName: "totalSupplied", args: [asset.address] },
      { address: poolManagerAddress, abi: bitVPoolManagerAbi, functionName: "totalBorrowed", args: [asset.address] },
      { address: poolManagerAddress, abi: bitVPoolManagerAbi, functionName: "availableLiquidity", args: [asset.address] },
      { address: poolManagerAddress, abi: bitVPoolManagerAbi, functionName: "utilizationRay", args: [asset.address] },
      {
        address: poolManagerAddress,
        abi: bitVPoolManagerAbi,
        functionName: "balanceOf",
        args: userAddress ? [asset.address, userAddress] : undefined,
      },
      { address: asset.address, abi: erc20Abi, functionName: "symbol", args: [] },
      { address: asset.address, abi: erc20Abi, functionName: "decimals", args: [] },
    ]),
    query: { enabled },
  });

  if (!poolManagerAddress) {
    return { status: "unavailable", reason: "BitVPoolManager is not configured for this network." };
  }
  if (poolAssets.length === 0) return { status: "empty" };
  if (isLoading) return { status: "loading" };
  if (isError || !data) return { status: "error", message: "Could not read pool data from the contract." };

  const rows: PoolPositionRow[] = poolAssets.map((asset, i) => {
    const [pool, supplied, borrowed, available, utilization, userBalance, symbol, decimals] = data.slice(
      i * 8,
      i * 8 + 8,
    );
    if (pool?.status !== "success") {
      return {
        assetAddress: asset.address,
        symbol: undefined,
        decimals: undefined,
        isActive: false,
        isPaused: false,
        isBorrowingEnabled: false,
        isCollateralEnabled: false,
        supplyCap: 0n,
        borrowCap: 0n,
        totalSupplied: undefined,
        totalBorrowed: undefined,
        availableLiquidity: undefined,
        utilizationRay: undefined,
        userBalance: undefined,
      };
    }
    const p = pool.result as {
      isActive: boolean;
      isPaused: boolean;
      isBorrowingEnabled: boolean;
      isCollateralEnabled: boolean;
      supplyCap: bigint;
      borrowCap: bigint;
    };
    return {
      assetAddress: asset.address,
      symbol: symbol?.status === "success" ? (symbol.result as string) : undefined,
      decimals: decimals?.status === "success" ? (decimals.result as number) : undefined,
      isActive: p.isActive,
      isPaused: p.isPaused,
      isBorrowingEnabled: p.isBorrowingEnabled,
      isCollateralEnabled: p.isCollateralEnabled,
      supplyCap: p.supplyCap,
      borrowCap: p.borrowCap,
      totalSupplied: supplied?.status === "success" ? (supplied.result as bigint) : undefined,
      totalBorrowed: borrowed?.status === "success" ? (borrowed.result as bigint) : undefined,
      availableLiquidity: available?.status === "success" ? (available.result as bigint) : undefined,
      utilizationRay: utilization?.status === "success" ? (utilization.result as bigint) : undefined,
      userBalance:
        walletState === "connected" && userBalance?.status === "success"
          ? (userBalance.result as bigint)
          : undefined,
    };
  });

  return { status: "loaded", data: rows };
}
