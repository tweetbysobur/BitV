import { Building2 } from "lucide-react";
import { Reveal } from "./Reveal";

const CONTROLS = [
  "Asset registration",
  "Oracle availability",
  "LTV limits",
  "Liquidation thresholds",
  "Asset status",
  "Eligibility controls",
];

export function RWASection() {
  return (
    <section id="rwa" className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="text-center">
          <Building2 className="mx-auto text-accent" size={24} />
          <h2 className="mt-4 font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            RWA collateral
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-muted-foreground">
            BitV allows registered real-world assets to participate in collateralized lending,
            subject to the same discipline as any pool asset — priced and bounded per asset,
            layered on top of the core lending engine rather than replacing it.
          </p>
        </Reveal>

        <Reveal delay={0.08}>
          <div className="mt-12 grid grid-cols-2 gap-3 sm:grid-cols-3">
            {CONTROLS.map((control) => (
              <div
                key={control}
                className="rounded-md border border-border px-4 py-3 text-center text-sm text-foreground"
              >
                {control}
              </div>
            ))}
          </div>
        </Reveal>

        <Reveal delay={0.14}>
          <div className="mt-8 rounded-lg border border-border bg-muted/50 p-5">
            <p className="text-sm leading-relaxed text-muted-foreground">
              RWA infrastructure is distinct from CVA (Cleanverse Verified Asset) status. An asset
              being registered for RWA collateral does not by itself mean it is CVA-recognized —
              that is a separate, explicitly checked attestation surfaced honestly in the protocol.
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
