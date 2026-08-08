/**
 * RWA asset status display logic — mirrors
 * BitVRWACollateralRegistry.AssetStatus exactly
 * (contracts/src/core/BitVRWACollateralRegistry.sol).
 */
export type RWAAssetStatus = "Unregistered" | "Active" | "Frozen" | "Delisted";

export const RWA_ASSET_STATUS_BY_INDEX: readonly RWAAssetStatus[] = [
  "Unregistered",
  "Active",
  "Frozen",
  "Delisted",
];

export function getRWAAssetStatusFromIndex(statusIndex: number): RWAAssetStatus {
  const status = RWA_ASSET_STATUS_BY_INDEX[statusIndex];
  if (status === undefined) throw new RangeError(`Unknown RWA asset status index: ${statusIndex}`);
  return status;
}

/** What each status means for NEW deposits/borrowing specifically —
 * matches docs/rwa-market-implementation.md's frozen/delisted table
 * exactly (repayment/withdrawal/liquidation always remain available
 * regardless of status; this only describes new activity). */
export function describeRWAStatusForNewActivity(status: RWAAssetStatus): string {
  switch (status) {
    case "Active":
      return "Eligible for new deposits and counts toward new borrowing capacity (subject to oracle freshness).";
    case "Frozen":
      return "New deposits and new borrowing capacity from this asset are stopped. Repayment, withdrawal, and liquidation remain available.";
    case "Delisted":
      return "Permanently stopped for new deposits and new borrowing capacity. Repayment, withdrawal, and liquidation remain available.";
    case "Unregistered":
      return "Not registered as RWA collateral with BitV.";
  }
}
