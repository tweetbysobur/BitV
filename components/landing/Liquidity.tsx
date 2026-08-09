import { Reveal } from "./Reveal";

const POINTS = [
  { title: "Asset-specific pools", body: "Each supported asset has its own pool with its own risk configuration — nothing is pooled or priced generically." },
  { title: "Risk parameters", body: "LTV, liquidation threshold, liquidation bonus, and supply/borrow caps are set per pool by the risk manager." },
  { title: "Utilization", body: "Borrowed-to-supplied ratio drives the interest rate model for each pool, keeping incentives aligned with actual demand." },
  { title: "Protocol controls", body: "Pools can be paused, capped, or reconfigured by role-gated protocol operations without touching user funds directly." },
];

export function Liquidity() {
  return (
    <section className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Verified liquidity infrastructure
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-muted-foreground">
            Liquidity in BitV isn&apos;t a single shared pool — it&apos;s a set of independently
            configured markets that feed the same lending engine.
          </p>
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
