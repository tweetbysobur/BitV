"use client";

import { DataStateView } from "@/components/dashboard/DataStateView";
import { RWAStatusCard } from "@/components/dashboard/RWAStatusCard";
import { useRWAAssets, type RWAAssetRow } from "@/hooks/useRWAAssets";
import { useCVAStatus } from "@/hooks/useCVAStatus";

function RWAAssetCardWithCVA({ row }: { row: RWAAssetRow }) {
  const cva = useCVAStatus(row.assetAddress);
  const interfaceVerified = cva.status === "loaded" ? cva.data.interfaceVerified : undefined;
  return <RWAStatusCard row={row} cvaInterfaceVerified={interfaceVerified} />;
}

export default function RWAPage() {
  const rwaAssets = useRWAAssets();

  return (
    <div className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">RWA Collateral</h1>
      <DataStateView
        state={rwaAssets}
        loadingLabel="Reading RWA registry"
        emptyTitle="No RWA assets registered"
        emptyDescription="BitV has no RWA assets configured for this network yet."
      >
        {(rows) => (
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
            {rows.map((row) => (
              <RWAAssetCardWithCVA key={row.assetAddress} row={row} />
            ))}
          </div>
        )}
      </DataStateView>
    </div>
  );
}
