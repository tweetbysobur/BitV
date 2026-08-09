"use client";

import { useEffect, useState } from "react";
import { parseUnits } from "viem";
import type { Address } from "viem";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { useContractAddress } from "@/hooks/useContractAddress";
import { useSupplyAllowance } from "@/hooks/usePoolSupplyWithdraw";
import {
  useApproveLendingManager,
  useDepositCollateral,
  useWithdrawCollateral,
  useBorrow,
  useRepay,
} from "@/hooks/useLendingActions";
import { poolAssets } from "@/services/contracts/addresses";
import { formatTokenAmount } from "@/lib/format";

const STATUS_LABEL: Record<string, string> = {
  idle: "",
  pending: "Confirm in wallet…",
  confirming: "Confirming on-chain…",
  success: "Confirmed",
  error: "Failed",
};

/** Collateral + borrow/repay actions against BitVLendingManager, for
 * the one deployed pool/collateral asset (BVTEST). Distinct from
 * SupplyWithdrawPanel: that panel supplies pool *liquidity* to
 * BitVPoolManager (what borrowers draw from); this panel posts
 * collateral and borrows/repays against BitVLendingManager — two
 * separate contracts, two separate allowances, by design in the
 * deployed contracts (see BitVLendingManager.depositCollateral, which
 * calls transferFrom directly rather than routing through the pool). */
export function CollateralBorrowPanel({
  onPositionChanged,
  actionsDisabled,
}: {
  onPositionChanged?: () => void;
  actionsDisabled?: boolean;
}) {
  const lendingManagerAddress = useContractAddress("LendingManager");
  const asset = poolAssets[0] as { address: Address; chainId: number } | undefined;
  const decimals = 18;

  const { balance, allowance, refetch: refetchAllowance } = useSupplyAllowance(asset?.address, lendingManagerAddress);
  const { state: approveState, txHash: approveHash, errorMessage: approveError, approve, reset: resetApprove } = useApproveLendingManager();
  const { state: depositState, txHash: depositHash, errorMessage: depositError, send: depositCollateral, reset: resetDeposit } = useDepositCollateral();
  const { state: withdrawState, txHash: withdrawHash, errorMessage: withdrawError, send: withdrawCollateral, reset: resetWithdraw } = useWithdrawCollateral();
  const { state: borrowState, txHash: borrowHash, errorMessage: borrowError, send: borrow, reset: resetBorrow } = useBorrow();
  const { state: repayState, txHash: repayHash, errorMessage: repayError, send: repay, reset: resetRepay } = useRepay();

  const [collateralAmount, setCollateralAmount] = useState("");
  const [uncollateralAmount, setUncollateralAmount] = useState("");
  const [borrowAmount, setBorrowAmount] = useState("");
  const [repayAmount, setRepayAmount] = useState("");

  if (!asset || !lendingManagerAddress) {
    return null;
  }

  const parsedCollateral = collateralAmount ? safeParse(collateralAmount, decimals) : undefined;
  const parsedUncollateral = uncollateralAmount ? safeParse(uncollateralAmount, decimals) : undefined;
  const parsedBorrow = borrowAmount ? safeParse(borrowAmount, decimals) : undefined;
  const parsedRepay = repayAmount ? safeParse(repayAmount, decimals) : undefined;

  const needsApproval = parsedCollateral !== undefined && (allowance === undefined || allowance < parsedCollateral);
  const collateralExceedsBalance = parsedCollateral !== undefined && balance !== undefined && parsedCollateral > balance;
  const collateralBusy = actionsDisabled || approveState === "pending" || approveState === "confirming" || depositState === "pending" || depositState === "confirming";
  const uncollateralBusy = actionsDisabled || withdrawState === "pending" || withdrawState === "confirming";
  const borrowBusy = actionsDisabled || borrowState === "pending" || borrowState === "confirming";
  const repayBusy = actionsDisabled || repayState === "pending" || repayState === "confirming";
  const cviHelperText = actionsDisabled
    ? "CVI required — complete Cleanverse verification before using this market."
    : undefined;

  function afterConfirmed() {
    refetchAllowance();
    onPositionChanged?.();
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>2. Post collateral &amp; borrow — BVTEST</CardTitle>
        <CardDescription>
          Post BVTEST as collateral, then borrow against it. Testnet-only asset, no real value. Wallet balance:{" "}
          {formatTokenAmount(balance, decimals, { maxFractionDigits: 4 })} BVTEST.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-6">
        <ActionRow
          label="Post collateral"
          inputId="collateral-amount"
          value={collateralAmount}
          onChange={(v) => {
            setCollateralAmount(v);
            resetApprove();
            resetDeposit();
          }}
          buttonLabel={needsApproval ? "Approve" : "Deposit"}
          buttonVariant="primary"
          isLoading={needsApproval ? approveState === "pending" || approveState === "confirming" : depositState === "pending" || depositState === "confirming"}
          disabled={!parsedCollateral || collateralExceedsBalance || collateralBusy}
          helperText={collateralExceedsBalance ? "Amount exceeds your wallet balance." : cviHelperText}
          onSubmit={() => {
            if (!parsedCollateral) return;
            if (needsApproval) {
              approve({ assetAddress: asset.address, spender: lendingManagerAddress, amount: parsedCollateral });
            } else {
              depositCollateral({ lendingManagerAddress, assetAddress: asset.address, amount: parsedCollateral });
            }
          }}
          state={approveState !== "idle" ? approveState : depositState}
          txHash={approveHash ?? depositHash}
          errorMessage={approveError ?? depositError}
          onConfirmed={() => {
            afterConfirmed();
            setCollateralAmount("");
          }}
        />

        <ActionRow
          label="Withdraw collateral"
          inputId="uncollateral-amount"
          value={uncollateralAmount}
          onChange={(v) => {
            setUncollateralAmount(v);
            resetWithdraw();
          }}
          buttonLabel="Withdraw"
          buttonVariant="secondary"
          isLoading={uncollateralBusy}
          disabled={!parsedUncollateral || uncollateralBusy}
          helperText={cviHelperText}
          onSubmit={() => {
            if (!parsedUncollateral) return;
            withdrawCollateral({ lendingManagerAddress, assetAddress: asset.address, amount: parsedUncollateral });
          }}
          state={withdrawState}
          txHash={withdrawHash}
          errorMessage={withdrawError}
          onConfirmed={() => {
            afterConfirmed();
            setUncollateralAmount("");
          }}
        />

        <ActionRow
          label="Borrow"
          inputId="borrow-amount"
          value={borrowAmount}
          onChange={(v) => {
            setBorrowAmount(v);
            resetBorrow();
          }}
          buttonLabel="Borrow"
          buttonVariant="primary"
          isLoading={borrowBusy}
          disabled={!parsedBorrow || borrowBusy}
          helperText={cviHelperText}
          onSubmit={() => {
            if (!parsedBorrow) return;
            borrow({ lendingManagerAddress, assetAddress: asset.address, amount: parsedBorrow });
          }}
          state={borrowState}
          txHash={borrowHash}
          errorMessage={borrowError}
          onConfirmed={() => {
            afterConfirmed();
            setBorrowAmount("");
          }}
        />

        <ActionRow
          label="Repay"
          inputId="repay-amount"
          value={repayAmount}
          onChange={(v) => {
            setRepayAmount(v);
            resetRepay();
          }}
          buttonLabel="Repay"
          buttonVariant="secondary"
          isLoading={repayBusy}
          disabled={!parsedRepay || repayBusy}
          helperText={cviHelperText}
          onSubmit={() => {
            if (!parsedRepay) return;
            repay({ lendingManagerAddress, assetAddress: asset.address, amount: parsedRepay });
          }}
          state={repayState}
          txHash={repayHash}
          errorMessage={repayError}
          onConfirmed={() => {
            afterConfirmed();
            setRepayAmount("");
          }}
        />
      </CardContent>
    </Card>
  );
}

