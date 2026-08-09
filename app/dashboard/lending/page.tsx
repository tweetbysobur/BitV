"use client";

import type { ReactNode } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { DataStateView } from "@/components/dashboard/DataStateView";
import { HealthFactorCard } from "@/components/dashboard/HealthFactorCard";
import { BorrowingCapacityCard } from "@/components/dashboard/BorrowingCapacityCard";
import { CollateralTable } from "@/components/dashboard/CollateralTable";
import { DebtTable } from "@/components/dashboard/DebtTable";
import { SupplyWithdrawPanel } from "@/components/dashboard/SupplyWithdrawPanel";
import { CollateralBorrowPanel } from "@/components/dashboard/CollateralBorrowPanel";
import { CVIStatus } from "@/components/dashboard/CVIStatus";
import { BitScoreCard } from "@/components/dashboard/BitScoreCard";
import { useWalletStatus } from "@/hooks/useWalletStatus";
import { useLendingPosition } from "@/hooks/useLendingPosition";
import { useContractAddress } from "@/hooks/useContractAddress";
import { useCVIStatus } from "@/hooks/useCVIStatus";
import { formatBps } from "@/lib/format";

export default function LendingPage() {
  const { state: walletState, chainId, expectedChainId } = useWalletStatus();
  const position = useLendingPosition();
  const lendingManagerAddress = useContractAddress("LendingManager");
  const cvi = useCVIStatus(lendingManagerAddress);
  const queryClient = useQueryClient();

  if (walletState === "disconnected") {
    return <p className="text-muted-foreground">Connect your wallet to view your lending position.</p>;
  }
  if (walletState === "connecting") {
    return <p className="text-muted-foreground">Connecting wallet…</p>;
  }
  if (walletState === "wrong-network" || walletState === "unsupported-network") {
    return (
      <p className="text-muted-foreground">
        BitV runs on Monad Testnet (chain {expectedChainId}). Your wallet is connected to
        {chainId !== undefined ? ` chain ${chainId}` : " an unrecognized network"} — switch networks in your
        wallet to use lending.
      </p>
    );
  }

  const cviBlocksActions = !cvi.isLoading && cvi.status === "not-verified";

  function refetchPosition() {
    void queryClient.invalidateQueries();
  }

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="font-heading text-2xl font-semibold">Lending</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Your risk, your position, and what you can do next — in that order.
        </p>
      </div>

      <section className="flex flex-col gap-4">
        <SectionLabel>Eligibility</SectionLabel>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <BitScoreCard />
          <Card>
            <CardHeader>
              <CardTitle>Cleanverse CVI</CardTitle>
              <CardDescription>Eligibility to use this lending market</CardDescription>
            </CardHeader>
            <CardContent>
              <CVIStatus poolAddress={lendingManagerAddress} />
            </CardContent>
          </Card>
        </div>
      </section>

      <section className="flex flex-col gap-4">
        <SectionLabel>Your position</SectionLabel>
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
      </section>

      <section className="flex flex-col gap-4">
        <SectionLabel>What you can do next</SectionLabel>
        <SupplyWithdrawPanel actionsDisabled={cviBlocksActions} />
        <CollateralBorrowPanel onPositionChanged={refetchPosition} actionsDisabled={cviBlocksActions} />
      </section>
    </div>
  );
}

function SectionLabel({ children }: { children: ReactNode }) {
  return <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{children}</p>;
}
