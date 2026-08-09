import { Reveal } from "./Reveal";

const STEPS = [
  {
    step: "01",
    title: "CVI eligibility",
    body: "Cleanverse checks the connecting wallet's CVI status. Ineligible wallets are blocked from protocol actions at the contract level.",
  },
  {
    step: "02",
    title: "Protocol risk assessment",
    body: "For eligible wallets, BitScore supplies a 0–100 risk signal that adjusts the wallet's effective borrowing parameters within the pool's configured limits.",
  },
  {
    step: "03",
    title: "Collateral / lending",
    body: "The wallet supplies collateral — a standard pool asset, or an RWA asset registered in the RWA Collateral Registry — and can borrow against it up to its LTV.",
  },
  {
    step: "04",
    title: "Risk controls",
    body: "Liquidation thresholds, liquidation bonuses, and supply/borrow caps are enforced continuously by the pool and lending contracts, not just at origination.",
  },
  {
    step: "05",
    title: "On-chain execution",
    body: "Every supply, borrow, repay, withdraw, and liquidation call executes directly against BitV's contracts on Monad Testnet — no off-chain matching or custody.",
  },
];

export function HowItWorks() {
  return (
    <section id="how-it-works" className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            How BitV works
          </h2>
        </Reveal>

        <div className="mt-14 flex flex-col gap-0">
          {STEPS.map((s, i) => (
            <Reveal key={s.step} delay={i * 0.06}>
              <div className="flex gap-6 border-l border-border py-6 pl-6 first:pt-0 last:pb-0">
                <span className="font-heading text-sm font-semibold text-accent">{s.step}</span>
                <div>
                  <h3 className="font-heading text-base font-semibold">{s.title}</h3>
                  <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">{s.body}</p>
                </div>
              </div>
            </Reveal>
          ))}
        </div>

        <Reveal delay={0.1}>
          <div className="mt-8 rounded-lg border border-border bg-muted/50 p-5">
            <p className="text-sm leading-relaxed text-muted-foreground">
              <span className="font-medium text-foreground">For RWA users:</span> registering an
              asset in the RWA Collateral Registry adds an additional eligibility and risk layer —
              its own LTV, liquidation threshold, and cap — on top of the same lending engine used
              by standard pool assets. It does not replace or bypass the core lending logic.
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
