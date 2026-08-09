import { Reveal } from "./Reveal";

export function CompliantDeFi() {
  return (
    <section id="compliance" className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-3xl">
        <Reveal>
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Built for compliant DeFi
          </h2>
          <p className="mt-4 text-muted-foreground">
            BitV uses Cleanverse CVI as its eligibility layer — every wallet interacting with the
            protocol is checked against Cleanverse&apos;s compliance validator before any lending,
            vault, or collateral action is allowed to execute.
          </p>
        </Reveal>

        <Reveal delay={0.08}>
          <div className="mt-8 rounded-lg border border-border bg-muted/50 p-5">
            <p className="text-sm font-medium text-foreground">Current status</p>
            <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
              BitV&apos;s current deployment is a Cleanverse <span className="font-medium text-foreground">sandbox</span> integration
              on Monad Testnet. This confirms the integration path works end to end, on-chain —
              it is not a production Cleanverse registration or approval, and it does not
              constitute an official endorsement of BitV or of Monad by Cleanverse.
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
