import { describe, expect, it } from "vitest";
import { getRWAAssetStatusFromIndex, describeRWAStatusForNewActivity, describeIneligibilityReason } from "@/lib/rwa";

describe("RWA status rendering", () => {
  it("maps every on-chain AssetStatus index correctly", () => {
    expect(getRWAAssetStatusFromIndex(0)).toBe("Unregistered");
    expect(getRWAAssetStatusFromIndex(1)).toBe("Active");
    expect(getRWAAssetStatusFromIndex(2)).toBe("Frozen");
    expect(getRWAAssetStatusFromIndex(3)).toBe("Delisted");
  });

  it("rejects an unknown status index", () => {
    expect(() => getRWAAssetStatusFromIndex(4)).toThrow(RangeError);
  });

  it("describes frozen assets as blocking new activity but not existing positions", () => {
    const description = describeRWAStatusForNewActivity("Frozen");
    expect(description).toContain("stopped");
    expect(description).toContain("Repayment, withdrawal, and liquidation remain available");
  });

  it("describes delisted assets identically for existing-position availability", () => {
    const description = describeRWAStatusForNewActivity("Delisted");
    expect(description).toContain("Repayment, withdrawal, and liquidation remain available");
  });
});

describe("RWA ineligibility reason", () => {
  const base = { lastPriceVerifiedTimestamp: 1000, maxOracleStalenessSeconds: 3600, oraclePrice: 1n, nowSeconds: 1500 };

  it("reports Frozen before checking oracle state", () => {
    expect(describeIneligibilityReason({ ...base, status: "Frozen" })).toContain("Frozen");
  });

  it("reports Delisted before checking oracle state", () => {
    expect(describeIneligibilityReason({ ...base, status: "Delisted" })).toContain("Delisted");
  });

  it("reports never-attested price when lastPriceVerifiedTimestamp is 0", () => {
    const reason = describeIneligibilityReason({ ...base, status: "Active", lastPriceVerifiedTimestamp: 0 });
    expect(reason).toContain("never been attested fresh");
  });

  it("reports staleness once the max staleness window has elapsed", () => {
    const reason = describeIneligibilityReason({ ...base, status: "Active", nowSeconds: 1000 + 3600 + 1 });
    expect(reason).toContain("stale");
  });

  it("reports a zero oracle price as invalid", () => {
    const reason = describeIneligibilityReason({ ...base, status: "Active", oraclePrice: 0n });
    expect(reason).toContain("zero price");
  });

  it("returns undefined when every check passes (asset is actually eligible)", () => {
    expect(describeIneligibilityReason({ ...base, status: "Active" })).toBeUndefined();
  });
});
