import { Badge, type BadgeTone } from "@/components/ui/badge";

export type ProtocolAlertSeverity = "info" | "warning" | "critical";

const TONE: Record<ProtocolAlertSeverity, BadgeTone> = {
  info: "neutral",
  warning: "warning",
  critical: "destructive",
};

export interface ProtocolAlertData {
  severity: ProtocolAlertSeverity;
  message: string;
}

export function ProtocolAlert({ alert }: { alert: ProtocolAlertData }) {
  return (
    <div className="flex items-start gap-2 rounded-md border border-border p-3 text-sm">
      <Badge tone={TONE[alert.severity]}>{alert.severity}</Badge>
      <p>{alert.message}</p>
    </div>
  );
}
