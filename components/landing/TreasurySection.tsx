import { Landmark } from "lucide-react";
import { Reveal } from "./Reveal";

export function TreasurySection() {
  return (
    <section id="treasury" className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-3xl">
        <Reveal className="text-center">
          <Landmark className="mx-auto text-accent" size={24} />
          <h2 className="mt-4 font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Treasury
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-muted-foreground">
            Each pool&apos;s reserve factor routes a share of borrower interest into scaled supply
            credited to the protocol treasury — accounted the same way as any supplier&apos;s
            balance, then claimable by a role-gated administrative action. Vault performance fees
            and liquidation proceeds follow the same treasury path.
          </p>
        </Reveal>
      </div>
    </section>
  );
}
