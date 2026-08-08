"use client";

import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { useWalletStatus } from "@/hooks/useWalletStatus";
import { monadTestnet } from "@/config/chains";

export default function SettingsPage() {
  const { address, chainId, state } = useWalletStatus();

  return (
    <div className="flex flex-col gap-6">
      <h1 className="font-heading text-2xl font-semibold">Settings</h1>

      <Card>
        <CardHeader>
          <CardTitle>Wallet</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-1 text-sm">
          <span>Address: {address ?? "Not connected"}</span>
          <span>Connection status: {state}</span>
          <span>Chain ID: {chainId ?? "Unavailable"}</span>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Network</CardTitle>
          <CardDescription>BitV supports Monad Testnet only — no mainnet deployment exists.</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-1 text-sm">
          <span>Network: {monadTestnet.name}</span>
          <span>Expected chain ID: {monadTestnet.id}</span>
        </CardContent>
      </Card>
    </div>
  );
}
