import Link from "next/link";
import { siteConfig } from "@/config/site";

const LINKS = [
  { label: "Protocol", href: "#protocol" },
  { label: "Risk", href: "#risk" },
  { label: "RWA", href: "#rwa" },
  { label: "Vaults", href: "#vaults" },
  {
    label: "Docs",
    href: "https://github.com/tweetbysobur/BitV/tree/main/docs",
    external: true,
  },
];

export function LandingFooter() {
  return (
    <footer className="border-t border-border px-6 py-10">
      <div className="mx-auto flex max-w-6xl flex-col items-center gap-6 text-center sm:flex-row sm:items-start sm:justify-between sm:text-left">
        <div>
          <p className="font-heading text-base font-semibold">{siteConfig.name}</p>
          <p className="mt-1 text-sm text-muted-foreground">{siteConfig.tagline}</p>
        </div>

        <div className="flex flex-col items-center gap-3 text-sm sm:items-end">
          <div className="flex flex-wrap justify-center gap-x-6 gap-y-2 sm:justify-end">
            {LINKS.map((link) =>
              link.external ? (
                <a
                  key={link.label}
                  href={link.href}
                  target="_blank"
                  rel="noreferrer noopener"
                  className="text-muted-foreground hover:text-foreground"
                >
                  {link.label}
                </a>
              ) : (
                <a key={link.label} href={link.href} className="text-muted-foreground hover:text-foreground">
                  {link.label}
                </a>
              )
            )}
            <Link href="/dashboard" className="text-muted-foreground hover:text-foreground">
              Dashboard
            </Link>
          </div>
          <p className="text-xs text-muted-foreground">Network: {siteConfig.network}</p>
          <p className="max-w-sm text-xs text-muted-foreground">
            BitV is deployed on {siteConfig.network} only, with a Cleanverse sandbox compliance
            integration. Contracts, assets, and balances shown are for testing and carry no real
            value. Nothing here is financial advice, and use of the protocol is not guaranteed
            approval to borrow.
          </p>
        </div>
      </div>
    </footer>
  );
}
