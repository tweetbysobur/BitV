"use client";

import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DataStateView } from "./DataStateView";
import { useTreasuryReserve, useClaimPoolReserve, useContractAddress } from "@/hooks";
import { formatTokenAmount } from "@/lib/format";
import type { Address } from "viem";

/** Treasury reserve-factor claim panel (Prompt 14's contract logic,
 * wired into the UI in Prompt 16). This is a protocol-administration
 * action, not a normal user action: it only renders its claim controls
 * when the connected wallet holds PROTOCOL_ADMIN_ROLE (per
 * useTreasuryReserve's `isAdmin`), and it always shows the underlying
 * on-chain enforcement's own success/failure — a submitted transaction
 * is never presented as "success" before its receipt confirms. */
export function TreasuryReservePanel() {
  const state = useTreasuryReserve();
  const treasuryAddress = useContractAddress("Treasury");
  const poolManagerAddress = useContractAddress("PoolManager");
  const { state: claimState, txHash, errorMessage, claim, reset } = useClaimPoolReserve();
  const [claimingAsset, setClaimingAsset] = useState<Address | undefined>(undefined);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Treasury Administration — Reserve Claim</CardTitle>
        <CardDescription>
          Protocol-admin-only. Claims BitVTreasury&apos;s accrued reserve-factor interest out of a
          pool, per asset. Not a user action — see docs/economic-engine-review.md.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <DataStateView state={state} loadingLabel="Reading Treasury reserve balances">
          {({ rows, isAdmin }) => (
            <div className="flex flex-col gap-3">
              {!isAdmin ? (
                <p className="text-sm text-muted-foreground">
                  Reserve balances (read-only — connect the protocol admin wallet to claim):
                </p>
              ) : null}

              {rows.map((row) => {
                const isThisAssetClaiming =
                  claimingAsset === row.assetAddress && (claimState === "pending" || claimState === "confirming");
                return (
                  <div
                    key={row.assetAddress}
                    className="flex flex-col gap-2 rounded-md border border-border p-3 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <div className="flex items-center gap-2 text-sm">
                      <span className="font-medium">{row.symbol ?? row.assetAddress}</span>
                      <span className="text-muted-foreground">
                        Accrued reserve: {formatTokenAmount(row.reserveBalance, 18, { maxFractionDigits: 6 })}
                      </span>
                    </div>

                    {isAdmin ? (
                      <Button
                        variant="primary"
                        className="h-8 px-3 text-xs"
                        isLoading={isThisAssetClaiming}
                        disabled={row.reserveBalance === 0n || !treasuryAddress || !poolManagerAddress}
                        onClick={() => {
                          if (!treasuryAddress || !poolManagerAddress) return;
                          setClaimingAsset(row.assetAddress);
                          reset();
                          claim({
                            treasuryAddress,
                            poolManagerAddress,
                            asset: row.assetAddress,
                            amount: BigInt(2) ** BigInt(256) - BigInt(1), // type(uint256).max — claim full accrued balance
                          });
                        }}
                      >
                        {isThisAssetClaiming ? "Claiming…" : "Claim reserve"}
                      </Button>
                    ) : null}
                  </div>
                );
              })}

              {claimingAsset && claimState === "success" ? (
                <div role="status" className="rounded-md border border-success/30 bg-success/5 p-3 text-sm">
                  <p className="font-medium text-success">Claim confirmed</p>
                  {txHash ? <p className="mt-1 break-all text-xs text-muted-foreground">Tx: {txHash}</p> : null}
                </div>
              ) : null}

              {claimingAsset && claimState === "error" ? (
                <div role="alert" className="rounded-md border border-destructive/30 bg-destructive/5 p-3 text-sm">
                  <p className="font-medium text-destructive">Claim failed</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {errorMessage ?? "The transaction was rejected or reverted."}
                  </p>
                </div>
              ) : null}

              {!isAdmin ? <Badge tone="neutral">Read-only — not a protocol admin</Badge> : null}
            </div>
          )}
        </DataStateView>
      </CardContent>
    </Card>
  );
}
