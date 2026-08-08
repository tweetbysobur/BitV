"use client";

import { DataStateView } from "@/components/dashboard/DataStateView";
import { VaultPositionCard } from "@/components/dashboard/VaultPositionCard";
import { useWalletStatus } from "@/hooks/useWalletStatus";
import { useVaultPositions } from "@/hooks/useVaultPositions";

export default function VaultsPage() {
  const { state: walletState } = useWalletStatus();
  const vaults = useVaultPositions();

  if (walletState !== "connected") {
    return <p className="text-muted-foreground">Connect your wallet to view your vault positions.</p>;
  }

  return (
    <div className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">Yield Vaults</h1>
      <DataStateView
        state={vaults}
        loadingLabel="Reading vault positions"
        emptyTitle="No vaults configured"
        emptyDescription="BitV has no yield vaults configured for this network yet."
      >
        {(rows) => (
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
            {rows.map((vault) => (
              <VaultPositionCard key={vault.vaultAddress} vault={vault} />
            ))}
          </div>
        )}
      </DataStateView>
    </div>
  );
}
