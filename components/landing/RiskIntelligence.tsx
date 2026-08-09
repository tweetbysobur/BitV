import { RiskTierBadge } from "@/components/dashboard/RiskTierBadge";
import { BITSCORE_TIERS } from "@/lib/bitscore";
import { Reveal } from "./Reveal";

export function RiskIntelligence() {
  return (
    <section id="risk" className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="mx-auto max-w-2xl text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            BitScore: BitV&apos;s risk layer
          </h2>
          <p className="mt-4 text-muted-foreground">
            BitScore is BitV&apos;s own protocol-level risk signal, maintained entirely on-chain.
            Every wallet starts at a neutral score of <span className="font-medium text-foreground">30</span> on
            a 0–100 scale and moves within it based on on-chain behavior inside BitV.
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

        <Reveal delay={0.16}>
          <div className="mt-8 rounded-lg border border-border bg-muted/50 p-5">
            <p className="text-sm leading-relaxed text-muted-foreground">
              BitScore adjusts lending parameters — like a wallet&apos;s effective LTV — within
              limits the protocol&apos;s risk manager configures. It does not grant or override
              CVI eligibility, does not guarantee safety or creditworthiness, and is not derived
              from personal identity data.
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
