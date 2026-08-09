"use client";

import { useEffect, useState } from "react";
import { parseUnits } from "viem";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useAccount } from "wagmi";
import {
  useVaultAllowance,
  useApproveVaultAsset,
  useVaultDeposit,
  useVaultWithdraw,
} from "@/hooks/useVaultActions";
import { useCVIStatus } from "@/hooks/useCVIStatus";
import { formatTokenAmount } from "@/lib/format";
import type { VaultPositionRow } from "@/hooks/useVaultPositions";

const STATUS_LABEL: Record<string, string> = {
  idle: "",
  pending: "Confirm in wallet…",
  confirming: "Confirming on-chain…",
  success: "Confirmed",
  error: "Failed",
};

/** Real deposit/withdraw actions against a deployed BitVYieldVault
 * (ERC-4626, self-service only — receiver/owner must equal the
 * connected wallet, enforced on-chain). Deliberately does not expose
 * mint/redeem (share-denominated variants) — assets-denominated
 * deposit/withdraw is the intuitive path for a demo. */
export function VaultActionsPanel({ vault, onChanged }: { vault: VaultPositionRow; onChanged?: () => void }) {
  const { address: account } = useAccount();
  const decimals = 18;

  const cvi = useCVIStatus(vault.vaultAddress);
  const cviBlocksActions = !cvi.isLoading && cvi.status === "not-verified";

  const { balance, allowance, refetch } = useVaultAllowance(vault.underlyingAsset, vault.vaultAddress);
  const { state: approveState, txHash: approveHash, errorMessage: approveError, approve, reset: resetApprove } = useApproveVaultAsset();
  const { state: depositState, txHash: depositHash, errorMessage: depositError, deposit, reset: resetDeposit } = useVaultDeposit();
  const { state: withdrawState, txHash: withdrawHash, errorMessage: withdrawError, withdraw, reset: resetWithdraw } = useVaultWithdraw();

  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");

  useEffect(() => {
    if (depositState === "success" || withdrawState === "success") {
      refetch();
      onChanged?.();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [depositState, withdrawState]);

  if (!vault.underlyingAsset || !account) return null;

  const parsedDeposit = depositAmount ? safeParse(depositAmount, decimals) : undefined;
  const parsedWithdraw = withdrawAmount ? safeParse(withdrawAmount, decimals) : undefined;
  const needsApproval = parsedDeposit !== undefined && (allowance === undefined || allowance < parsedDeposit);
  const depositExceedsBalance = parsedDeposit !== undefined && balance !== undefined && parsedDeposit > balance;
  const withdrawExceedsMax =
    parsedWithdraw !== undefined && vault.maxWithdrawAssets !== undefined && parsedWithdraw > vault.maxWithdrawAssets;

  const depositBusy =
    cviBlocksActions || approveState === "pending" || approveState === "confirming" || depositState === "pending" || depositState === "confirming";
  const withdrawBusy = cviBlocksActions || withdrawState === "pending" || withdrawState === "confirming";

  if (vault.depositsPaused && vault.withdrawalsPaused) {
    return (
      <Card>
        <CardContent className="pt-6">
          <Badge tone="warning">Deposits and withdrawals are paused on this vault</Badge>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Vault Actions</CardTitle>
        <CardDescription>
          Wallet balance: {formatTokenAmount(balance, decimals, { maxFractionDigits: 4 })} underlying.
          {vault.isTestStrategy ? " Test strategy — no real yield." : ""}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-6">
        <div className="flex flex-col gap-2">
          <label htmlFor={`vault-deposit-${vault.vaultAddress}`} className="text-sm font-medium">
            Deposit
          </label>
          <div className="flex flex-col gap-2 sm:flex-row">
            <input
              id={`vault-deposit-${vault.vaultAddress}`}
              type="text"
              inputMode="decimal"
              placeholder="0.0"
              value={depositAmount}
              disabled={vault.depositsPaused === true}
              onChange={(e) => {
                setDepositAmount(e.target.value);
                resetApprove();
                resetDeposit();
              }}
              className="h-10 flex-1 rounded-md border border-border bg-background px-3 text-sm font-numeric outline-none focus-visible:ring-2 focus-visible:ring-accent disabled:opacity-40"
            />
            {needsApproval ? (
              <Button
                type="button"
                variant="primary"
                isLoading={approveState === "pending" || approveState === "confirming"}
                disabled={!parsedDeposit || depositExceedsBalance || depositBusy || vault.depositsPaused === true}
                onClick={() => {
                  if (!parsedDeposit || !vault.underlyingAsset) return;
                  approve({ assetAddress: vault.underlyingAsset, spender: vault.vaultAddress, amount: parsedDeposit });
                }}
              >
                Approve
              </Button>
            ) : (
              <Button
                type="button"
                variant="primary"
                isLoading={depositState === "pending" || depositState === "confirming"}
                disabled={!parsedDeposit || depositExceedsBalance || depositBusy || vault.depositsPaused === true}
                onClick={() => {
                  if (!parsedDeposit || !account) return;
                  deposit({ vaultAddress: vault.vaultAddress, assets: parsedDeposit, receiver: account });
                }}
              >
                Deposit
              </Button>
            )}
          </div>
          {vault.depositsPaused ? <p className="text-xs text-destructive">Deposits are currently paused on this vault.</p> : null}
          {depositExceedsBalance ? <p className="text-xs text-destructive">Amount exceeds your wallet balance.</p> : null}
          {cviBlocksActions ? (
            <p className="text-xs text-destructive">CVI required — complete Cleanverse verification before using this vault.</p>
          ) : null}
          <ActionStatus
            state={approveState !== "idle" ? approveState : depositState}
            txHash={approveHash ?? depositHash}
            errorMessage={approveError ?? depositError}
          />
        </div>

        <div className="flex flex-col gap-2">
          <label htmlFor={`vault-withdraw-${vault.vaultAddress}`} className="text-sm font-medium">
            Withdraw
          </label>
          <div className="flex flex-col gap-2 sm:flex-row">
            <input
              id={`vault-withdraw-${vault.vaultAddress}`}
              type="text"
              inputMode="decimal"
              placeholder="0.0"
              value={withdrawAmount}
              disabled={vault.withdrawalsPaused === true}
              onChange={(e) => {
                setWithdrawAmount(e.target.value);
                resetWithdraw();
              }}
              className="h-10 flex-1 rounded-md border border-border bg-background px-3 text-sm font-numeric outline-none focus-visible:ring-2 focus-visible:ring-accent disabled:opacity-40"
            />
            <Button
              type="button"
              variant="secondary"
              isLoading={withdrawBusy}
              disabled={!parsedWithdraw || withdrawExceedsMax || withdrawBusy || vault.withdrawalsPaused === true}
              onClick={() => {
                if (!parsedWithdraw || !account) return;
                withdraw({ vaultAddress: vault.vaultAddress, assets: parsedWithdraw, receiver: account, owner: account });
              }}
            >
              Withdraw
            </Button>
          </div>
          {vault.withdrawalsPaused ? <p className="text-xs text-destructive">Withdrawals are currently paused on this vault.</p> : null}
          {withdrawExceedsMax ? (
            <p className="text-xs text-destructive">
              Amount exceeds what the vault can currently return
              {vault.maxWithdrawAssets !== undefined
                ? ` (max ${formatTokenAmount(vault.maxWithdrawAssets, decimals, { maxFractionDigits: 4 })}).`
                : "."}
            </p>
          ) : null}
          {cviBlocksActions ? (
            <p className="text-xs text-destructive">CVI required — complete Cleanverse verification before using this vault.</p>
          ) : null}
          <ActionStatus state={withdrawState} txHash={withdrawHash} errorMessage={withdrawError} />
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
