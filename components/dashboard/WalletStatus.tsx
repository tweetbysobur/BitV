"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useWalletStatus } from "@/hooks/useWalletStatus";
import { Badge } from "@/components/ui/badge";

const STATE_LABEL: Record<string, string> = {
  disconnected: "Not connected",
  connecting: "Connecting…",
  connected: "Connected",
  "wrong-network": "Wrong network",
  "unsupported-network": "Unsupported network",
};

export function WalletStatus() {
  const { state, chainId, expectedChainId } = useWalletStatus();

  return (
    <div className="flex items-center gap-3">
      {state === "wrong-network" || state === "unsupported-network" ? (
        <Badge tone="warning" role="status">
          {STATE_LABEL[state]} {chainId !== undefined ? `(chain ${chainId}, expected ${expectedChainId})` : ""}
        </Badge>
      ) : null}
      <ConnectButton
        showBalance={false}
        chainStatus="icon"
        accountStatus={{ smallScreen: "avatar", largeScreen: "full" }}
      />
    </div>
  );
}
