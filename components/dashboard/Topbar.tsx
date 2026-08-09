"use client";

import { useState } from "react";
import Link from "next/link";
import { Menu, X } from "lucide-react";
import { WalletStatus } from "./WalletStatus";
import { NavLinks } from "./Sidebar";
import { BitVMark } from "@/components/brand/BitVMark";

/** Top bar for every screen size: wallet status always visible;
 * mobile-only collapsible nav trigger (the sidebar itself is hidden
 * below `lg`, see Sidebar.tsx). */
export function Topbar() {
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  return (
    <header className="relative flex items-center justify-between border-b border-border px-4 py-3 lg:px-6">
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={() => setMobileNavOpen((open) => !open)}
          aria-expanded={mobileNavOpen}
          aria-controls="mobile-dashboard-nav"
          aria-label={mobileNavOpen ? "Close navigation menu" : "Open navigation menu"}
          className="rounded-md p-2 text-foreground hover:bg-muted lg:hidden"
        >
          {mobileNavOpen ? <X className="h-5 w-5" aria-hidden="true" /> : <Menu className="h-5 w-5" aria-hidden="true" />}
        </button>
        <Link href="/dashboard/overview" className="flex items-center gap-2 lg:hidden">
          <BitVMark className="h-6 w-6" />
          <span className="font-heading text-base font-semibold">BitV</span>
        </Link>
      </div>
      <WalletStatus />
      {mobileNavOpen ? (
        <div id="mobile-dashboard-nav" className="absolute inset-x-0 top-[57px] z-20 border-b border-border bg-background p-4 lg:hidden">
          <NavLinks onNavigate={() => setMobileNavOpen(false)} />
        </div>
      ) : null}
    </header>
  );
}
