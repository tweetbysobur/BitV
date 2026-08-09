import type { Metadata } from "next";
import { MotionConfig } from "framer-motion";
import { LandingNav } from "@/components/landing/LandingNav";
import { LandingFooter } from "@/components/landing/LandingFooter";
import { Reveal } from "@/components/landing/Reveal";
import { FinalCTA } from "@/components/landing/FinalCTA";

export const metadata: Metadata = {
  title: "How It Works | BitV",
  description: "The complete BitV user journey — lending, RWA collateral, and yield vaults.",
};

function Timeline({ steps }: { steps: { title: string; body: string }[] }) {
  return (
    <div className="flex flex-col">
      {steps.map((step, i) => (
        <Reveal key={step.title} delay={i * 0.05}>
          <div className="flex gap-5 border-l border-border py-5 pl-6 first:pt-0 last:border-l-0 last:pb-0">
            <span className="font-heading text-sm font-semibold text-accent">
              {String(i + 1).padStart(2, "0")}
            </span>
            <div>
              <h3 className="font-heading text-base font-semibold">{step.title}</h3>
              <p className="mt-1 text-sm leading-relaxed text-muted-foreground">{step.body}</p>
            </div>
          </div>
        </Reveal>
      ))}
    </div>
  );
}

const MAIN_FLOW = [
  { title: "Connect wallet", body: "Connect via RainbowKit/WalletConnect on Monad Testnet." },
  { title: "Verify identity", body: "Cleanverse checks your wallet's CVI eligibility before any protected action is available." },
  { title: "Supply assets", body: "Deposit a supported asset into its pool to start earning interest." },
  { title: "Build collateral", body: "Deposit an asset as collateral through the lending engine." },
  { title: "Borrow", body: "Borrow against your collateral up to your pool- and BitScore-adjusted LTV." },
  { title: "Manage risk", body: "Track health factor, liquidation threshold, and borrowing capacity on the Risk page." },
  { title: "Repay", body: "Repay part or all of your debt at any time." },
  { title: "Withdraw", body: "Withdraw supplied or collateral balances once your position allows it." },
];

const RWA_FLOW = [
  { title: "Register asset", body: "An RWA asset is registered in the RWA Collateral Registry with its own risk parameters." },
  { title: "Verify eligibility", body: "The registry checks eligibility, oracle freshness, and status before allowing new activity." },
  { title: "Apply risk parameters", body: "LTV, liquidation threshold, and collateral cap apply specifically to that asset." },
  { title: "Use as collateral", body: "The asset can be deposited as collateral through the same lending engine as any pool asset." },
  { title: "Monitor health", body: "Frozen or delisted status is reflected immediately in eligibility for new activity." },
];

const VAULT_FLOW = [
  { title: "Connect", body: "Connect a CVI-eligible wallet." },
  { title: "Deposit", body: "Deposit the vault's underlying asset, subject to the vault's deposit cap and pause state." },
  { title: "Receive vault position", body: "Your deposit is represented as ERC-4626 vault shares." },
  { title: "Monitor strategy", body: "Track vault performance and strategy allocation from the Vaults page." },
  { title: "Withdraw", body: "Withdraw your share of the vault's assets, or use emergency withdrawal if enabled." },
];

export default function HowItWorksPage() {
  return (
    <MotionConfig reducedMotion="user">
      <main className="min-h-screen">
        <LandingNav />

        <section className="px-6 pb-16 pt-20 sm:pt-28">
          <Reveal className="mx-auto max-w-3xl text-center">
            <p className="mb-4 text-xs font-medium uppercase tracking-widest text-accent">
              User journey
            </p>
            <h1 className="font-heading text-4xl font-semibold tracking-tight sm:text-5xl">
              How BitV works
            </h1>
            <p className="mx-auto mt-4 max-w-2xl text-muted-foreground">
              The complete path from connecting a wallet to managing a position — for lending,
              RWA collateral, and yield vaults.
            </p>
          </Reveal>
        </section>

        <section className="border-t border-border px-6 py-20">
          <div className="mx-auto max-w-2xl">
            <Reveal>
              <h2 className="font-heading text-2xl font-semibold tracking-tight">Lending</h2>
            </Reveal>
            <div className="mt-10">
              <Timeline steps={MAIN_FLOW} />
            </div>
          </div>
        </section>

        <section className="border-t border-border px-6 py-20">
          <div className="mx-auto max-w-2xl">
            <Reveal>
              <h2 className="font-heading text-2xl font-semibold tracking-tight">RWA collateral</h2>
            </Reveal>
            <div className="mt-10">
              <Timeline steps={RWA_FLOW} />
            </div>
          </div>
        </section>

        <section className="border-t border-border px-6 py-20">
          <div className="mx-auto max-w-2xl">
            <Reveal>
              <h2 className="font-heading text-2xl font-semibold tracking-tight">Yield vaults</h2>
            </Reveal>
            <div className="mt-10">
              <Timeline steps={VAULT_FLOW} />
            </div>
          </div>
        </section>

        <FinalCTA />
        <LandingFooter />
      </main>
    </MotionConfig>
  );
}
