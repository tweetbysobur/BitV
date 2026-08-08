import { cn } from "@/lib/utils";
import type { ComplianceStatus } from "@/services/cleanverse/types";

/**
 * Presentational only — renders whatever ComplianceStatus it's given.
 * Nothing in this component calls Cleanverse or fabricates a status; the
 * caller is responsible for producing a real ComplianceStatus once
 * services/cleanverse/client.ts is implemented for real.
 */
export function ComplianceStatusBadge({ status }: { status: ComplianceStatus }) {
  const { label, className } = describe(status);

  return (
    <span
      className={cn(
        "inline-flex items-center gap-2 rounded-md border px-3 py-1 text-sm font-medium",
        className
      )}
    >
      {label}
    </span>
  );
}

function describe(status: ComplianceStatus): { label: string; className: string } {
  switch (status.state) {
    case "loading":
      return { label: "Checking compliance…", className: "border-border text-muted-foreground" };
    case "verification-required":
      return { label: "Verification required", className: "border-accent text-accent" };
    case "eligible":
      return { label: "Eligible", className: "border-primary text-primary" };
    case "ineligible":
      return { label: "Ineligible", className: "border-destructive text-destructive" };
    case "error":
      return { label: `Compliance error: ${status.message}`, className: "border-destructive text-destructive" };
  }
}
