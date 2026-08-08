"use client";

import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { DataStateView } from "@/components/dashboard/DataStateView";
import { CVIStatus } from "@/components/dashboard/CVIStatus";
import { BitScoreCard } from "@/components/dashboard/BitScoreCard";
import { HealthFactorCard } from "@/components/dashboard/HealthFactorCard";
import { BorrowingCapacityCard } from "@/components/dashboard/BorrowingCapacityCard";
import { ActivityTable } from "@/components/dashboard/ActivityTable";
import { UnavailableState } from "@/components/dashboard/ErrorState";
import { useWalletStatus } from "@/hooks/useWalletStatus";
import { useContractAddress } from "@/hooks/useContractAddress";
import { useLendingPosition } from "@/hooks/useLendingPosition";
import { useVaultPositions } from "@/hooks/useVaultPositions";
import { useRWAAssets } from "@/hooks/useRWAAssets";
import { formatTokenAmount } from "@/lib/format";

export default function OverviewPage() {
  const { state: walletState, address } = useWalletStatus();
  const lendingManagerAddress = useContractAddress("LendingManager");
  const lendingPosition = useLendingPosition();
  const vaults = useVaultPositions();
  const rwaAssets = useRWAAssets();

  if (walletState !== "connected") {
    return (
      <div className="mx-auto max-w-lg py-16 text-center">
        <h1 className="mb-2 font-heading text-2xl font-semibold">Connect your wallet</h1>
        <p className="text-muted-foreground">
          {walletState === "wrong-network" || walletState === "unsupported-network"
            ? "Switch to Monad Testnet to view your BitV dashboard."
            : "Connect a wallet to view your BitV protocol overview."}
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="font-heading text-2xl font-semibold">Overview</h1>
        <p className="text-sm text-muted-foreground">Wallet: {address}</p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>CVI Status</CardTitle>
            <CardDescription>Cleanverse Verified Identity eligibility</CardDescription>
          </CardHeader>
          <CardContent>
            <CVIStatus poolAddress={lendingManagerAddress} />
          </CardContent>
        </Card>

        <BitScoreCard />

        <DataStateView state={lendingPosition} loadingLabel="Reading lending position">
          {(data) => <HealthFactorCard healthFactorRay={data.accountData.healthFactorRay} />}
        </DataStateView>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>Total Supplied</CardTitle>
          </CardHeader>
          <CardContent>
            <DataStateView state={lendingPosition} loadingLabel="Reading">
              {(data) => (
                <p className="font-heading text-xl font-semibold tabular-nums">
                  {formatTokenAmount(data.accountData.totalCollateralValue, 18, { maxFractionDigits: 2 })}
                </p>
              )}
            </DataStateView>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Total Borrowed</CardTitle>
          </CardHeader>
          <CardContent>
            <DataStateView state={lendingPosition} loadingLabel="Reading">
              {(data) => (
                <p className="font-heading text-xl font-semibold tabular-nums">
                  {formatTokenAmount(data.accountData.totalDebtValue, 18, { maxFractionDigits: 2 })}
                </p>
              )}
            </DataStateView>
          </CardContent>
        </Card>

        <DataStateView state={lendingPosition} loadingLabel="Reading">
          {(data) => (
            <BorrowingCapacityCard
              effectiveAvailableBorrowValue={data.effectiveAvailableBorrowValue}
              baseAvailableBorrowValue={data.accountData.availableBorrowValue}
            />
          )}
        </DataStateView>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>RWA Collateral Value</CardTitle>
            <CardDescription>Registered RWA assets tracked by BitV</CardDescription>
          </CardHeader>
          <CardContent>
            <DataStateView
              state={rwaAssets}
              loadingLabel="Reading"
              emptyTitle="No RWA assets registered"
              emptyDescription="BitV has no RWA assets configured for this network yet."
            >
              {(rows) => <p className="text-sm text-muted-foreground">{rows.length} registered asset(s) — see the RWA page for detail.</p>}
            </DataStateView>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Vault Value</CardTitle>
            <CardDescription>Your positions across BitV yield vaults</CardDescription>
          </CardHeader>
          <CardContent>
            <DataStateView
              state={vaults}
              loadingLabel="Reading"
              emptyTitle="No vaults configured"
              emptyDescription="BitV has no yield vaults configured for this network yet."
            >
              {(rows) => <p className="text-sm text-muted-foreground">{rows.length} vault(s) — see the Vaults page for detail.</p>}
            </DataStateView>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Protocol Alerts</CardTitle>
        </CardHeader>
        <CardContent>
          <UnavailableState reason="No protocol-wide alert feed is wired up yet." />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Recent Activity</CardTitle>
        </CardHeader>
        <CardContent>
          <ActivityTable />
        </CardContent>
      </Card>
    </div>
  );
}
