import { siteConfig } from "@/config/site";
import { Reveal } from "./Reveal";

const FACTS = [
  {
    title: "Network",
    body: `Deployed on ${siteConfig.network} (chain ID 10143). No mainnet deployment exists yet.`,
  },
  {
    title: "Compliance",
    body: "Cleanverse sandbox integration — CVI eligibility checks and CVA lookups run against real sandbox endpoints, not mocked responses.",
  },
  {
    title: "Contracts",
    body: "Core lending, risk, RWA registry, and vault contracts are deployed and independently verified on-chain via a dedicated validation script.",
  },
  {
    title: "Open source",
    body: "Solidity contracts and the frontend are both in this repository — architecture and behavior are auditable directly from source.",
  },
];

export function ProtocolStatus() {
  return (
    <section className="border-t border-border px-6 py-20">
      <div className="mx-auto max-w-4xl">
        <Reveal className="text-center">
          <h2 className="font-heading text-3xl font-semibold tracking-tight sm:text-4xl">
            Real protocol status
          </h2>
          <p className="mt-4 text-muted-foreground">
            No projected numbers. These are the current, verifiable facts about the deployment.
          </p>
        </Reveal>

        <div className="mt-12 grid grid-cols-1 gap-4 sm:grid-cols-2">
          {FACTS.map((fact, i) => (
            <Reveal key={fact.title} delay={i * 0.06}>
              <div className="h-full rounded-lg border border-border p-5">
                <p className="font-heading text-sm font-semibold text-accent">{fact.title}</p>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{fact.body}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
