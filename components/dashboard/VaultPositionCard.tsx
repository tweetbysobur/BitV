import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { getStrategyLabel, getPerformanceLabel } from "@/lib/vault";
import { formatTokenAmount, formatBps } from "@/lib/format";
import type { VaultPositionRow } from "@/hooks/useVaultPositions";

export function VaultPositionCard({ vault }: { vault: VaultPositionRow }) {
  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between gap-2">
        <CardTitle>{vault.vaultAddress}</CardTitle>
        {vault.isTestStrategy ? <Badge tone="warning">Test / non-production</Badge> : null}
      </CardHeader>
      <CardContent className="flex flex-col gap-2 text-sm">
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1">
          <dt className="text-muted-foreground">Underlying asset</dt>
          <dd>{vault.underlyingAsset ?? "Unavailable"}</dd>
          <dt className="text-muted-foreground">Your deposit (asset value)</dt>
          <dd className="tabular-nums">{formatTokenAmount(vault.userUnderlyingValue, 18)}</dd>
          <dt className="text-muted-foreground">Your shares</dt>
          <dd className="tabular-nums">
            {vault.shareDecimals !== undefined ? formatTokenAmount(vault.userShares, vault.shareDecimals) : "Unavailable"}
          </dd>
          <dt className="text-muted-foreground">Total assets in vault</dt>
          <dd className="tabular-nums">{formatTokenAmount(vault.totalAssets, 18)}</dd>
          <dt className="text-muted-foreground">Current strategy</dt>
          <dd>{getStrategyLabel(vault.isTestStrategy)}</dd>
          <dt className="text-muted-foreground">Estimated performance</dt>
          <dd>{getPerformanceLabel(vault.isTestStrategy)}</dd>
          <dt className="text-muted-foreground">Performance fee</dt>
          <dd className="tabular-nums">
            {vault.performanceFeeBps !== undefined ? formatBps(Number(vault.performanceFeeBps)) : "Unavailable"}
          </dd>
          <dt className="text-muted-foreground">Deposits</dt>
          <dd>{vault.depositsPaused === undefined ? "Unavailable" : vault.depositsPaused ? "Paused" : "Open"}</dd>
          <dt className="text-muted-foreground">Withdrawals</dt>
          <dd>
            {vault.withdrawalsPaused === undefined ? "Unavailable" : vault.withdrawalsPaused ? "Paused" : "Open"}
          </dd>
        </dl>
      </CardContent>
    </Card>
  );
}
