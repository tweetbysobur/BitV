import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@/components/ui/table";
import { EmptyState } from "./EmptyState";
import { formatPositionRows, hasAnyNonzeroPosition, type AssetPositionRow } from "@/lib/positions";

/** Renders a multi-asset collateral (or, via the same component, debt)
 * table — never assumes a single asset. Pass `title="Debt"` for the
 * debt case; the underlying rendering logic is identical. */
export function CollateralTable({
  rows,
  title = "Collateral",
}: {
  rows: AssetPositionRow[];
  title?: string;
}) {
  if (rows.length === 0) {
    return <EmptyState title={`No ${title.toLowerCase()} assets configured`} />;
  }
  if (!hasAnyNonzeroPosition(rows)) {
    return <EmptyState title={`No ${title.toLowerCase()}`} description="This wallet has no position in any known asset." />;
  }

  const formatted = formatPositionRows(rows);

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Asset</TableHead>
          <TableHead>{title}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {formatted.map((row) => (
          <TableRow key={row.assetAddress}>
            <TableCell>{row.symbol}</TableCell>
            <TableCell className="tabular-nums">{row.amount}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
