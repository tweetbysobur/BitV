"use client";

import { useReadContracts } from "wagmi";
import { bitScoreManagerAbi } from "@/services/contracts/abis";
import { useContractAddress } from "./useContractAddress";
import { useWalletStatus } from "./useWalletStatus";
import { getBitScoreTierFromIndex, type BitScoreTier } from "@/lib/bitscore";
import type { DataState } from "@/lib/data-state";

export interface BitScoreData {
  score: number;
  tier: BitScoreTier;
}

/** Reads BitScoreManager.getScore/getTier for the connected wallet — the
 * current 0-100 scale (uint8), never the legacy 0-1000 model. Returns a
 * full DataState so the UI never shows a fabricated score while waiting
 * on or failing a real read. */
export function useBitScore(): DataState<BitScoreData> {
  const { address: userAddress, state: walletState } = useWalletStatus();
  const bitScoreManagerAddress = useContractAddress("BitScoreManager");

  const enabled = walletState === "connected" && Boolean(userAddress) && Boolean(bitScoreManagerAddress);

  const { data, isLoading, isError } = useReadContracts({
    contracts: [
      {
        address: bitScoreManagerAddress,
        abi: bitScoreManagerAbi,
        functionName: "getScore",
        args: userAddress ? [userAddress] : undefined,
      },
      {
        address: bitScoreManagerAddress,
        abi: bitScoreManagerAbi,
        functionName: "getTier",
        args: userAddress ? [userAddress] : undefined,
      },
    ],
    query: { enabled },
  });

  if (!bitScoreManagerAddress) return { status: "unavailable", reason: "BitScoreManager is not configured for this network." };
  if (walletState !== "connected") return { status: "unavailable", reason: "Wallet not connected." };
  if (isLoading) return { status: "loading" };
  if (isError || !data) return { status: "error", message: "Could not read BitScore from the contract." };

  const [scoreResult, tierResult] = data;
  if (scoreResult.status !== "success" || tierResult.status !== "success") {
    return { status: "error", message: "Could not read BitScore from the contract." };
  }

  return {
    status: "loaded",
    data: { score: scoreResult.result, tier: getBitScoreTierFromIndex(tierResult.result) },
  };
}
