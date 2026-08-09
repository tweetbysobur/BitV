import { Reveal } from "./Reveal";

const CONTROLS = [
  "Cleanverse compliance boundary — protected actions fail closed when eligibility can't be verified.",
  "Role-based access control — risk, pause, and vault operations are each gated to their own on-chain role.",
  "Reentrancy protection on state-changing pool, lending, and vault functions.",
  "Pause controls for emergency response without touching user funds.",
  "Oracle safeguards — stale or missing price data blocks the actions that depend on it.",
  "Liquidation controls — close factor and liquidation bonus bounded by protocol parameters.",
  "Strategy isolation — vault strategies are swappable and contained, not given unbounded vault access.",
  "Fail-safe integration boundaries with external dependencies like Cleanverse.",
];

export function Security() {
  return (
    <section className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Security and compliance
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-muted-foreground">
            Built with security-first architecture. BitV has not undergone a third-party audit —
            the points below describe the protocol&apos;s current on-chain controls, not a claim of audit status.
          </p>
        </Reveal>

        <Reveal delay={0.08}>
          <ul className="mx-auto mt-12 grid max-w-3xl grid-cols-1 gap-3 sm:grid-cols-2">
            {CONTROLS.map((control) => (
              <li
                key={control}
                className="rounded-md border border-border px-4 py-3 text-sm leading-relaxed text-muted-foreground"
              >
                {control}
              </li>
            ))}
          </ul>
        </Reveal>
      </div>
    </section>
  );
}
