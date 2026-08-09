import { Reveal } from "./Reveal";
import { RiskTierBadge } from "@/components/dashboard/RiskTierBadge";

const FEATURES = [
  "Multi-collateral positions",
  "Multiple debt assets",
  "Risk-aware borrowing",
  "LTV controls",
  "Health factor",
  "Liquidation protection",
  "BitScore-adjusted parameters",
];

export function LendingSection() {
  return (
    <section id="lending" className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-5xl">
        <Reveal className="mx-auto max-w-2xl text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Risk-aware lending
          </h2>
          <p className="mt-4 text-muted-foreground">
            BitV&apos;s lending engine tracks collateral and debt per wallet, continuously
            re-evaluating health factor against each pool&apos;s risk parameters.
          </p>
        </Reveal>

        <div className="mt-14 grid grid-cols-1 gap-8 lg:grid-cols-2 lg:items-center">
          <Reveal>
            <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2">
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

          <Reveal delay={0.08}>
            <div className="rounded-lg border border-border bg-card p-6">
              <p className="text-xs uppercase tracking-widest text-muted-foreground">
                Illustrative position — not live data
              </p>
              <div className="mt-5 flex items-center justify-between">
                <span className="text-sm text-muted-foreground">Health factor</span>
                <span className="font-heading text-lg font-semibold text-success">1.62</span>
              </div>
              <div className="mt-3 h-2 w-full overflow-hidden rounded-full bg-muted">
                <div className="h-full w-3/4 rounded-full bg-success" />
              </div>

              <div className="mt-6 grid grid-cols-2 gap-4">
                <div>
                  <p className="text-xs text-muted-foreground">Collateral</p>
                  <p className="mt-1 font-heading text-sm font-semibold">2 assets</p>
                </div>
                <div>
                  <p className="text-xs text-muted-foreground">Debt</p>
                  <p className="mt-1 font-heading text-sm font-semibold">1 asset</p>
                </div>
                <div>
                  <p className="text-xs text-muted-foreground">Max LTV</p>
                  <p className="mt-1 font-heading text-sm font-semibold">70%</p>
                </div>
                <div>
                  <p className="text-xs text-muted-foreground">BitScore tier</p>
                  <p className="mt-1">
                    <RiskTierBadge tier="Established" />
                  </p>
                </div>
              </div>
            </div>
          </Reveal>
        </div>
      </div>
    </section>
  );
}
