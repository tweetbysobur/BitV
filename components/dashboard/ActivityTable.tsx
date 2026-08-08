import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from "@/components/ui/table";
import { DataStateView } from "./DataStateView";
import { useActivity } from "@/hooks/useActivity";

export function ActivityTable() {
  const state = useActivity();

  return (
    <DataStateView
      state={state}
      loadingLabel="Loading activity"
      emptyTitle="No activity"
      emptyDescription="This wallet has no recorded protocol activity."
    >
      {(entries) => (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Category</TableHead>
              <TableHead>Summary</TableHead>
              <TableHead>Transaction</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {entries.map((entry) => (
              <TableRow key={entry.txHash}>
                <TableCell>{entry.category}</TableCell>
                <TableCell>{entry.summary}</TableCell>
                <TableCell className="font-mono text-xs">{entry.txHash}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </DataStateView>
  );
}
