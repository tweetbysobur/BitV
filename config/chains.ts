import { defineChain } from "viem";

const rpcUrl = process.env.NEXT_PUBLIC_MONAD_TESTNET_RPC_URL;

if (!rpcUrl) {
  // The public RPC is rate-limited and not fit for real usage, so we don't
  // silently fall back to it — the env var must be set explicitly. See
  // .env.example and docs/architecture.md for the verified values.
  console.warn(
    "NEXT_PUBLIC_MONAD_TESTNET_RPC_URL is not set — Monad Testnet RPC calls will fail. See .env.example."
  );
}

/**
 * Monad Testnet — BitV's target network.
 * Chain ID, native currency, and block explorer verified against Monad's
 * official docs/registries (see docs/architecture.md for sources and date).
 * The RPC URL is intentionally not hardcoded — it comes from
 * NEXT_PUBLIC_MONAD_TESTNET_RPC_URL so environments can point at their own
 * (non-rate-limited) endpoint.
 */
export const monadTestnet = defineChain({
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "Monad", symbol: "MON", decimals: 18 },
  rpcUrls: {
    default: { http: rpcUrl ? [rpcUrl] : [] },
  },
  blockExplorers: {
    default: { name: "Monad Explorer", url: "https://testnet.monadexplorer.com" },
  },
  testnet: true,
});
