import { KeyRound, ShieldCheck, Gauge, Building2, Coins, Link2 } from "lucide-react";
import { Reveal } from "./Reveal";

const CAPABILITIES = [
  {
    icon: KeyRound,
    title: "Identity-native access",
    body: "Every protocol interaction is gated by Cleanverse CVI eligibility, checked directly on-chain before any lending or vault action executes.",
  },
  {
    icon: ShieldCheck,
    title: "Risk-aware lending",
    body: "Supply, borrow, and collateral limits are enforced per-pool by the risk manager — LTV, liquidation threshold, liquidation bonus, and caps are all on-chain parameters.",
  },
  {
    icon: Gauge,
    title: "BitScore",
    body: "A 0–100 protocol-native risk signal that adjusts a wallet's effective LTV within the bounds the risk manager configures — never overriding the underlying pool limits.",
  },
  {
    icon: Building2,
    title: "RWA collateral",
    body: "A dedicated registry tracks real-world-asset collateral — its own LTV, liquidation threshold, collateral cap, and oracle-freshness checks — layered on top of the core lending engine.",
  },
  {
    icon: Coins,
    title: "Yield vaults",
    body: "ERC-4626 vaults with pluggable strategies, deposit caps, and pausability, so vault deposits stay bounded and strategy risk stays contained.",
  },
  {
    icon: Link2,
    title: "CVA-aware infrastructure",
    body: "Assets can carry Cleanverse Verified Asset status via the CVA adapter — surfaced honestly in the protocol, never assumed by default.",
  },
];

export function ProtocolCapabilities() {
  return (
    <section id="protocol" className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-6xl">
        <Reveal className="mx-auto max-w-2xl text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            What BitV does today
          </h2>
          <p className="mt-4 text-muted-foreground">
            Every capability below is implemented in BitV&apos;s deployed contracts — nothing here is planned or aspirational.
          </p>
        </Reveal>

        <div className="mt-14 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {CAPABILITIES.map((cap, i) => (
            <Reveal key={cap.title} delay={(i % 3) * 0.06}>
              <div className="h-full rounded-lg border border-border p-6 transition-colors hover:border-accent/40">
                <cap.icon className="text-accent" size={20} />
                <h3 className="mt-4 font-heading text-base font-semibold">{cap.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{cap.body}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
