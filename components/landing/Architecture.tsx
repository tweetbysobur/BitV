import { Reveal } from "./Reveal";

const LAYERS = [
  { label: "Cleanverse", detail: "External identity & compliance provider" },
  { label: "CVI", detail: "Compliant Verified Identity — eligibility check" },
  { label: "BitV Compliance Layer", detail: "On-chain complianceVerify() gate" },
  { label: "BitScore", detail: "0–100 protocol risk signal" },
  { label: "Liquidity", detail: "Asset-specific pools, risk parameters" },
  { label: "Lending", detail: "Collateral, borrowing, liquidation" },
  { label: "Vaults / RWA", detail: "Yield strategies & real-world asset collateral" },
];

export function Architecture() {
  return (
    <section className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-2xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Product architecture
          </h2>
        </Reveal>

        <div className="mt-14 flex flex-col items-center">
          {LAYERS.map((layer, i) => (
            <Reveal key={layer.label} delay={i * 0.05} className="w-full">
              <div className="flex w-full items-center gap-4 rounded-lg border border-border bg-card px-5 py-4">
                <span className="font-heading text-xs font-semibold text-accent">
                  {String(i + 1).padStart(2, "0")}
                </span>
                <div>
                  <p className="font-heading text-sm font-semibold">{layer.label}</p>
                  <p className="text-xs text-muted-foreground">{layer.detail}</p>
                </div>
              </div>
              {i < LAYERS.length - 1 && (
                <div className="mx-auto my-1 h-6 w-px bg-border" aria-hidden />
              )}
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
