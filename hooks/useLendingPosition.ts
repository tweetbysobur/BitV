"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { bitVLendingManagerAbi, erc20Abi } from "@/services/contracts/abis";
import { useContractAddress } from "./useContractAddress";
import { useWalletStatus } from "./useWalletStatus";
import { poolAssets } from "@/services/contracts/addresses";
import type { DataState } from "@/lib/data-state";
import type { Address } from "viem";

export interface AccountDataResult {
  totalCollateralValue: bigint;
  totalDebtValue: bigint;
  availableBorrowValue: bigint;
  weightedMaxLtvValue: bigint;
  currentLiquidationThresholdBps: bigint;
  healthFactorRay: bigint;
}

export interface AssetBalance {
  assetAddress: Address;
  symbol: string | undefined;
  decimals: number | undefined;
  amount: bigint | undefined;
}

export interface LendingPositionData {
  accountData: AccountDataResult;
  effectiveAvailableBorrowValue: bigint;
  collateralByAsset: AssetBalance[];
  debtByAsset: AssetBalance[];
}

/** Reads BitVLendingManager.getUserAccountData plus per-asset collateral/
 * debt balances for every known pool asset (services/contracts/
 * addresses.ts's `poolAssets`) — never assumes a single collateral or
 * debt asset. `poolAssets` is empty until real pools are deployed, so
 * this reports "unavailable" until then, matching real state. */
export function useLendingPosition(): DataState<LendingPositionData> {
  const { address: userAddress, state: walletState } = useWalletStatus();
  const lendingManagerAddress = useContractAddress("LendingManager");

  const enabled = walletState === "connected" && Boolean(userAddress) && Boolean(lendingManagerAddress);

  const accountDataRead = useReadContract({
    address: lendingManagerAddress,
    abi: bitVLendingManagerAbi,
    functionName: "getUserAccountData",
    args: userAddress ? [userAddress] : undefined,
    query: { enabled },
  });

  const effectiveAvailableRead = useReadContract({
    address: lendingManagerAddress,
    abi: bitVLendingManagerAbi,
    functionName: "getEffectiveAvailableBorrowValue",
    args: userAddress ? [userAddress] : undefined,
    query: { enabled },
  });

  const perAssetReads = useReadContracts({
    contracts: poolAssets.flatMap((asset) => [
      {
        address: lendingManagerAddress,
        abi: bitVLendingManagerAbi,
        functionName: "getCollateralBalance",
        args: userAddress ? [userAddress, asset.address] : undefined,
      },
      {
        address: lendingManagerAddress,
        abi: bitVLendingManagerAbi,
        functionName: "getCurrentDebt",
        args: userAddress ? [userAddress, asset.address] : undefined,
      },
      { address: asset.address, abi: erc20Abi, functionName: "symbol", args: [] },
      { address: asset.address, abi: erc20Abi, functionName: "decimals", args: [] },
    ]),
    query: { enabled: enabled && poolAssets.length > 0 },
  });

  if (!lendingManagerAddress) {
    return { status: "unavailable", reason: "BitVLendingManager is not configured for this network." };
  }
  if (walletState !== "connected") return { status: "unavailable", reason: "Wallet not connected." };
  if (accountDataRead.isLoading || effectiveAvailableRead.isLoading) return { status: "loading" };
  if (accountDataRead.isError || effectiveAvailableRead.isError || !accountDataRead.data) {
    return { status: "error", message: "Could not read lending position from the contract." };
  }
  if (poolAssets.length === 0) {
    // No known pool assets configured — accountData itself may still be
    // a real, meaningful zero-position result, but per-asset tables have
    // nothing to show; render the top-level figures, empty tables.
    return {
      status: "loaded",
      data: {
        accountData: accountDataRead.data,
        effectiveAvailableBorrowValue: effectiveAvailableRead.data ?? 0n,
        collateralByAsset: [],
        debtByAsset: [],
      },
    };
  }

  if (perAssetReads.isLoading) return { status: "loading" };
  const results = perAssetReads.data;
  if (!results) return { status: "error", message: "Could not read per-asset positions from the contract." };

  const collateralByAsset: AssetBalance[] = [];
  const debtByAsset: AssetBalance[] = [];
  poolAssets.forEach((asset, i) => {
    const [collateral, debt, symbol, decimals] = results.slice(i * 4, i * 4 + 4);
    const symbolValue = symbol?.status === "success" ? (symbol.result as string) : undefined;
    const decimalsValue = decimals?.status === "success" ? (decimals.result as number) : undefined;
    collateralByAsset.push({
      assetAddress: asset.address,
      symbol: symbolValue,
      decimals: decimalsValue,
      amount: collateral?.status === "success" ? (collateral.result as bigint) : undefined,
    });
    debtByAsset.push({
      assetAddress: asset.address,
      symbol: symbolValue,
      decimals: decimalsValue,
      amount: debt?.status === "success" ? (debt.result as bigint) : undefined,
    });
  });

  return {
    status: "loaded",
    data: {
      accountData: accountDataRead.data,
      effectiveAvailableBorrowValue: effectiveAvailableRead.data ?? 0n,
      collateralByAsset,
      debtByAsset,
    },
  };
}
