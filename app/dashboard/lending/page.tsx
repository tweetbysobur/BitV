"use client";

import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { DataStateView } from "@/components/dashboard/DataStateView";
import { HealthFactorCard } from "@/components/dashboard/HealthFactorCard";
import { BorrowingCapacityCard } from "@/components/dashboard/BorrowingCapacityCard";
import { CollateralTable } from "@/components/dashboard/CollateralTable";
import { DebtTable } from "@/components/dashboard/DebtTable";
import { SupplyWithdrawPanel } from "@/components/dashboard/SupplyWithdrawPanel";
import { useWalletStatus } from "@/hooks/useWalletStatus";
import { useLendingPosition } from "@/hooks/useLendingPosition";
import { formatBps } from "@/lib/format";

export default function LendingPage() {
  const { state: walletState } = useWalletStatus();
  const position = useLendingPosition();

  if (walletState !== "connected") {
    return <p className="text-muted-foreground">Connect your wallet to view your lending position.</p>;
  }

  return (
    <div className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">Lending</h1>

      <SupplyWithdrawPanel />

      <DataStateView state={position} loadingLabel="Reading lending position">
        {(data) => (
          <>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <HealthFactorCard healthFactorRay={data.accountData.healthFactorRay} />
              <BorrowingCapacityCard
                effectiveAvailableBorrowValue={data.effectiveAvailableBorrowValue}
                baseAvailableBorrowValue={data.accountData.availableBorrowValue}
              />
              <Card>
                <CardHeader>
                  <CardTitle>Liquidation Threshold</CardTitle>
                  <CardDescription>Collateral-value-weighted average across your positions</CardDescription>
                </CardHeader>
                <CardContent>
                  <p className="font-heading text-xl font-semibold tabular-nums">
                    {formatBps(Number(data.accountData.currentLiquidationThresholdBps))}
                  </p>
                </CardContent>
              </Card>
            </div>

            <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
              <Card>
                <CardHeader>
                  <CardTitle>Collateral by Asset</CardTitle>
                </CardHeader>
                <CardContent>
                  <CollateralTable
                    rows={data.collateralByAsset.map((a) => ({
                      assetAddress: a.assetAddress,
                      symbol: a.symbol,
                      rawAmount: a.amount,
                      decimals: a.decimals,
                    }))}
                  />
                </CardContent>
              </Card>
              <Card>
                <CardHeader>
                  <CardTitle>Debt by Asset</CardTitle>
                </CardHeader>
                <CardContent>
                  <DebtTable
                    rows={data.debtByAsset.map((a) => ({
                      assetAddress: a.assetAddress,
                      symbol: a.symbol,
                      rawAmount: a.amount,
                      decimals: a.decimals,
                    }))}
                  />
                </CardContent>
              </Card>
            </div>
          </>
        )}
      </DataStateView>
    </div>
  );
}
