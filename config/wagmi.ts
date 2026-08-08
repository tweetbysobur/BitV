import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { monadTestnet } from "./chains";

const walletConnectProjectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID;

if (!walletConnectProjectId) {
  // Fails loudly in dev rather than shipping a silently-broken wallet connector.
  console.warn(
    "NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID is not set — wallet connection will not work. See .env.example."
  );
}

export const wagmiConfig = getDefaultConfig({
  appName: "BitV",
  projectId: walletConnectProjectId ?? "",
  chains: [monadTestnet],
  ssr: true,
});
