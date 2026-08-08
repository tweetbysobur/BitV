import { CollateralTable } from "./CollateralTable";
import type { AssetPositionRow } from "@/lib/positions";

/** Multi-asset debt table — thin wrapper over CollateralTable's shared
 * rendering logic (formatting/empty-state behavior is identical for
 * collateral and debt rows). */
export function DebtTable({ rows }: { rows: AssetPositionRow[] }) {
  return <CollateralTable rows={rows} title="Debt" />;
}
