import { Reveal } from "./Reveal";

const PIECES = ["Monad", "Cleanverse CVI", "Cleanverse CVA", "BitScore"];

export function InfrastructureStrip() {
  return (
    <section className="border-t border-border px-6 py-10">
      <Reveal className="mx-auto max-w-6xl">
        <p className="text-center text-xs uppercase tracking-widest text-muted-foreground">
          Built around verified identity and asset-aware infrastructure
        </p>
        <div className="mt-6 flex flex-wrap items-center justify-center gap-x-10 gap-y-4">
          {PIECES.map((piece) => (
            <span key={piece} className="font-heading text-sm font-medium text-foreground/70">
              {piece}
            </span>
          ))}
        </div>
      </Reveal>
    </section>
  );
}
