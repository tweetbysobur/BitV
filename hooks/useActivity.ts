"use client";

import type { DataState } from "@/lib/data-state";

export type ActivityCategory =
  | "Supply"
  | "Withdraw"
  | "Borrow"
  | "Repay"
  | "Liquidation"
  | "VaultDeposit"
  | "VaultWithdrawal"
  | "RWACollateral"
  | "PoolActivity"
  | "BitScoreUpdate";

export interface ActivityEntry {
  category: ActivityCategory;
  txHash: `0x${string}`;
  blockTimestamp: number;
  summary: string;
}

/** No event indexer exists yet for BitV (no subgraph, no log-scanning
 * service) — this hook deliberately always reports `unavailable` rather
 * than fabricating history. Wire this up to a real indexer/log-scan
 * service before displaying anything here; do not backfill with
 * synthetic data in the meantime. */
export function useActivity(): DataState<ActivityEntry[]> {
  return {
    status: "unavailable",
    reason: "Activity indexing is not yet available. BitV does not yet index historical events.",
  };
}
