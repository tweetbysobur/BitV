import { formatTokenAmount, UNAVAILABLE } from "./format";

/** One row of a multi-asset collateral or debt position — the shape
 * CollateralTable/DebtTable render, built from
 * BitVLendingManager.getCollateralBalance/getCurrentDebt per asset. Never
 * assumes a single asset; callers build one row per known asset address. */
export interface AssetPositionRow {
  assetAddress: string;
  symbol: string | undefined;
  rawAmount: bigint | undefined;
  decimals: number | undefined;
}

export interface FormattedPositionRow {
  assetAddress: string;
  symbol: string;
  amount: string;
}

/** Formats a list of per-asset rows for display, filtering out rows with
 * no data at all (never read) while keeping rows the user actually has
 * a zero on-chain balance for, which is a real, meaningful "0", not a
 * missing-data placeholder. A row whose amount could not be read at all
 * (rawAmount undefined) still renders, showing "Unavailable" rather than
 * being silently dropped — the user should know a read failed, not see
 * their position understated. */
export function formatPositionRows(rows: readonly AssetPositionRow[]): FormattedPositionRow[] {
  return rows.map((row) => ({
    assetAddress: row.assetAddress,
    symbol: row.symbol ?? UNAVAILABLE,
    amount:
      row.decimals === undefined
        ? UNAVAILABLE
        : formatTokenAmount(row.rawAmount, row.decimals),
  }));
}

/** True only when every row has a real, nonzero position — used to
 * decide between the "loaded" and "empty" DataState for a multi-asset
 * table, per lib/data-state.ts. A user with zero collateral in every
 * known asset is a genuine "empty" state, not "unavailable." */
export function hasAnyNonzeroPosition(rows: readonly AssetPositionRow[]): boolean {
  return rows.some((row) => row.rawAmount !== undefined && row.rawAmount > 0n);
}
