"use client";

import { useCallback } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { erc20Abi, bitVPoolManagerAbi } from "@/services/contracts/abis";
import { derivePoolActionState, type PoolActionState } from "@/lib/poolAction";
import type { Address } from "viem";

export interface PoolWriteResult {
  state: PoolActionState;
  txHash: `0x${string}` | undefined;
  errorMessage: string | undefined;
  reset: () => void;
}

/** Read the connected wallet's token balance and its current
 * allowance for the PoolManager, so the Supply panel can decide
 * whether an approve step is still needed. */
export function useSupplyAllowance(assetAddress: Address | undefined, poolManagerAddress: Address | undefined) {
  const { address: account } = useAccount();

  const balance = useReadContract({
    address: assetAddress,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: account ? [account] : undefined,
    query: { enabled: Boolean(assetAddress && account) },
  });

  const allowance = useReadContract({
    address: assetAddress,
    abi: erc20Abi,
    functionName: "allowance",
    args: account && poolManagerAddress ? [account, poolManagerAddress] : undefined,
    query: { enabled: Boolean(assetAddress && account && poolManagerAddress) },
  });

  return {
    balance: balance.data,
    allowance: allowance.data,
    refetch: () => {
      void balance.refetch();
      void allowance.refetch();
    },
  };
}

/** Write path for ERC20.approve(poolManager, amount) — the first step
 * of the supply flow, only needed when the current allowance is below
 * the amount the user wants to supply. */
export function useApproveAsset(): PoolWriteResult & {
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

/** Write path for BitVPoolManager.deposit(asset, amount) — supplying
 * an already-approved amount into the pool as collateral/liquidity. */
export function useDepositToPool(): PoolWriteResult & {
  deposit: (args: { poolManagerAddress: Address; assetAddress: Address; amount: bigint }) => void;
} {
  const { writeContract, data: txHash, error: writeError, status: writeStatus, reset } = useWriteContract();
  const { status: receiptStatus, error: receiptError } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: Boolean(txHash) },
  });

  const deposit = useCallback(
    ({ poolManagerAddress, assetAddress, amount }: { poolManagerAddress: Address; assetAddress: Address; amount: bigint }) => {
      writeContract({
        address: poolManagerAddress,
        abi: bitVPoolManagerAbi,
        functionName: "deposit",
        args: [assetAddress, amount],
      });
    },
    [writeContract],
  );

  return {
    state: derivePoolActionState(writeStatus, txHash ? receiptStatus : undefined),
    txHash,
    errorMessage: writeError?.message ?? receiptError?.message,
    deposit,
    reset,
  };
}

/** Write path for BitVPoolManager.withdraw(asset, amount). */
export function useWithdrawFromPool(): PoolWriteResult & {
  withdraw: (args: { poolManagerAddress: Address; assetAddress: Address; amount: bigint }) => void;
} {
  const { writeContract, data: txHash, error: writeError, status: writeStatus, reset } = useWriteContract();
  const { status: receiptStatus, error: receiptError } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: Boolean(txHash) },
  });

  const withdraw = useCallback(
    ({ poolManagerAddress, assetAddress, amount }: { poolManagerAddress: Address; assetAddress: Address; amount: bigint }) => {
      writeContract({
        address: poolManagerAddress,
        abi: bitVPoolManagerAbi,
        functionName: "withdraw",
        args: [assetAddress, amount],
      });
    },
    [writeContract],
  );

  return {
    state: derivePoolActionState(writeStatus, txHash ? receiptStatus : undefined),
    txHash,
    errorMessage: writeError?.message ?? receiptError?.message,
    withdraw,
    reset,
  };
}
