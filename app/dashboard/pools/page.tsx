"use client";

import { DataStateView } from "@/components/dashboard/DataStateView";
import { PoolPositionCard } from "@/components/dashboard/PoolPositionCard";
import { usePoolPositions } from "@/hooks/usePoolPositions";

export default function PoolsPage() {
  const pools = usePoolPositions();

  return (
    <div className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">Pools</h1>
      <DataStateView
        state={pools}
        loadingLabel="Reading pool data"
        emptyTitle="No pools configured"
        emptyDescription="BitV has no lending pools configured for this network yet."
      >
        {(rows) => (
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
            {rows.map((pool) => (
              <PoolPositionCard key={pool.assetAddress} pool={pool} />
            ))}
          </div>
        )}
      </DataStateView>
    </div>
  );
}
