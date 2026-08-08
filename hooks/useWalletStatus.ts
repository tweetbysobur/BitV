"use client";

import { useAccount } from "wagmi";
import { monadTestnet } from "@/config/chains";
import { deriveWalletConnectionState, type WalletConnectionState } from "@/lib/network";

export interface WalletStatus {
  state: WalletConnectionState;
  address: `0x${string}` | undefined;
  chainId: number | undefined;
  expectedChainId: number;
}

/** Single source of truth for wallet/network connection state, built on
 * the existing Wagmi/RainbowKit configuration (components/providers/
 * web3-provider.tsx) — no second wallet provider is introduced. */
export function useWalletStatus(): WalletStatus {
  const { address, isConnected, isConnecting, isReconnecting, chainId } = useAccount();

  const state = deriveWalletConnectionState({
    isConnected,
    isConnecting: isConnecting || isReconnecting,
    chainId,
    expectedChainId: monadTestnet.id,
  });

  return { state, address, chainId, expectedChainId: monadTestnet.id };
}
