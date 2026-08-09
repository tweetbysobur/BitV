import Link from "next/link";
import { Gauge } from "lucide-react";
import { RiskTierBadge } from "@/components/dashboard/RiskTierBadge";
import { BITSCORE_TIERS } from "@/lib/bitscore";
import { Reveal } from "./Reveal";

export function BitScoreTeaser() {
  return (
    <section className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-3xl text-center">
        <Reveal>
          <Gauge className="mx-auto text-accent" size={24} />
          <h2 className="mt-4 font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            BitScore
          </h2>
          <p className="mx-auto mt-4 max-w-xl text-muted-foreground">
            BitV&apos;s own protocol-level risk signal — a 0–100 score that adjusts lending
            parameters within limits the protocol defines.
          </p>
        </Reveal>

        <Reveal delay={0.08}>
          <div className="mt-10 flex flex-wrap justify-center gap-3">
            {BITSCORE_TIERS.map((tier) => (
              <RiskTierBadge key={tier.tier} tier={tier.tier} />
            ))}
          </div>
        </Reveal>

        <Reveal delay={0.12}>
          <Link href="/product#risk" className="mt-8 inline-block text-sm font-medium text-accent hover:underline">
            How BitScore works →
          </Link>
        </Reveal>
      </div>
    </section>
  );
}
