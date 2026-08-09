import Link from "next/link";
import { siteConfig } from "@/config/site";

export function LandingFooter() {
  return (
    <footer className="border-t border-border px-6 py-10">
      <div className="mx-auto flex max-w-6xl flex-col items-center gap-4 text-center sm:flex-row sm:items-start sm:justify-between sm:text-left">
        <div>
          <p className="font-heading text-base font-semibold">{siteConfig.name}</p>
          <p className="mt-1 text-sm text-muted-foreground">{siteConfig.tagline}</p>
        </div>

        <div className="flex flex-col items-center gap-2 text-sm sm:items-end">
          <div className="flex gap-6">
            <Link href="/dashboard" className="text-muted-foreground hover:text-foreground">
              Dashboard
            </Link>
            <a
              href="https://github.com/tweetbysobur/BitV"
              target="_blank"
              rel="noreferrer noopener"
              className="text-muted-foreground hover:text-foreground"
            >
              GitHub
            </a>
          </div>
          <p className="text-xs text-muted-foreground">Network: {siteConfig.network}</p>
          <p className="max-w-xs text-xs text-muted-foreground">
            Testnet only. Contracts, assets, and balances shown are for testing and carry no real value.
          </p>
        </div>
      </div>
    </footer>
  );
}
