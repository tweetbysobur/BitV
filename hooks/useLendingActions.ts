"use client";

import { useCallback } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { erc20Abi, bitVLendingManagerAbi } from "@/services/contracts/abis";
import { derivePoolActionState, type PoolActionState } from "@/lib/poolAction";
import type { Address } from "viem";

export interface LendingWriteResult {
  state: PoolActionState;
  txHash: `0x${string}` | undefined;
  errorMessage: string | undefined;
  reset: () => void;
}

type LendingActionName = "depositCollateral" | "withdrawCollateral" | "borrow" | "repay";

function useLendingWrite(functionName: LendingActionName): LendingWriteResult & {
  send: (args: { lendingManagerAddress: Address; assetAddress: Address; amount: bigint }) => void;
} {
  const { writeContract, data: txHash, error: writeError, status: writeStatus, reset } = useWriteContract();
  const { status: receiptStatus, error: receiptError } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: Boolean(txHash) },
  });

  const send = useCallback(
    ({ lendingManagerAddress, assetAddress, amount }: { lendingManagerAddress: Address; assetAddress: Address; amount: bigint }) => {
      writeContract({
        address: lendingManagerAddress,
        abi: bitVLendingManagerAbi,
        functionName,
        args: [assetAddress, amount],
      });
    },
    [writeContract, functionName],
  );

  return {
    state: derivePoolActionState(writeStatus, txHash ? receiptStatus : undefined),
    txHash,
    errorMessage: writeError?.message ?? receiptError?.message,
    send,
    reset,
  };
}

/** Write path for ERC20.approve(lendingManager, amount) — required
 * before BitVLendingManager.depositCollateral, which pulls tokens via
 * transferFrom directly (a separate allowance from the one used for
 * BitVPoolManager.deposit, since it's a different spender). */
export function useApproveLendingManager(): LendingWriteResult & {
  approve: (args: { assetAddress: Address; spender: Address; amount: bigint }) => void;
} {
  const { writeContract, data: txHash, error: writeError, status: writeStatus, reset } = useWriteContract();
  const { status: receiptStatus, error: receiptError } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: Boolean(txHash) },
  });

  const approve = useCallback(
    ({ assetAddress, spender, amount }: { assetAddress: Address; spender: Address; amount: bigint }) => {
      writeContract({ address: assetAddress, abi: erc20Abi, functionName: "approve", args: [spender, amount] });
    },
    [writeContract],
  );

  return {
    state: derivePoolActionState(writeStatus, txHash ? receiptStatus : undefined),
    txHash,
    errorMessage: writeError?.message ?? receiptError?.message,
    approve,
    reset,
  };
}

export function useDepositCollateral() {
  return useLendingWrite("depositCollateral");
}

export function useWithdrawCollateral() {
  return useLendingWrite("withdrawCollateral");
}

export function useBorrow() {
  return useLendingWrite("borrow");
}

export function useRepay() {
  return useLendingWrite("repay");
}
