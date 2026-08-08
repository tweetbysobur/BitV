"use client";

import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { DataStateView } from "./DataStateView";
import { RiskTierBadge } from "./RiskTierBadge";
import { useBitScore } from "@/hooks/useBitScore";

/** Displays BitV's own 0-100 BitScore (never the legacy 0-1000 model) —
 * a BitV protocol-native risk signal, not a Cleanverse primitive. Does
 * not expose internal scoring implementation (decay accumulators,
 * liquidation-penalty bookkeeping) beyond score + tier. */
export function BitScoreCard() {
  const state = useBitScore();

  return (
    <Card>
      <CardHeader>
        <CardTitle>BitScore</CardTitle>
        <CardDescription>BitV&apos;s protocol-native lending risk signal (0-100).</CardDescription>
      </CardHeader>
      <CardContent>
        <DataStateView state={state} loadingLabel="Reading score">
          {(data) => (
            <div className="flex items-center gap-4">
              <div className="font-heading text-3xl font-semibold tabular-nums">{data.score}</div>
              <div className="flex flex-col gap-1">
                <RiskTierBadge tier={data.tier} />
                <span className="text-xs text-muted-foreground">out of 100</span>
              </div>
            </div>
          )}
        </DataStateView>
      </CardContent>
    </Card>
  );
}
