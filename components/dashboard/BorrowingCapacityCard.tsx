import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { formatTokenAmount } from "@/lib/format";

/** Available borrowing capacity — the BitScore-adjusted figure
 * (BitVLendingManager.getEffectiveAvailableBorrowValue), presented
 * alongside the base (score-independent) figure for transparency. Value
 * unit is the protocol's shared 18-decimal price-value unit (see
 * BitVLendingManager._valueOf), not a specific token. */
export function BorrowingCapacityCard({
  effectiveAvailableBorrowValue,
  baseAvailableBorrowValue,
}: {
  effectiveAvailableBorrowValue: bigint | undefined;
  baseAvailableBorrowValue: bigint | undefined;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Available Borrowing Capacity</CardTitle>
        <CardDescription>BitScore-adjusted, in the protocol&apos;s shared value unit (18 decimals).</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="font-heading text-2xl font-semibold tabular-nums">
          {formatTokenAmount(effectiveAvailableBorrowValue, 18, { maxFractionDigits: 2 })}
        </div>
        {baseAvailableBorrowValue !== undefined && effectiveAvailableBorrowValue !== baseAvailableBorrowValue ? (
          <p className="mt-1 text-xs text-muted-foreground">
            Base (no BitScore adjustment): {formatTokenAmount(baseAvailableBorrowValue, 18, { maxFractionDigits: 2 })}
          </p>
        ) : null}
      </CardContent>
    </Card>
  );
}
