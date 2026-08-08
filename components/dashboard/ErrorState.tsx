export function ErrorState({ message }: { message: string }) {
  return (
    <div role="alert" className="flex flex-col gap-1 rounded-md border border-destructive/30 bg-destructive/5 p-4 text-sm">
      <p className="font-medium text-destructive">Unable to load this data</p>
      <p className="text-muted-foreground">{message}</p>
    </div>
  );
}

/** For values that simply have no data source connected yet (missing
 * contract address, wallet not connected) — distinct from a genuine
 * read failure, per docs/dashboard-implementation.md's loading/error
 * model. */
export function UnavailableState({ reason }: { reason: string }) {
  return (
    <div className="flex flex-col gap-1 rounded-md border border-border bg-muted/40 p-4 text-sm">
      <p className="font-medium text-muted-foreground">Unavailable</p>
      <p className="text-muted-foreground">{reason}</p>
    </div>
  );
}
