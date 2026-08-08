"use client";

import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { DataStateView } from "@/components/dashboard/DataStateView";
import { BitScoreCard } from "@/components/dashboard/BitScoreCard";
import { HealthFactorCard } from "@/components/dashboard/HealthFactorCard";
import { CVIStatus } from "@/components/dashboard/CVIStatus";
import { useWalletStatus } from "@/hooks/useWalletStatus";
import { useContractAddress } from "@/hooks/useContractAddress";
import { useLendingPosition } from "@/hooks/useLendingPosition";
import { formatBps, formatTokenAmount } from "@/lib/format";
import { getHealthFactorStatus } from "@/lib/health-factor";

/** No separate numerical "risk score" is computed here — BitScore
 * (0-100) is the only risk score BitV exposes, per the task's explicit
 * instruction. This page presents the underlying signals (health
 * factor, collateralization, utilization) alongside BitScore, not a
 * fabricated combination of them. */
export default function RiskPage() {
  const { state: walletState } = useWalletStatus();
  const lendingManagerAddress = useContractAddress("LendingManager");
  const position = useLendingPosition();

  if (walletState !== "connected") {
    return <p className="text-muted-foreground">Connect your wallet to view your risk dashboard.</p>;
  }

  return (
    <div className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">Risk</h1>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <BitScoreCard />
        <Card>
          <CardHeader>
            <CardTitle>CVI Eligibility</CardTitle>
          </CardHeader>
          <CardContent>
            <CVIStatus poolAddress={lendingManagerAddress} />
          </CardContent>
        </Card>
        <DataStateView state={position} loadingLabel="Reading">
          {(data) => <HealthFactorCard healthFactorRay={data.accountData.healthFactorRay} />}
        </DataStateView>
      </div>

      <DataStateView state={position} loadingLabel="Reading risk signals">
        {(data) => {
          const hfStatus = getHealthFactorStatus(data.accountData.healthFactorRay);
          return (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <Card>
                <CardHeader>
                  <CardTitle>Collateralization</CardTitle>
                  <CardDescription>Total collateral value vs. total debt value</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-1 text-sm">
                  <span>Collateral: {formatTokenAmount(data.accountData.totalCollateralValue, 18, { maxFractionDigits: 2 })}</span>
                  <span>Debt: {formatTokenAmount(data.accountData.totalDebtValue, 18, { maxFractionDigits: 2 })}</span>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>Liquidation Proximity</CardTitle>
                  <CardDescription>Current liquidation threshold (weighted average)</CardDescription>
                </CardHeader>
                <CardContent className="text-sm">
                  <p>Threshold: {formatBps(Number(data.accountData.currentLiquidationThresholdBps))}</p>
                  <p className="mt-1 text-muted-foreground">
                    {hfStatus === "danger"
                      ? "Position is at risk of liquidation."
                      : hfStatus === "warning"
                        ? "Position is approaching the liquidation threshold."
                        : hfStatus === "no-debt"
                          ? "No outstanding debt — liquidation is not applicable."
                          : "Position has a healthy buffer above the liquidation threshold."}
                  </p>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>Protocol Restrictions</CardTitle>
                </CardHeader>
                <CardContent className="text-sm text-muted-foreground">
                  No protocol-wide restriction feed is wired up yet — see the RWA page for
                  per-asset eligibility and status.
                </CardContent>
              </Card>
            </div>
          );
        }}
      </DataStateView>
    </div>
  );
}
