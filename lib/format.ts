import { formatUnits } from "viem";

/** Standard placeholder for a value that genuinely has no data source
 * connected yet (no wallet, no configured address) — distinct from
 * "unavailable due to a read error," which callers should render with
 * lib/data-state.ts's `error` state and its own message instead. */
export const NOT_CONNECTED = "Not connected";

/** Standard placeholder for a value BitV could theoretically read but
 * currently cannot (missing address, failed call, contract not
 * configured) — never substitute a zero. */
export const UNAVAILABLE = "Unavailable";

/** Formats a raw on-chain token amount for display. Returns
 * `UNAVAILABLE` for `undefined`/`null` rather than `"0"` — callers must
 * never pass a fabricated `0n` to make this render a number. */
export function formatTokenAmount(
  raw: bigint | undefined,
  decimals: number,
  options?: { maxFractionDigits?: number },
): string {
  if (raw === undefined) return UNAVAILABLE;
  const formatted = formatUnits(raw, decimals);
  const maxFractionDigits = options?.maxFractionDigits ?? 4;
  const [whole, fraction] = formatted.split(".");
  if (!fraction || maxFractionDigits <= 0) return whole ?? "0";
  return `${whole}.${fraction.slice(0, maxFractionDigits)}`;
}

/** Basis points (0-10000) -> percentage string, e.g. 7000 -> "70.00%". */
export function formatBps(bps: number | undefined): string {
  if (bps === undefined) return UNAVAILABLE;
  return `${(bps / 100).toFixed(2)}%`;
}

/** Ray (1e27-scaled) value -> percentage string, e.g. for utilization. */
const RAY = 10n ** 27n;
export function formatRayAsPercent(ray: bigint | undefined): string {
  if (ray === undefined) return UNAVAILABLE;
  const pct = (ray * 10000n) / RAY;
  return `${(Number(pct) / 100).toFixed(2)}%`;
}
