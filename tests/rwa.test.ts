import { describe, expect, it } from "vitest";
import { getRWAAssetStatusFromIndex, describeRWAStatusForNewActivity } from "@/lib/rwa";

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
