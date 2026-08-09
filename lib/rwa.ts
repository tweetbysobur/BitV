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

/** Explains *why* `isEligibleForNewActivity` is false, mirroring
 * BitVRWACollateralRegistry.isEligibleForNewActivity's exact check
 * order (status -> staleness -> zero price) so the UI never just shows
 * a bare "not eligible" with no actionable reason. `nowSeconds` is the
 * caller's local clock, not the chain's block.timestamp — this is an
 * approximation for display only, never used to gate a transaction
 * (the contract is always the actual source of truth for eligibility). */
export function describeIneligibilityReason(params: {
  status: RWAAssetStatus;
  lastPriceVerifiedTimestamp: number;
  maxOracleStalenessSeconds: number;
  oraclePrice: bigint | undefined;
  nowSeconds: number;
}): string | undefined {
  const { status, lastPriceVerifiedTimestamp, maxOracleStalenessSeconds, oraclePrice, nowSeconds } = params;
  if (status === "Frozen") return "Asset is Frozen — new deposits and borrowing against it are paused.";
  if (status === "Delisted") return "Asset is Delisted — permanently closed to new deposits and borrowing.";
  if (status === "Unregistered") return "Asset is not registered as RWA collateral.";
  if (lastPriceVerifiedTimestamp === 0) {
    return "Oracle price has never been attested fresh for this asset (markPriceFresh not yet called).";
  }
  if (nowSeconds - lastPriceVerifiedTimestamp > maxOracleStalenessSeconds) {
    return "Oracle price attestation is stale — needs a fresh markPriceFresh call before new activity is allowed.";
  }
  if (oraclePrice === 0n) {
    return "Oracle is currently reporting a zero price — treated as invalid, not eligible.";
  }
  return undefined;
}
