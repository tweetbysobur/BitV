import Link from "next/link";
import { Landmark, Building2, Coins, Droplets, Gauge } from "lucide-react";
import { Reveal } from "./Reveal";

const CAPABILITIES = [
  { icon: Landmark, title: "Lending", href: "/product#lending" },
  { icon: Building2, title: "RWA", href: "/product#rwa" },
  { icon: Coins, title: "Yield Vaults", href: "/product#vaults" },
  { icon: Droplets, title: "Liquidity", href: "/product#liquidity" },
  { icon: Gauge, title: "Risk Intelligence", href: "/product#risk" },
];

export function CoreCapabilities() {
  return (
    <section id="protocol" className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-5xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Core capabilities
          </h2>
        </Reveal>

        <div className="mt-12 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
          {CAPABILITIES.map((cap, i) => (
            <Reveal key={cap.title} delay={(i % 5) * 0.05}>
              <Link
                href={cap.href}
                className="group flex h-full flex-col items-center gap-3 rounded-lg border border-border p-5 text-center transition-colors hover:border-accent/40"
              >
                <cap.icon className="text-accent" size={22} />
                <span className="font-heading text-sm font-medium">{cap.title}</span>
              </Link>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
