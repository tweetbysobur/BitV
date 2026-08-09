import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Reveal } from "./Reveal";

export function FinalCTA() {
  return (
    <section className="border-t border-border px-6 py-24">
      <Reveal className="mx-auto flex max-w-2xl flex-col items-center text-center">
        <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
          The next generation of DeFi needs better trust infrastructure.
        </h2>
        <p className="mt-3 text-xl font-medium text-foreground/80">Build with BitV.</p>
        <Link
          href="/dashboard"
          className="group mt-8 inline-flex items-center gap-2 rounded-md bg-primary px-6 py-3 text-sm font-medium text-primary-foreground transition-opacity hover:opacity-90"
        >
          Launch App
          <ArrowRight size={16} className="transition-transform group-hover:translate-x-0.5" />
        </Link>
      </Reveal>
    </section>
  );
}
