import { Coins } from "lucide-react";
import { Reveal } from "./Reveal";

const FEATURES = [
  "ERC-4626 vault architecture",
  "Controlled, pluggable strategies",
  "Compliance-aware deposits and withdrawals",
  "Deposit caps and pause controls",
  "Performance-fee architecture",
  "Emergency withdrawal",
];

export function VaultsSection() {
  return (
    <section id="vaults" className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="text-center">
          <Coins className="mx-auto text-accent" size={24} />
          <h2 className="mt-4 font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Yield vaults
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-muted-foreground">
            BitV&apos;s yield vaults follow the ERC-4626 standard, with deposits gated by the same
            compliance layer as the rest of the protocol and strategy risk contained by caps,
            pausability, and emergency withdrawal.
          </p>
        </Reveal>

        <Reveal delay={0.08}>
          <ul className="mx-auto mt-12 grid max-w-2xl grid-cols-1 gap-3 sm:grid-cols-2">
            {FEATURES.map((feature) => (
              <li
                key={feature}
                className="rounded-md border border-border px-4 py-3 text-sm text-foreground"
              >
                {feature}
              </li>
            ))}
          </ul>
        </Reveal>

        <Reveal delay={0.14}>
          <div className="mt-8 rounded-lg border border-border bg-muted/50 p-5">
            <p className="text-sm leading-relaxed text-muted-foreground">
              The currently deployed testnet strategy is a non-production test strategy used to
              verify vault mechanics end to end — it does not generate real yield, and vault
              activity shown in the dashboard is never presented as a live APY.
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
