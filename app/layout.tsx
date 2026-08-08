import type { Metadata } from "next";
import { poppins, montserrat } from "@/lib/fonts";
import { Web3Provider } from "@/components/providers/web3-provider";
import { siteConfig } from "@/config/site";
import "./globals.css";

export const metadata: Metadata = {
  title: `${siteConfig.name} — ${siteConfig.tagline}`,
  description: `${siteConfig.name} is an identity-native DeFi protocol on ${siteConfig.network}, built on ${siteConfig.infrastructure}.`,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${poppins.variable} ${montserrat.variable}`}>
      <body>
        <Web3Provider>{children}</Web3Provider>
      </body>
    </html>
  );
}
