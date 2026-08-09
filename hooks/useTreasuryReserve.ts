"use client";

import { useReadContracts } from "wagmi";
import { bitVPoolManagerAbi, bitVAccessManagerAbi, erc20Abi } from "@/services/contracts/abis";
import { useContractAddress } from "./useContractAddress";
import { useWalletStatus } from "./useWalletStatus";
import { poolAssets, treasuryReserveClaimSupported } from "@/services/contracts/addresses";
import { PROTOCOL_ADMIN_ROLE } from "@/lib/treasury";
import type { DataState } from "@/lib/data-state";
import type { Address } from "viem";

export interface TreasuryReserveRow {
  assetAddress: Address;
  symbol: string | undefined;
  reserveBalance: bigint;
}

export interface TreasuryReserveResult {
  rows: TreasuryReserveRow[];
  /** Whether the connected wallet holds PROTOCOL_ADMIN_ROLE on
   * BitVAccessManager — mirrors, never replaces, the contract's own
   * enforcement in BitVTreasury.claimPoolReserve. */
  isAdmin: boolean;
}

/** Reads BitVPoolManager.reserveBalance (Prompt 14) for every
 * configured pool asset, plus whether the connected wallet is a
 * protocol admin — the data the Treasury reserve-claim panel
 * (Prompt 16, Settings page) needs. Never fabricates a reserve value:
 * an unconfigured PoolManager or empty asset list surfaces as
 * "unavailable"/"empty", not zero. */
export function useTreasuryReserve(): DataState<TreasuryReserveResult> {
  const poolManagerAddress = useContractAddress("PoolManager");
  const accessManagerAddress = useContractAddress("AccessManager");
  const { address: userAddress, state: walletState } = useWalletStatus();

  const enabled =
    treasuryReserveClaimSupported &&
    walletState === "connected" &&
    Boolean(poolManagerAddress) &&
    Boolean(accessManagerAddress) &&
    Boolean(userAddress);

  const { data, isLoading, isError } = useReadContracts({
    contracts: [
      ...poolAssets.flatMap((asset) => [
        {
          address: poolManagerAddress,
          abi: bitVPoolManagerAbi,
          functionName: "reserveBalance",
          args: [asset.address],
        } as const,
        { address: asset.address, abi: erc20Abi, functionName: "symbol", args: [] } as const,
      ]),
      {
        address: accessManagerAddress,
        abi: bitVAccessManagerAbi,
        functionName: "hasRole",
        args: userAddress ? [PROTOCOL_ADMIN_ROLE, userAddress] : undefined,
      } as const,
    ],
    query: { enabled },
  });

  if (!treasuryReserveClaimSupported) {
    return {
      status: "unavailable",
      reason:
        "The currently deployed PoolManager/Treasury predate the reserve-claim feature (Prompt 14) — a redeployment is required before this is usable on Monad Testnet. Verified in Foundry only (240/240), never on live testnet state.",
    };
  }
  if (!poolManagerAddress || !accessManagerAddress) {
    return { status: "unavailable", reason: "PoolManager or AccessManager is not configured for this network." };
  }
  if (walletState !== "connected") {
    return { status: "unavailable", reason: "Connect a wallet to read Treasury reserve data." };
  }
  if (poolAssets.length === 0) return { status: "empty" };
  if (isLoading) return { status: "loading" };
  if (isError || !data) return { status: "error", message: "Could not read Treasury reserve data." };

  const assetResults = data.slice(0, poolAssets.length * 2);
  const adminResult = data[data.length - 1];

  const rows: TreasuryReserveRow[] = poolAssets.map((asset, i) => {
    const [reserve, symbol] = assetResults.slice(i * 2, i * 2 + 2);
    return {
      assetAddress: asset.address,
      symbol: symbol?.status === "success" ? (symbol.result as string) : undefined,
      reserveBalance: reserve?.status === "success" ? (reserve.result as bigint) : 0n,
    };
  });

  const isAdmin = adminResult?.status === "success" ? Boolean(adminResult.result) : false;

  return { status: "loaded", data: { rows, isAdmin } };
}
