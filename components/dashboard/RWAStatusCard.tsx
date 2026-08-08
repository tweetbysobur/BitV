import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge, type BadgeTone } from "@/components/ui/badge";
import { describeRWAStatusForNewActivity, type RWAAssetStatus } from "@/lib/rwa";
import { deriveCVALabel, CVA_RECOGNITION_DISCLAIMER } from "@/lib/cva";
import { formatBps } from "@/lib/format";
import type { RWAAssetRow } from "@/hooks/useRWAAssets";

const STATUS_TONE: Record<RWAAssetStatus, BadgeTone> = {
  Unregistered: "neutral",
  Active: "success",
  Frozen: "warning",
  Delisted: "destructive",
};

/** One RWA asset's full status — asset registry status, oracle/LTV
 * config, and CVA recognition kept as three visually distinct pieces of
 * information (never merged), per the RWA page's requirements. */
export function RWAStatusCard({
  row,
  cvaInterfaceVerified,
}: {
  row: RWAAssetRow;
  /** From useCVAStatus — a separate, live read; `undefined` if not yet
   * loaded (RWAAssetRow's own `adminAttestedCVA` field is loaded
   * alongside the rest of the asset config, but interface verification
   * is a second, independent read through BitVCVAAdapter). */
  cvaInterfaceVerified: boolean | undefined;
}) {
  const cvaLabel =
    cvaInterfaceVerified === undefined
      ? undefined
      : deriveCVALabel({ adminAttestedCVA: row.adminAttestedCVA, interfaceVerified: cvaInterfaceVerified });

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between gap-2">
        <CardTitle>{row.symbol ?? row.assetAddress}</CardTitle>
        <Badge tone={STATUS_TONE[row.status]}>{row.status}</Badge>
      </CardHeader>
      <CardContent className="flex flex-col gap-3 text-sm">
        <p className="text-muted-foreground">{describeRWAStatusForNewActivity(row.status)}</p>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1">
          <dt className="text-muted-foreground">LTV</dt>
          <dd className="tabular-nums">{formatBps(row.ltvBps)}</dd>
          <dt className="text-muted-foreground">Liquidation threshold</dt>
          <dd className="tabular-nums">{formatBps(row.liquidationThresholdBps)}</dd>
          <dt className="text-muted-foreground">Borrowing eligibility</dt>
          <dd>{row.eligibleForNewActivity ? "Eligible for new borrowing" : "Not eligible for new borrowing"}</dd>
        </dl>
        <div className="border-t border-border pt-3">
          <p className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">CVA status</p>
          <div className="flex flex-col gap-1">
            <span>Admin attested: {row.adminAttestedCVA ? "Yes" : "No"}</span>
            <span>
              Interface verified:{" "}
              {cvaInterfaceVerified === undefined ? "Unavailable" : cvaInterfaceVerified ? "Yes" : "No"}
            </span>
            {cvaLabel ? <span className="font-medium">{cvaLabel}</span> : null}
            <p className="mt-1 text-xs text-muted-foreground">{CVA_RECOGNITION_DISCLAIMER}</p>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
