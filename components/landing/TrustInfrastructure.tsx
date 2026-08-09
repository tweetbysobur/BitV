import { ShieldCheck, Gauge, Landmark } from "lucide-react";
import { Reveal } from "./Reveal";

const LAYERS = [
  {
    icon: ShieldCheck,
    title: "Cleanverse CVI — eligibility",
    body:
      "Cleanverse's Compliant Verified Identity determines whether a wallet is eligible to use the protocol at all. It is an access gate, not a risk score.",
  },
  {
    icon: Gauge,
    title: "BitScore — protocol risk",
    body:
      "Once a wallet is eligible, BitV's own on-chain BitScore (0–100) adjusts lending parameters — like maximum LTV — within limits the protocol's risk manager sets. BitScore is not an identity check and does not affect eligibility.",
  },
  {
    icon: Landmark,
    title: "RWA & yield infrastructure",
    body:
      "Real-world-asset collateral is tracked through a dedicated registry layered on top of the existing lending engine, and yield vaults route deposits through pluggable, permissioned strategies — both still gated by the same CVI eligibility check.",
  },
];

export function TrustInfrastructure() {
  return (
    <section className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-6xl">
        <Reveal className="mx-auto max-w-2xl text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Two separate layers, one protocol
          </h2>
          <p className="mt-4 text-muted-foreground">
            BitV keeps eligibility and risk deliberately separate. Cleanverse CVI decides
            who can use the protocol; BitScore decides how the protocol treats them once they&apos;re in.
          </p>
        </Reveal>

        <div className="mt-14 grid grid-cols-1 gap-6 md:grid-cols-3">
          {LAYERS.map((layer, i) => (
            <Reveal key={layer.title} delay={i * 0.08}>
              <div className="h-full rounded-lg border border-border p-6">
                <layer.icon className="text-accent" size={22} />
                <h3 className="mt-4 font-heading text-base font-semibold">{layer.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{layer.body}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
