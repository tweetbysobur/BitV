"use client";

import { useCallback } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { erc20Abi, bitVYieldVaultAbi } from "@/services/contracts/abis";
import { derivePoolActionState, type PoolActionState } from "@/lib/poolAction";
import type { Address } from "viem";

export interface VaultWriteResult {
  state: PoolActionState;
  txHash: `0x${string}` | undefined;
  errorMessage: string | undefined;
  reset: () => void;
}

/** Read the connected wallet's underlying-asset balance and its
 * allowance for a specific vault, so the deposit panel can decide
 * whether an approve step is still needed. */
export function useVaultAllowance(underlyingAsset: Address | undefined, vaultAddress: Address | undefined) {
  const { address: account } = useAccount();

  const balance = useReadContract({
    address: underlyingAsset,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: account ? [account] : undefined,
    query: { enabled: Boolean(underlyingAsset && account) },
  });

  const allowance = useReadContract({
    address: underlyingAsset,
    abi: erc20Abi,
    functionName: "allowance",
    args: account && vaultAddress ? [account, vaultAddress] : undefined,
    query: { enabled: Boolean(underlyingAsset && account && vaultAddress) },
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

export function useApproveVaultAsset(): VaultWriteResult & {
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

/** Write path for BitVYieldVault.deposit(assets, receiver) — receiver
 * is always the connected wallet (the deployed contract reverts
 * OnlySelfService otherwise). */
export function useVaultDeposit(): VaultWriteResult & {
  deposit: (args: { vaultAddress: Address; assets: bigint; receiver: Address }) => void;
} {
  const { writeContract, data: txHash, error: writeError, status: writeStatus, reset } = useWriteContract();
  const { status: receiptStatus, error: receiptError } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: Boolean(txHash) },
  });

  const deposit = useCallback(
    ({ vaultAddress, assets, receiver }: { vaultAddress: Address; assets: bigint; receiver: Address }) => {
      writeContract({ address: vaultAddress, abi: bitVYieldVaultAbi, functionName: "deposit", args: [assets, receiver] });
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

/** Write path for BitVYieldVault.withdraw(assets, receiver, owner) —
 * receiver and owner are always the connected wallet. */
export function useVaultWithdraw(): VaultWriteResult & {
  withdraw: (args: { vaultAddress: Address; assets: bigint; receiver: Address; owner: Address }) => void;
} {
  const { writeContract, data: txHash, error: writeError, status: writeStatus, reset } = useWriteContract();
  const { status: receiptStatus, error: receiptError } = useWaitForTransactionReceipt({
    hash: txHash,
    query: { enabled: Boolean(txHash) },
  });

  const withdraw = useCallback(
    ({ vaultAddress, assets, receiver, owner }: { vaultAddress: Address; assets: bigint; receiver: Address; owner: Address }) => {
      writeContract({
        address: vaultAddress,
        abi: bitVYieldVaultAbi,
        functionName: "withdraw",
        args: [assets, receiver, owner],
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
