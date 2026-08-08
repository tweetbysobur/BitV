import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge, type BadgeTone } from "@/components/ui/badge";
import { formatHealthFactor, getHealthFactorStatus, type HealthFactorStatus } from "@/lib/health-factor";

const TONE: Record<HealthFactorStatus, BadgeTone> = {
  "no-debt": "neutral",
  healthy: "success",
  warning: "warning",
  danger: "destructive",
  unavailable: "neutral",
};

const LABEL: Record<HealthFactorStatus, string> = {
  "no-debt": "No outstanding debt",
  healthy: "Healthy",
  warning: "Approaching liquidation threshold",
  danger: "At risk of liquidation",
  unavailable: "Unavailable",
};

export function HealthFactorCard({ healthFactorRay }: { healthFactorRay: bigint | undefined }) {
  const status = getHealthFactorStatus(healthFactorRay);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Health Factor</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="flex items-center gap-4">
          <div className="font-heading text-3xl font-semibold tabular-nums">
            {formatHealthFactor(healthFactorRay)}
          </div>
          <Badge tone={TONE[status]}>{LABEL[status]}</Badge>
        </div>
      </CardContent>
    </Card>
  );
}
