import { connectorsForWallets } from "@rainbow-me/rainbowkit";
import {
  metaMaskWallet,
  rabbyWallet,
  coinbaseWallet,
  walletConnectWallet,
  rainbowWallet,
  trustWallet,
  okxWallet,
  injectedWallet,
} from "@rainbow-me/rainbowkit/wallets";
import { createConfig, http } from "wagmi";
import { monadTestnet } from "./chains";

const walletConnectProjectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID;

if (!walletConnectProjectId) {
  // Fails loudly in dev rather than shipping a silently-broken wallet connector.
  console.warn(
    "NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID is not set — wallet connection will not work. See .env.example."
  );
}

/**
 * Explicit wallet list rather than RainbowKit's bare `getDefaultConfig`
 * curated set (Rainbow/MetaMask/Coinbase/WalletConnect only) — that
 * default left Rabby and other EIP-1193 injected EVM wallets without a
 * dedicated, reliably-clickable entry for users whose extension doesn't
 * announce itself the way RainbowKit's default detection expects.
 * `rabbyWallet` is Rabby's own dedicated RainbowKit connector;
 * `injectedWallet` is the catch-all fallback so any other installed EVM
 * wallet extension (Frame, Rabby-alikes, browser-native, etc.) still
 * gets a working "Injected" entry instead of being invisible.
 */
const connectors = connectorsForWallets(
  [
    {
      groupName: "Popular",
      wallets: [metaMaskWallet, rabbyWallet, coinbaseWallet, rainbowWallet],
    },
    {
      groupName: "More",
      wallets: [walletConnectWallet, trustWallet, okxWallet, injectedWallet],
    },
  ],
  {
    appName: "BitV",
    projectId: walletConnectProjectId ?? "",
  },
);

export const wagmiConfig = createConfig({
  chains: [monadTestnet],
  connectors,
  transports: {
    [monadTestnet.id]: http(),
  },
  ssr: true,
});
