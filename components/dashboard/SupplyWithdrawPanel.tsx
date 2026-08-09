"use client";

import { useState } from "react";
import { parseUnits } from "viem";
import type { Address } from "viem";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import {
  useContractAddress,
  useSupplyAllowance,
  useApproveAsset,
  useDepositToPool,
  useWithdrawFromPool,
} from "@/hooks";
import { poolAssets } from "@/services/contracts/addresses";
import { formatTokenAmount } from "@/lib/format";

const STATUS_LABEL: Record<string, string> = {
  idle: "",
  pending: "Confirm in wallet…",
  confirming: "Confirming on-chain…",
  success: "Confirmed",
  error: "Failed",
};

/** Real supply/withdraw actions against BitVPoolManager, for the one
 * pool asset currently deployed (poolAssets[0], BVTEST — testnet-only,
 * no real value). Approve-then-deposit is a standard two-step ERC-20
 * flow; withdraw is a single call. Every step waits for its own
 * transaction receipt before advancing — never shows "success" from a
 * submitted-but-unconfirmed transaction. */
export function SupplyWithdrawPanel({ actionsDisabled }: { actionsDisabled?: boolean } = {}) {
  const poolManagerAddress = useContractAddress("PoolManager");
  const asset = poolAssets[0] as { address: Address; chainId: number } | undefined;
  const decimals = 18;

  const { balance, allowance, refetch } = useSupplyAllowance(asset?.address, poolManagerAddress);
  const { state: approveState, txHash: approveHash, errorMessage: approveError, approve, reset: resetApprove } = useApproveAsset();
  const { state: depositState, txHash: depositHash, errorMessage: depositError, deposit, reset: resetDeposit } = useDepositToPool();
  const { state: withdrawState, txHash: withdrawHash, errorMessage: withdrawError, withdraw, reset: resetWithdraw } = useWithdrawFromPool();

  const [supplyAmount, setSupplyAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");

  if (!asset || !poolManagerAddress) {
    return null;
  }

  const parsedSupply = supplyAmount ? safeParse(supplyAmount, decimals) : undefined;
  const parsedWithdraw = withdrawAmount ? safeParse(withdrawAmount, decimals) : undefined;
  const needsApproval = parsedSupply !== undefined && (allowance === undefined || allowance < parsedSupply);
  const supplyExceedsBalance = parsedSupply !== undefined && balance !== undefined && parsedSupply > balance;

  const busy = actionsDisabled || approveState === "pending" || approveState === "confirming" || depositState === "pending" || depositState === "confirming";
  const withdrawBusy = actionsDisabled || withdrawState === "pending" || withdrawState === "confirming";

  return (
    <Card>
      <CardHeader>
        <CardTitle>Supply / Withdraw — BVTEST</CardTitle>
        <CardDescription>
          Testnet-only asset, no real value. Wallet balance: {formatTokenAmount(balance, decimals, { maxFractionDigits: 4 })} BVTEST.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-6">
        <div className="flex flex-col gap-2">
          <label htmlFor="supply-amount" className="text-sm font-medium">
            Supply
          </label>
          <div className="flex flex-col gap-2 sm:flex-row">
            <input
              id="supply-amount"
              type="text"
              inputMode="decimal"
              placeholder="0.0"
              value={supplyAmount}
              onChange={(e) => {
                setSupplyAmount(e.target.value);
                resetApprove();
                resetDeposit();
              }}
              className="h-10 flex-1 rounded-md border border-border bg-background px-3 text-sm font-numeric outline-none focus-visible:ring-2 focus-visible:ring-accent"
            />
            {needsApproval ? (
              <Button
                type="button"
                variant="primary"
                isLoading={approveState === "pending" || approveState === "confirming"}
                disabled={!parsedSupply || supplyExceedsBalance || busy}
                onClick={() => {
                  if (!parsedSupply) return;
                  approve({ assetAddress: asset.address, spender: poolManagerAddress, amount: parsedSupply });
                }}
              >
                Approve
              </Button>
            ) : (
              <Button
                type="button"
                variant="primary"
                isLoading={depositState === "pending" || depositState === "confirming"}
                disabled={!parsedSupply || supplyExceedsBalance || busy}
                onClick={() => {
                  if (!parsedSupply) return;
                  deposit({ poolManagerAddress, assetAddress: asset.address, amount: parsedSupply });
                }}
              >
                Supply
              </Button>
            )}
          </div>
          {supplyExceedsBalance ? (
            <p className="text-xs text-destructive">Amount exceeds your wallet balance.</p>
          ) : null}
          {actionsDisabled ? (
            <p className="text-xs text-destructive">CVI required — complete Cleanverse verification before using this market.</p>
          ) : null}
          <ActionStatus
            state={approveState !== "idle" ? approveState : depositState}
            txHash={approveHash ?? depositHash}
            errorMessage={approveError ?? depositError}
          />
          {approveState === "success" || depositState === "success" ? (
            <button
              type="button"
              className="w-fit text-xs text-muted-foreground underline"
              onClick={() => {
                refetch();
                setSupplyAmount("");
                resetApprove();
                resetDeposit();
              }}
            >
              Refresh balances
            </button>
          ) : null}
        </div>

        <div className="flex flex-col gap-2">
          <label htmlFor="withdraw-amount" className="text-sm font-medium">
            Withdraw
          </label>
          <div className="flex flex-col gap-2 sm:flex-row">
            <input
              id="withdraw-amount"
              type="text"
              inputMode="decimal"
              placeholder="0.0"
              value={withdrawAmount}
              onChange={(e) => {
                setWithdrawAmount(e.target.value);
                resetWithdraw();
              }}
              className="h-10 flex-1 rounded-md border border-border bg-background px-3 text-sm font-numeric outline-none focus-visible:ring-2 focus-visible:ring-accent"
            />
            <Button
              type="button"
              variant="secondary"
              isLoading={withdrawBusy}
              disabled={!parsedWithdraw || withdrawBusy}
              onClick={() => {
                if (!parsedWithdraw) return;
                withdraw({ poolManagerAddress, assetAddress: asset.address, amount: parsedWithdraw });
              }}
            >
              Withdraw
            </Button>
          </div>
          <ActionStatus state={withdrawState} txHash={withdrawHash} errorMessage={withdrawError} />
          {withdrawState === "success" ? (
            <button
              type="button"
              className="w-fit text-xs text-muted-foreground underline"
              onClick={() => {
                refetch();
                setWithdrawAmount("");
                resetWithdraw();
              }}
            >
              Refresh balances
            </button>
          ) : null}
        </div>
      </CardContent>
    </Card>
  );
}

function ActionStatus({
  state,
  txHash,
  errorMessage,
}: {
  state: string;
  txHash: `0x${string}` | undefined;
  errorMessage: string | undefined;
}) {
  if (state === "idle") return null;
  return (
    <p className="text-xs text-muted-foreground" role="status" aria-live="polite">
      {STATUS_LABEL[state] ?? state}
      {txHash ? ` — tx ${txHash.slice(0, 10)}…` : ""}
      {state === "error" && errorMessage ? ` (${errorMessage.split("\n")[0]})` : ""}
    </p>
  );
}

function safeParse(value: string, decimals: number): bigint | undefined {
  try {
    if (!/^\d*\.?\d*$/.test(value) || value === "" || value === ".") return undefined;
    const parsed = parseUnits(value, decimals);
    return parsed > 0n ? parsed : undefined;
  } catch {
    return undefined;
  }
}
