import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Reveal } from "./Reveal";
import { RiskTierBadge } from "@/components/dashboard/RiskTierBadge";
import { buttonVariants } from "@/components/ui/button";

export function ProductPreview() {
  return (
    <section className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-5xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            The BitV dashboard
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-muted-foreground">
            Representative UI — not live user data. Connect a wallet at{" "}
            <span className="font-medium text-foreground">/dashboard</span> to see your own
            position on Monad Testnet.
          </p>
        </Reveal>

        <Reveal delay={0.1}>
          <div className="mt-12 overflow-hidden rounded-xl border border-border bg-card">
            <div className="flex items-center justify-between border-b border-border px-6 py-4">
              <span className="font-heading text-sm font-semibold">Overview</span>
              <RiskTierBadge tier="Established" />
            </div>
            <div className="grid grid-cols-2 gap-px bg-border sm:grid-cols-4">
              {[
                { label: "BitScore", value: "58" },
                { label: "Health factor", value: "1.62" },
                { label: "Collateral", value: "2 assets" },
                { label: "Debt", value: "1 asset" },
              ].map((cell) => (
                <div key={cell.label} className="bg-card p-5">
                  <p className="text-xs text-muted-foreground">{cell.label}</p>
                  <p className="mt-1 font-heading text-lg font-semibold">{cell.value}</p>
                </div>
              ))}
            </div>
            <div className="grid grid-cols-1 gap-px bg-border sm:grid-cols-3">
              {[
                { label: "RWA collateral", value: "1 registered asset" },
                { label: "Vaults", value: "1 vault position" },
                { label: "Activity", value: "Unavailable — no indexer yet" },
              ].map((cell) => (
                <div key={cell.label} className="bg-card p-5">
                  <p className="text-xs text-muted-foreground">{cell.label}</p>
                  <p className="mt-1 text-sm font-medium text-foreground">{cell.value}</p>
                </div>
              ))}
            </div>
          </div>
        </Reveal>

        <Reveal delay={0.16} className="mt-8 flex justify-center">
          <Link href="/dashboard" className={buttonVariants("primary", "group h-11 px-6 text-sm")}>
            Explore the App
            <ArrowRight size={16} className="transition-transform group-hover:translate-x-0.5" />
          </Link>
        </Reveal>
      </div>
    </section>
  );
}
