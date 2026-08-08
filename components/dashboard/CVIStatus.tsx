"use client";

import { Badge, type BadgeTone } from "@/components/ui/badge";
import { useCVIStatus } from "@/hooks/useCVIStatus";
import type { Address } from "viem";
import type { CVIStatus as CVIStatusValue } from "@/lib/cvi";

const LABEL: Record<CVIStatusValue, string> = {
  verified: "Verified",
  "not-verified": "Not Verified",
  unavailable: "Unavailable",
};

const TONE: Record<CVIStatusValue, BadgeTone> = {
  verified: "success",
  "not-verified": "destructive",
  unavailable: "neutral",
};

/** CVI (participant) eligibility only — never merged with CVA (asset)
 * status, which has its own component (CVAStatusBadge, on the RWA
 * page). See lib/cvi.ts. */
export function CVIStatus({ poolAddress }: { poolAddress: Address | undefined }) {
  const { status, isLoading } = useCVIStatus(poolAddress);

  return (
    <div className="flex flex-col gap-1">
      <Badge tone={TONE[status]} role="status" aria-live="polite">
        {isLoading ? "Checking…" : LABEL[status]}
      </Badge>
      <p className="text-xs text-muted-foreground">
        Cleanverse Verified Identity (CVI) eligibility — checked against BitV&apos;s compliance gate only.
        Not a claim about any specific asset&apos;s CVA status.
      </p>
    </div>
  );
}
