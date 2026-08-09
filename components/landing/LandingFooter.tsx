import Link from "next/link";
import { siteConfig } from "@/config/site";
import { BitVLockup } from "@/components/brand/BitVMark";

const COLUMNS: { heading: string; links: { label: string; href: string; external?: boolean }[] }[] = [
  {
    heading: "Product",
    links: [
      { label: "Overview", href: "/dashboard/overview" },
      { label: "Lending", href: "/dashboard/lending" },
      { label: "Vaults", href: "/dashboard/vaults" },
      { label: "RWA", href: "/dashboard/rwa" },
      { label: "Pools", href: "/dashboard/pools" },
      { label: "Risk", href: "/dashboard/risk" },
    ],
  },
  {
    heading: "Resources",
    links: [
      { label: "How It Works", href: "/how-it-works" },
      {
        label: "Documentation",
        href: "https://github.com/tweetbysobur/BitV/tree/main/docs",
        external: true,
      },
      { label: "GitHub", href: "https://github.com/tweetbysobur/BitV", external: true },
    ],
  },
  {
    heading: "Protocol",
    links: [
      { label: "BitScore", href: "/product#risk" },
      { label: "CVI", href: "/product#cvi" },
      { label: "CVA", href: "/product#cva" },
      { label: "Security", href: "/product#security" },
      { label: "Monad", href: "/product#monad" },
    ],
  },
];

export function LandingFooter() {
  const year = new Date().getFullYear();

  return (
    <footer className="border-t border-border px-6 py-16">
      <div className="mx-auto max-w-6xl">
        <div className="grid grid-cols-1 gap-10 sm:grid-cols-2 lg:grid-cols-[1.4fr_1fr_1fr_1fr]">
          <div>
            <BitVLockup />
            <p className="mt-3 max-w-xs text-sm text-muted-foreground">{siteConfig.tagline}</p>
            <p className="mt-3 max-w-xs text-sm text-muted-foreground">
              Identity-native DeFi infrastructure — verified access, risk-adjusted lending, RWA
              collateral, and yield vaults.
            </p>
          </div>

          {COLUMNS.map((col) => (
            <div key={col.heading}>
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                {col.heading}
              </p>
              <ul className="mt-4 flex flex-col gap-2.5 text-sm">
                {col.links.map((link) => (
                  <li key={link.label}>
                    {link.external ? (
                      <a
                        href={link.href}
                        target="_blank"
                        rel="noreferrer noopener"
                        className="text-muted-foreground hover:text-foreground"
                      >
                        {link.label}
                      </a>
                    ) : (
                      <Link href={link.href} className="text-muted-foreground hover:text-foreground">
                        {link.label}
                      </Link>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-12 flex flex-col items-center justify-between gap-4 border-t border-border pt-6 text-xs text-muted-foreground sm:flex-row">
          <p>© {year} BitV. All rights reserved.</p>
          <div className="flex items-center gap-2">
            <span className="h-1.5 w-1.5 rounded-full bg-success" aria-hidden="true" />
            <span>Built on {siteConfig.network}</span>
          </div>
        </div>

        <p className="mt-4 max-w-2xl text-xs text-muted-foreground">
          BitV is deployed on {siteConfig.network} only, with a Cleanverse sandbox compliance
          integration. Contracts, assets, and balances shown are for testing and carry no real
          value. Nothing here is financial advice, and use of the protocol is not guaranteed
          approval to borrow.
        </p>
      </div>
    </footer>
  );
}
