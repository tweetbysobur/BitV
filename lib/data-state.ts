/**
 * Shared loading/loaded/empty/unavailable/error model every
 * contract-backed dashboard section uses — per the dashboard's own
 * requirement that no section may silently look loaded/successful when
 * it isn't. See docs/dashboard-implementation.md.
 */
export type DataState<T> =
  | { status: "loading" }
  | { status: "loaded"; data: T }
  | { status: "empty" }
  | { status: "unavailable"; reason: string }
  | { status: "error"; message: string };

export function isLoaded<T>(state: DataState<T>): state is { status: "loaded"; data: T } {
  return state.status === "loaded";
}
