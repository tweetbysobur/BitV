import { RiskTierBadge } from "@/components/dashboard/RiskTierBadge";
import { BITSCORE_TIERS } from "@/lib/bitscore";
import { Reveal } from "./Reveal";

export function RiskIntelligence() {
  return (
    <section id="risk-intelligence" className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="mx-auto max-w-2xl text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Risk intelligence: BitScore
          </h2>
          <p className="mt-4 text-muted-foreground">
            BitScore is a 0–100 protocol-native score maintained on-chain by BitV. It adjusts
            lending parameters within limits the risk manager configures — it is not a
            guarantee of safety or creditworthiness, and it does not replace pool-level risk
            controls like liquidation thresholds and caps.
          </p>
        </Reveal>

        <Reveal delay={0.1}>
          <div className="mt-12 grid grid-cols-2 gap-4 sm:grid-cols-4">
            {BITSCORE_TIERS.map((tier) => (
              <div key={tier.tier} className="rounded-lg border border-border p-5 text-center">
                <RiskTierBadge tier={tier.tier} />
                <p className="mt-3 font-heading text-lg font-semibold">
                  {tier.min}–{tier.max}
                </p>
              </div>
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  );
}
