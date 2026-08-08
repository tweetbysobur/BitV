import { describe, expect, it } from "vitest";
import { getBitScoreTierFromScore, getBitScoreTierFromIndex, BITSCORE_TIERS } from "@/lib/bitscore";

describe("BitScore tier mapping (0-100 scale)", () => {
  it("maps the starting score (30) to Standard", () => {
    expect(getBitScoreTierFromScore(30).tier).toBe("Standard");
  });

  it("maps every tier boundary correctly", () => {
    expect(getBitScoreTierFromScore(0).tier).toBe("Restricted");
    expect(getBitScoreTierFromScore(24).tier).toBe("Restricted");
    expect(getBitScoreTierFromScore(25).tier).toBe("Standard");
    expect(getBitScoreTierFromScore(49).tier).toBe("Standard");
    expect(getBitScoreTierFromScore(50).tier).toBe("Established");
    expect(getBitScoreTierFromScore(74).tier).toBe("Established");
    expect(getBitScoreTierFromScore(75).tier).toBe("Trusted");
    expect(getBitScoreTierFromScore(100).tier).toBe("Trusted");
  });

  it("rejects scores outside the 0-100 range (not the legacy 0-1000 scale)", () => {
    expect(() => getBitScoreTierFromScore(-1)).toThrow(RangeError);
    expect(() => getBitScoreTierFromScore(101)).toThrow(RangeError);
    expect(() => getBitScoreTierFromScore(1000)).toThrow(RangeError);
  });

  it("maps on-chain tier index (0-3) to the same labels", () => {
    expect(getBitScoreTierFromIndex(0)).toBe("Restricted");
    expect(getBitScoreTierFromIndex(1)).toBe("Standard");
    expect(getBitScoreTierFromIndex(2)).toBe("Established");
    expect(getBitScoreTierFromIndex(3)).toBe("Trusted");
  });

  it("rejects an unknown tier index", () => {
    expect(() => getBitScoreTierFromIndex(4)).toThrow(RangeError);
  });

  it("covers the full 0-100 range with no gaps or overlaps", () => {
    for (let score = 0; score <= 100; score++) {
      expect(() => getBitScoreTierFromScore(score)).not.toThrow();
    }
    expect(BITSCORE_TIERS[0]!.min).toBe(0);
    expect(BITSCORE_TIERS[BITSCORE_TIERS.length - 1]!.max).toBe(100);
  });
});
