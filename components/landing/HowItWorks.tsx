import { Reveal } from "./Reveal";

const STEPS = [
  { step: "01", title: "Verify identity", body: "Connect a wallet and establish CVI eligibility through Cleanverse before any protocol action is available." },
  { step: "02", title: "Access trusted markets", body: "Eligible wallets can browse and interact with BitV's pools, RWA collateral, and yield vaults." },
  { step: "03", title: "Build risk history", body: "On-chain activity within BitV shapes your BitScore over time, within the limits the protocol defines." },
  { step: "04", title: "Unlock capital", body: "Borrowing capacity is computed from your collateral, pool risk parameters, and BitScore-adjusted LTV — not guaranteed or automatically approved." },
];

export function HowItWorks() {
  return (
    <section className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            How BitV works
          </h2>
        </Reveal>

        <div className="mt-14 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {STEPS.map((s, i) => (
            <Reveal key={s.step} delay={i * 0.06}>
              <div className="h-full rounded-lg border border-border p-5">
                <span className="font-heading text-sm font-semibold text-accent">{s.step}</span>
                <h3 className="mt-3 font-heading text-base font-semibold">{s.title}</h3>
                <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">{s.body}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
