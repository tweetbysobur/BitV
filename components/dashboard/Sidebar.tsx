"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

const NAV_ITEMS = [
  { href: "/dashboard/overview", label: "Overview" },
  { href: "/dashboard/lending", label: "Lending" },
  { href: "/dashboard/vaults", label: "Vaults" },
  { href: "/dashboard/rwa", label: "RWA" },
  { href: "/dashboard/pools", label: "Pools" },
  { href: "/dashboard/risk", label: "Risk" },
  { href: "/dashboard/activity", label: "Activity" },
  { href: "/dashboard/settings", label: "Settings" },
] as const;

function NavLinks({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  return (
    <nav aria-label="Dashboard" className="flex flex-col gap-1">
      {NAV_ITEMS.map((item) => {
        const active = pathname === item.href;
        return (
          <Link
            key={item.href}
            href={item.href}
            onClick={onNavigate}
            aria-current={active ? "page" : undefined}
            className={cn(
              "rounded-md px-3 py-2 text-sm font-medium transition-colors",
              active
                ? "bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-muted hover:text-foreground",
            )}
          >
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}

/** Desktop sidebar — always visible at `lg` and above. See Topbar.tsx
 * for the mobile collapsible equivalent. */
export function Sidebar() {
  return (
    <aside className="hidden w-56 shrink-0 border-r border-border p-4 lg:flex lg:flex-col lg:gap-6">
      <Link href="/dashboard/overview" className="font-heading text-lg font-semibold">
        BitV
      </Link>
      <NavLinks />
    </aside>
  );
}

export { NavLinks };
