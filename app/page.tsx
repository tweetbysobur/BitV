import { LandingNav } from "@/components/landing/LandingNav";
import { Hero } from "@/components/landing/Hero";
import { TrustInfrastructure } from "@/components/landing/TrustInfrastructure";
import { ProtocolCapabilities } from "@/components/landing/ProtocolCapabilities";
import { HowItWorks } from "@/components/landing/HowItWorks";
import { RiskIntelligence } from "@/components/landing/RiskIntelligence";
import { CompliantDeFi } from "@/components/landing/CompliantDeFi";
import { ProtocolStatus } from "@/components/landing/ProtocolStatus";
import { DashboardCTA } from "@/components/landing/DashboardCTA";
import { LandingFooter } from "@/components/landing/LandingFooter";

export default function HomePage() {
  return (
    <main className="min-h-screen">
      <LandingNav />
      <Hero />
      <TrustInfrastructure />
      <ProtocolCapabilities />
      <HowItWorks />
      <RiskIntelligence />
      <CompliantDeFi />
      <ProtocolStatus />
      <DashboardCTA />
      <LandingFooter />
    </main>
  );
}
