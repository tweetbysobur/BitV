import { Reveal } from "./Reveal";

const POINTS = [
  "Anonymous risk assessment — most protocols treat every wallet identically, regardless of history.",
  "Over-collateralization — the default answer to unknown counterparty risk is simply more collateral.",
  "Weak identity signals — pseudonymous addresses give lenders almost nothing to price risk against.",
  "Limited asset-aware controls — real-world assets rarely get collateral treatment matched to their actual risk.",
  "Fragmented compliance — eligibility checks, if they exist at all, are bolted on rather than enforced on-chain.",
  "Poor institutional risk visibility — there's no protocol-native signal institutions can reason about before participating.",
];

export function Problem() {
  return (
    <section className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            DeFi lending has a trust problem
          </h2>
        </Reveal>

        <Reveal delay={0.08}>
          <ul className="mx-auto mt-10 grid max-w-3xl grid-cols-1 gap-4 sm:grid-cols-2">
            {POINTS.map((point) => (
              <li
                key={point}
                className="rounded-lg border border-border p-4 text-sm leading-relaxed text-muted-foreground"
              >
                {point}
              </li>
            ))}
          </ul>
        </Reveal>
      </div>
    </section>
  );
}
