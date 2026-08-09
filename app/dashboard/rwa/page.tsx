"use client";

import Link from "next/link";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { DataStateView } from "@/components/dashboard/DataStateView";
import { RWAStatusCard } from "@/components/dashboard/RWAStatusCard";
import { CVIStatus } from "@/components/dashboard/CVIStatus";
import { useRWAAssets, type RWAAssetRow } from "@/hooks/useRWAAssets";
import { useCVAStatus } from "@/hooks/useCVAStatus";
import { useContractAddress } from "@/hooks/useContractAddress";

function RWAAssetCardWithCVA({ row }: { row: RWAAssetRow }) {
  const cva = useCVAStatus(row.assetAddress);
  const interfaceVerified = cva.status === "loaded" ? cva.data.interfaceVerified : undefined;
  return <RWAStatusCard row={row} cvaInterfaceVerified={interfaceVerified} />;
}

export default function RWAPage() {
  const rwaAssets = useRWAAssets();
  const lendingManagerAddress = useContractAddress("LendingManager");

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="font-heading text-2xl font-semibold">RWA Collateral</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          This registry only decides eligibility, LTV, and caps for RWA assets — it does not hold your position.
          Supply, borrow, repay, and withdraw against RWA collateral from the{" "}
          <Link href="/dashboard/lending" className="underline">
            Lending page
          </Link>
          .
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Cleanverse CVI</CardTitle>
          <CardDescription>
            Eligibility to post any collateral (including RWA) and borrow, checked against BitVLendingManager
          </CardDescription>
        </CardHeader>
        <CardContent>
          <CVIStatus poolAddress={lendingManagerAddress} />
        </CardContent>
      </Card>

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
