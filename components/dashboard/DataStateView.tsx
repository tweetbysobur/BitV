import type { ReactNode } from "react";
import type { DataState } from "@/lib/data-state";
import { LoadingState } from "./LoadingState";
import { EmptyState } from "./EmptyState";
import { ErrorState, UnavailableState } from "./ErrorState";

/** Renders the correct loading/loaded/empty/unavailable/error UI for a
 * `DataState<T>` — the single place every contract-backed dashboard
 * section routes through, so no section can silently render as if data
 * loaded successfully when it didn't. */
export function DataStateView<T>({
  state,
  loadingLabel,
  emptyTitle,
  emptyDescription,
  children,
}: {
  state: DataState<T>;
  loadingLabel?: string;
  emptyTitle?: string;
  emptyDescription?: string;
  children: (data: T) => ReactNode;
}) {
  switch (state.status) {
    case "loading":
      return <LoadingState label={loadingLabel} />;
    case "unavailable":
      return <UnavailableState reason={state.reason} />;
    case "error":
      return <ErrorState message={state.message} />;
    case "empty":
      return <EmptyState title={emptyTitle ?? "No data"} description={emptyDescription} />;
    case "loaded":
      return <>{children(state.data)}</>;
  }
}
