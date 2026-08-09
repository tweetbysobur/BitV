import type { Metadata } from "next";
import { poppins, montserrat } from "@/lib/fonts";
import { Web3Provider } from "@/components/providers/web3-provider";
import { siteConfig } from "@/config/site";
import "./globals.css";

const title = `${siteConfig.name} | ${siteConfig.tagline}`;
const description =
  "An identity-native DeFi protocol on Monad powered by verified identity, risk intelligence, and asset-aware infrastructure.";

export const metadata: Metadata = {
  title,
  description,
  openGraph: {
    title,
    description,
    type: "website",
  },
};

// Web3Provider constructs the RainbowKit/Wagmi config at render time, which
// requires a real NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID. Forcing dynamic
// rendering defers that to request time instead of build time, so `next
// build` doesn't require secrets to be present in the build environment.
export const dynamic = "force-dynamic";

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${poppins.variable} ${montserrat.variable}`}>
      <body>
        <Web3Provider>{children}</Web3Provider>
      </body>
    </html>
  );
}
