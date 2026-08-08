import type { ReactNode } from "react";
import { Sidebar } from "./Sidebar";
import { Topbar } from "./Topbar";

/** Desktop: sidebar navigation + top wallet/status bar + main workspace.
 * Mobile: collapsible nav (via Topbar) + stacked sections (each page's
 * own layout decides its stacking). */
export function DashboardShell({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar />
        <main className="flex-1 p-4 lg:p-6">{children}</main>
      </div>
    </div>
  );
}
