"use client";

import Link from "next/link";
import { motion } from "framer-motion";
import { ArrowRight, Fingerprint, ShieldCheck, Gauge, Coins } from "lucide-react";
import { siteConfig } from "@/config/site";
import { buttonVariants } from "@/components/ui/button";

const FLOW = [
  { label: "Identity", icon: Fingerprint },
  { label: "Trust", icon: ShieldCheck },
  { label: "Risk", icon: Gauge },
  { label: "Capital", icon: Coins },
];

export function Hero() {
  return (
    <section className="relative overflow-hidden px-6 pb-20 pt-20 sm:pt-28">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[480px] bg-[radial-gradient(ellipse_60%_50%_at_50%_-10%,hsl(var(--accent)/0.12),transparent)]"
      />

      <div className="mx-auto flex max-w-4xl flex-col items-center text-center">
        <motion.p
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="mb-6 rounded-full border border-border px-3 py-1 text-xs font-medium uppercase tracking-widest text-accent"
        >
          Identity-native DeFi
        </motion.p>

        <motion.h1
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.05 }}
          className="font-heading text-5xl font-semibold tracking-tight sm:text-6xl"
        >
          {siteConfig.name}
        </motion.h1>

        <motion.p
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.1 }}
          className="mt-3 text-xl font-medium text-foreground/80 sm:text-2xl"
        >
          {siteConfig.tagline}
        </motion.p>

        <motion.p
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.15 }}
          className="mt-6 max-w-xl text-balance text-base text-muted-foreground sm:text-lg"
        >
          Identity-native DeFi infrastructure for trusted financial markets.
        </motion.p>

        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.2 }}
          className="mt-10 flex flex-col items-center gap-4 sm:flex-row"
        >
          <Link href="/dashboard" className={buttonVariants("primary", "group h-12 px-6 text-sm")}>
            Launch App
            <ArrowRight size={16} className="transition-transform group-hover:translate-x-0.5" />
          </Link>
          <Link href="/product" className={buttonVariants("secondary", "h-12 px-6 text-sm")}>
            Explore Product
          </Link>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.28 }}
          className="mt-16 flex w-full max-w-xl items-center justify-between"
        >
          {FLOW.map((step, i) => (
            <div key={step.label} className="flex items-center">
              <div className="flex flex-col items-center gap-2">
                <div className="flex h-11 w-11 items-center justify-center rounded-full border border-border bg-card">
                  <step.icon size={18} className="text-accent" />
                </div>
                <span className="text-xs text-muted-foreground">{step.label}</span>
              </div>
              {i < FLOW.length - 1 && (
                <div className="mx-2 h-px w-8 bg-border sm:w-14" aria-hidden />
              )}
            </div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
