import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { formatTokenAmount, formatRayAsPercent } from "@/lib/format";
import type { PoolPositionRow } from "@/hooks/usePoolPositions";

export function PoolPositionCard({ pool }: { pool: PoolPositionRow }) {
  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between gap-2">
        <CardTitle>{pool.symbol ?? pool.assetAddress}</CardTitle>
        <div className="flex gap-2">
          {!pool.isActive ? <Badge tone="neutral">Inactive</Badge> : null}
          {pool.isPaused ? <Badge tone="warning">Paused</Badge> : null}
        </div>
      </CardHeader>
      <CardContent>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt className="text-muted-foreground">Total supplied</dt>
          <dd className="tabular-nums">{formatTokenAmount(pool.totalSupplied, pool.decimals ?? 18)}</dd>
          <dt className="text-muted-foreground">Total borrowed</dt>
          <dd className="tabular-nums">{formatTokenAmount(pool.totalBorrowed, pool.decimals ?? 18)}</dd>
          <dt className="text-muted-foreground">Available liquidity</dt>
          <dd className="tabular-nums">{formatTokenAmount(pool.availableLiquidity, pool.decimals ?? 18)}</dd>
          <dt className="text-muted-foreground">Utilization</dt>
          <dd className="tabular-nums">{formatRayAsPercent(pool.utilizationRay)}</dd>
          <dt className="text-muted-foreground">Your position</dt>
          <dd className="tabular-nums">{formatTokenAmount(pool.userBalance, pool.decimals ?? 18)}</dd>
          <dt className="text-muted-foreground">Borrowing</dt>
          <dd>{pool.isBorrowingEnabled ? "Enabled" : "Disabled"}</dd>
          <dt className="text-muted-foreground">Collateral</dt>
          <dd>{pool.isCollateralEnabled ? "Enabled" : "Disabled"}</dd>
        </dl>
      </CardContent>
    </Card>
  );
}
