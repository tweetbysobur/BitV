import { MotionConfig } from "framer-motion";
import { LandingNav } from "@/components/landing/LandingNav";
import { Hero } from "@/components/landing/Hero";
import { InfrastructureStrip } from "@/components/landing/InfrastructureStrip";
import { Problem } from "@/components/landing/Problem";
import { Solution } from "@/components/landing/Solution";
import { CoreCapabilities } from "@/components/landing/CoreCapabilities";
import { BitScoreTeaser } from "@/components/landing/BitScoreTeaser";
import { ProductPreview } from "@/components/landing/ProductPreview";
import { FinalCTA } from "@/components/landing/FinalCTA";
import { LandingFooter } from "@/components/landing/LandingFooter";

export default function HomePage() {
  return (
    <MotionConfig reducedMotion="user">
      <main className="min-h-screen">
        <LandingNav />
        <Hero />
        <InfrastructureStrip />
        <Problem />
        <Solution />
        <CoreCapabilities />
        <BitScoreTeaser />
        <ProductPreview />
        <FinalCTA />
        <LandingFooter />
      </main>
    </MotionConfig>
  );
}
