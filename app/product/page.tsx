import type { Metadata } from "next";
import { MotionConfig } from "framer-motion";
import { LandingNav } from "@/components/landing/LandingNav";
import { Reveal } from "@/components/landing/Reveal";
import { Architecture } from "@/components/landing/Architecture";
import { ProtocolCapabilities } from "@/components/landing/ProtocolCapabilities";
import { LendingSection } from "@/components/landing/LendingSection";
import { Liquidity } from "@/components/landing/Liquidity";
import { VaultsSection } from "@/components/landing/VaultsSection";
import { RWASection } from "@/components/landing/RWASection";
import { RiskIntelligence } from "@/components/landing/RiskIntelligence";
import { CVICVA } from "@/components/landing/CVICVA";
import { TreasurySection } from "@/components/landing/TreasurySection";
import { Security } from "@/components/landing/Security";
import { MonadSection } from "@/components/landing/MonadSection";
import { FinalCTA } from "@/components/landing/FinalCTA";
import { LandingFooter } from "@/components/landing/LandingFooter";

export const metadata: Metadata = {
  title: "The BitV Protocol | BitV",
  description:
    "How BitV's identity-native lending, RWA collateral, yield vaults, and risk infrastructure fit together.",
};

export default function ProductPage() {
  return (
    <MotionConfig reducedMotion="user">
      <main className="min-h-screen">
        <LandingNav />

        <section className="px-6 pb-16 pt-20 sm:pt-28">
          <Reveal className="mx-auto max-w-3xl text-center">
            <p className="mb-4 text-xs font-medium uppercase tracking-widest text-accent">
              Protocol overview
            </p>
            <h1 className="font-heading text-4xl font-semibold tracking-tight sm:text-5xl">
              The BitV Protocol
            </h1>
            <p className="mx-auto mt-4 max-w-2xl text-muted-foreground">
              Every piece of BitV explained: how identity, risk, lending, collateral, and yield
              fit together on Monad.
            </p>
          </Reveal>
        </section>

        <Architecture />
        <ProtocolCapabilities />
        <LendingSection />
        <Liquidity />
        <VaultsSection />
        <RWASection />
        <RiskIntelligence />
        <CVICVA />
        <TreasurySection />
        <Security />
        <MonadSection />
        <FinalCTA />
        <LandingFooter />
      </main>
    </MotionConfig>
  );
}
