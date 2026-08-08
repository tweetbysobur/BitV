import { Badge, type BadgeTone } from "@/components/ui/badge";
import type { BitScoreTier } from "@/lib/bitscore";

const TONE: Record<BitScoreTier, BadgeTone> = {
  Restricted: "destructive",
  Standard: "neutral",
  Established: "accent",
  Trusted: "success",
};

export function RiskTierBadge({ tier }: { tier: BitScoreTier }) {
  return <Badge tone={TONE[tier]}>{tier}</Badge>;
}
