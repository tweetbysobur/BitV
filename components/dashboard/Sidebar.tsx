"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutGrid,
  Landmark,
  Coins,
  Building2,
  Droplets,
  Gauge,
  Activity as ActivityIcon,
  Settings as SettingsIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { BitVLockup } from "@/components/brand/BitVMark";

const NAV_ITEMS = [
  { href: "/dashboard/overview", label: "Overview", icon: LayoutGrid },
  { href: "/dashboard/lending", label: "Lending", icon: Landmark },
  { href: "/dashboard/vaults", label: "Vaults", icon: Coins },
  { href: "/dashboard/rwa", label: "RWA", icon: Building2 },
  { href: "/dashboard/pools", label: "Pools", icon: Droplets },
  { href: "/dashboard/risk", label: "Risk", icon: Gauge },
  { href: "/dashboard/activity", label: "Activity", icon: ActivityIcon },
  { href: "/dashboard/settings", label: "Settings", icon: SettingsIcon },
] as const;

function NavLinks({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  return (
    <nav aria-label="Dashboard" className="flex flex-col gap-0.5">
      {NAV_ITEMS.map((item) => {
        const active = pathname === item.href;
        return (
          <Link
            key={item.href}
            href={item.href}
            onClick={onNavigate}
            aria-current={active ? "page" : undefined}
            className={cn(
              "flex items-center gap-2.5 rounded-md border-l-2 px-3 py-2 text-sm font-medium transition-colors",
              active
                ? "border-accent bg-muted text-foreground"
                : "border-transparent text-muted-foreground hover:bg-muted hover:text-foreground",
            )}
          >
            <item.icon size={16} className={active ? "text-accent" : "text-muted-foreground"} aria-hidden="true" />
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
    <aside className="hidden w-60 shrink-0 border-r border-border p-4 lg:flex lg:flex-col lg:gap-8">
      <Link href="/" aria-label="BitV home">
        <BitVLockup />
      </Link>
      <NavLinks />
    </aside>
  );
}

export { NavLinks };