function ActionRow({
  label,
  inputId,
  value,
  onChange,
  buttonLabel,
  buttonVariant,
  isLoading,
  disabled,
  onSubmit,
  state,
  txHash,
  errorMessage,
  onConfirmed,
  helperText,
}: {
  label: string;
  inputId: string;
  value: string;
  onChange: (v: string) => void;
  buttonLabel: string;
  buttonVariant: "primary" | "secondary";
  isLoading: boolean;
  disabled: boolean;
  onSubmit: () => void;
  state: string;
  txHash: `0x${string}` | undefined;
  errorMessage: string | undefined;
  onConfirmed: () => void;
  helperText?: string;
}) {
  const [notifiedFor, setNotifiedFor] = useState<string | undefined>(undefined);
  useEffect(() => {
    if (state === "success" && txHash && notifiedFor !== txHash) {
      setNotifiedFor(txHash);
      onConfirmed();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state, txHash]);

  return (
    <div className="flex flex-col gap-2">
      <label htmlFor={inputId} className="text-sm font-medium">
        {label}
      </label>
      <div className="flex flex-col gap-2 sm:flex-row">
        <input
          id={inputId}
          type="text"
          inputMode="decimal"
          placeholder="0.0"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="h-10 flex-1 rounded-md border border-border bg-background px-3 text-sm font-numeric outline-none focus-visible:ring-2 focus-visible:ring-accent"
        />
        <Button type="button" variant={buttonVariant} isLoading={isLoading} disabled={disabled} onClick={onSubmit}>
          {buttonLabel}
        </Button>
      </div>
      {helperText ? <p className="text-xs text-destructive">{helperText}</p> : null}
      {state !== "idle" ? (
        <p className="text-xs text-muted-foreground" role="status" aria-live="polite">
          {STATUS_LABEL[state] ?? state}
          {txHash ? ` — tx ${txHash.slice(0, 10)}…` : ""}
          {state === "error" && errorMessage ? ` (${errorMessage.split("\n")[0]})` : ""}
        </p>
      ) : null}
    </div>
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
