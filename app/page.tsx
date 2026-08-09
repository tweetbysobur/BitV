import { MotionConfig } from "framer-motion";
import { LandingNav } from "@/components/landing/LandingNav";
import { Hero } from "@/components/landing/Hero";
import { InfrastructureStrip } from "@/components/landing/InfrastructureStrip";
import { Problem } from "@/components/landing/Problem";
import { Solution } from "@/components/landing/Solution";
import { Architecture } from "@/components/landing/Architecture";
import { RiskIntelligence } from "@/components/landing/RiskIntelligence";
import { LendingSection } from "@/components/landing/LendingSection";
import { RWASection } from "@/components/landing/RWASection";
import { VaultsSection } from "@/components/landing/VaultsSection";
import { Liquidity } from "@/components/landing/Liquidity";
import { Security } from "@/components/landing/Security";
import { MonadSection } from "@/components/landing/MonadSection";
import { ProductPreview } from "@/components/landing/ProductPreview";
import { HowItWorks } from "@/components/landing/HowItWorks";
import { FinalCTA } from "@/components/landing/FinalCTA";
import { LandingFooter } from "@/components/landing/LandingFooter";
import { ProtocolCapabilities } from "@/components/landing/ProtocolCapabilities";

export default function HomePage() {
  return (
    <MotionConfig reducedMotion="user">
      <main className="min-h-screen">
        <LandingNav />
        <Hero />
        <InfrastructureStrip />
        <Problem />
        <Solution />
        <Architecture />
        <ProtocolCapabilities />
        <RiskIntelligence />
        <LendingSection />
        <RWASection />
        <VaultsSection />
        <Liquidity />
        <Security />
        <MonadSection />
        <ProductPreview />
        <HowItWorks />
        <FinalCTA />
        <LandingFooter />
      </main>
    </MotionConfig>
  );
}
