"use client";

import { type ReactNode, useState } from "react";
import { WagmiProvider } from "wagmi";
import { RainbowKitProvider, lightTheme } from "@rainbow-me/rainbowkit";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { wagmiConfig } from "@/config/wagmi";

import "@rainbow-me/rainbowkit/styles.css";

/**
 * RainbowKit's default theme is blue — it has nothing to do with BitV's
 * black/white/orange brand and was never overridden, so the wallet
 * connect widget (one of the most-seen interactive elements on the
 * whole product) has been rendering off-brand this whole time. This
 * maps RainbowKit's theme tokens onto the same design tokens used
 * everywhere else (see app/globals.css) so the connect button reads as
 * part of BitV, not a generic crypto widget bolted on.
 */
const bitvWalletTheme = lightTheme({
  accentColor: "#f97015", // hsl(24 95% 53%) — the exact BitV orange from app/globals.css's --accent
  accentColorForeground: "#0d0d0d",
  borderRadius: "medium",
  fontStack: "system",
  overlayBlur: "small",
});

export function Web3Provider({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={bitvWalletTheme}>{children}</RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
