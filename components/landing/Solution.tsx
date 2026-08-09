import { Reveal } from "./Reveal";

const CHAIN = ["Identity", "Compliance", "Risk", "Capital"];

const LAYERS = [
  {
    title: "CVI establishes eligibility",
    body: "Cleanverse's Compliant Verified Identity determines whether a wallet may use the protocol at all — a gate, not a score.",
  },
  {
    title: "BitScore evaluates protocol behavior",
    body: "Once eligible, BitV's own on-chain BitScore (0–100) reflects a wallet's on-chain behavior within BitV and adjusts lending parameters within limits the risk manager sets. It is separate from CVI and never overrides it.",
  },
  {
    title: "Asset and RWA infrastructure define collateral risk",
    body: "Standard pool assets and registered real-world assets each carry their own LTV, liquidation threshold, and cap — collateral risk is priced per asset, not assumed uniform.",
  },
  {
    title: "Lending determines borrowing capacity",
    body: "The lending engine combines pool risk parameters, BitScore-adjusted LTV, and collateral value to compute how much a wallet can actually borrow.",
  },
  {
    title: "Vaults provide controlled yield strategies",
    body: "Compliance-gated ERC-4626 vaults route deposits through pluggable, permissioned strategies with caps, pause controls, and emergency withdrawal.",
  },
];

export function Solution() {
  return (
    <section className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            BitV&apos;s answer
          </h2>
          <p className="mt-4 text-muted-foreground">
            Identity, compliance, risk, and capital are handled as distinct, ordered layers —
            never collapsed into one opaque check.
          </p>
        </Reveal>

        <Reveal delay={0.06}>
          <div className="mx-auto mt-10 flex max-w-md items-center justify-between">
            {CHAIN.map((step, i) => (
              <div key={step} className="flex items-center">
                <span className="font-heading text-sm font-medium text-foreground">{step}</span>
                {i < CHAIN.length - 1 && (
                  <span className="mx-3 text-accent" aria-hidden>
                    →
                  </span>
                )}
              </div>
            ))}
          </div>
        </Reveal>

        <div className="mt-14 flex flex-col gap-4">
          {LAYERS.map((layer, i) => (
            <Reveal key={layer.title} delay={i * 0.05}>
              <div className="rounded-lg border border-border p-5">
                <h3 className="font-heading text-sm font-semibold">{layer.title}</h3>
                <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">{layer.body}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
