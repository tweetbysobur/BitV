import { Reveal } from "./Reveal";

const POINTS = [
  { title: "Fast settlement", body: "Sub-second block times keep lending, liquidation, and vault actions responsive." },
  { title: "Low-cost transactions", body: "Cheap execution makes frequent risk-parameter updates and liquidations practical, not prohibitive." },
  { title: "DeFi execution", body: "Full EVM compatibility means BitV's Solidity contracts deploy and behave exactly as designed." },
  { title: "Infrastructure scalability", body: "Room to grow the number of pools, vaults, and RWA assets without contention on a congested base layer." },
];

export function MonadSection() {
  return (
    <section className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Why Monad
          </h2>
        </Reveal>

        <div className="mt-14 grid grid-cols-1 gap-6 sm:grid-cols-2">
          {POINTS.map((point, i) => (
            <Reveal key={point.title} delay={i * 0.06}>
              <div className="h-full rounded-lg border border-border p-5">
                <h3 className="font-heading text-sm font-semibold">{point.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{point.body}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
