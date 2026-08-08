import { describe, expect, it } from "vitest";
import { getStrategyLabel, getPerformanceLabel } from "@/lib/vault";

describe("vault strategy labeling", () => {
  it("labels a confirmed test strategy clearly as non-production", () => {
    expect(getStrategyLabel(true)).toContain("non-production");
    expect(getPerformanceLabel(true)).toContain("does not reflect real yield");
  });

  it("labels a confirmed production strategy without the test disclaimer", () => {
    expect(getStrategyLabel(false)).toBe("Production strategy");
    expect(getPerformanceLabel(false)).not.toContain("non-production");
  });

  it("shows Unavailable when BitV has no confirmed record either way", () => {
    expect(getStrategyLabel(undefined)).toBe("Unavailable");
    expect(getPerformanceLabel(undefined)).toBe("Unavailable");
  });
});
