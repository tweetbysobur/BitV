import { ShieldCheck, FileCheck2 } from "lucide-react";
import { Reveal } from "./Reveal";

export function CVICVA() {
  return (
    <section id="cvi" className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            CVI and CVA
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-muted-foreground">
            Two distinct Cleanverse primitives BitV integrates — never merged, never presented as
            the same thing.
          </p>
        </Reveal>

        <div className="mt-12 grid grid-cols-1 gap-6 sm:grid-cols-2">
          <Reveal>
            <div id="cvi-card" className="h-full rounded-lg border border-border p-6">
              <ShieldCheck className="text-accent" size={22} />
              <h3 className="mt-4 font-heading text-base font-semibold">
                CVI — Compliant Verified Identity
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                Wallet-level eligibility. Cleanverse&apos;s validator is checked on-chain before any
                protected BitV action executes — the sole gate for whether a wallet may use the
                protocol at all.
              </p>
            </div>
          </Reveal>

          <Reveal delay={0.06}>
            <div id="cva" className="h-full rounded-lg border border-border p-6">
              <FileCheck2 className="text-accent" size={22} />
              <h3 className="mt-4 font-heading text-base font-semibold">
                CVA — Cleanverse Verified Asset
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                Asset-level attestation, tracked separately by BitV&apos;s CVA adapter. An asset being
                usable as collateral does not by itself mean it is CVA-recognized — that status is
                checked and surfaced independently, never assumed.
              </p>
            </div>
          </Reveal>
        </div>

        <Reveal delay={0.12}>
          <div className="mt-8 rounded-lg border border-border bg-muted/50 p-5">
            <p className="text-sm leading-relaxed text-muted-foreground">
              BitV&apos;s current deployment uses Cleanverse&apos;s sandbox environment on Monad Testnet.
              This is not a production Cleanverse registration and not a claim of Cleanverse
              approval or certification of BitV.
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
