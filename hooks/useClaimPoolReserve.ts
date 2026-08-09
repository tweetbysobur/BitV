"use client";

import { useCallback } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { bitVTreasuryAbi } from "@/services/contracts/abis";
import { deriveClaimPoolReserveState, type ClaimPoolReserveState } from "@/lib/treasury";
import type { Address } from "viem";

export type { ClaimPoolReserveState };

export interface ClaimPoolReserveResult {
  state: ClaimPoolReserveState;
  /** Set once the wallet returns a hash — before the receipt confirms. */
  txHash: `0x${string}` | undefined;
  /** Populated only when `state === "error"` — the wallet/RPC's own
   * message (e.g. a user rejection, or the contract's own
   * CallerNotTreasury/AmountExceedsBalance revert reason), never a
   * generic "something went wrong." */
  errorMessage: string | undefined;
  claim: (args: { treasuryAddress: Address; poolManagerAddress: Address; asset: Address; amount: bigint }) => void;
  reset: () => void;
}

/** Write path for BitVTreasury.claimPoolReserve (Prompt 14/16) —
 * distinct pending/confirming/success/error states so the UI never
 * shows "success" from a submitted-but-unconfirmed or reverted
 * transaction. This is a protocol-administration action: callers are
 * expected to have already gated the UI on PROTOCOL_ADMIN_ROLE (see
 * useTreasuryReserve's `isAdmin`) — this hook does not re-check that
 * itself, since the contract enforces it regardless and re-deriving it
 * here would just duplicate that check without adding safety. */
export function useClaimPoolReserve(): ClaimPoolReserveResult {
  const { writeContract, data: txHash, error: writeError, status: writeStatus, reset: resetWrite } = useWriteContract();

  const {
    status: receiptStatus,
    error: receiptError,
  } = useWaitForTransactionReceipt({ hash: txHash, query: { enabled: Boolean(txHash) } });

  const claim = useCallback(
    ({
      treasuryAddress,
      poolManagerAddress,
      asset,
      amount,
    }: {
      treasuryAddress: Address;
      poolManagerAddress: Address;
      asset: Address;
      amount: bigint;
    }) => {
      writeContract({
        address: treasuryAddress,
        abi: bitVTreasuryAbi,
        functionName: "claimPoolReserve",
        args: [poolManagerAddress, asset, amount],
      });
    },
    [writeContract],
  );

  const state = deriveClaimPoolReserveState(writeStatus, txHash ? receiptStatus : undefined);

  const errorMessage = writeError?.message ?? receiptError?.message;

  return {
    state,
    txHash,
    errorMessage,
    claim,
    reset: resetWrite,
  };
}
