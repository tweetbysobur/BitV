import { describe, expect, it } from "vitest";
import { formatPositionRows, hasAnyNonzeroPosition, type AssetPositionRow } from "@/lib/positions";

const rowA: AssetPositionRow = {
  assetAddress: "0xAAA",
  symbol: "bvUSD",
  rawAmount: 1_000_000000000000000000n,
  decimals: 18,
};
const rowB: AssetPositionRow = {
  assetAddress: "0xBBB",
  symbol: "bvETH",
  rawAmount: 0n,
  decimals: 18,
};
const rowUnreadable: AssetPositionRow = {
  assetAddress: "0xCCC",
  symbol: undefined,
  rawAmount: undefined,
  decimals: undefined,
};

describe("multi-asset collateral/debt rendering", () => {
  it("formats multiple assets independently, never assuming a single collateral/debt asset", () => {
    const formatted = formatPositionRows([rowA, rowB]);
    expect(formatted).toHaveLength(2);
    expect(formatted[0]).toEqual({ assetAddress: "0xAAA", symbol: "bvUSD", amount: "1000" });
    expect(formatted[1]).toEqual({ assetAddress: "0xBBB", symbol: "bvETH", amount: "0" });
  });

  it("shows Unavailable, not zero, for a row whose amount couldn't be read", () => {
    const formatted = formatPositionRows([rowUnreadable]);
    expect(formatted[0]!.amount).toBe("Unavailable");
    expect(formatted[0]!.symbol).toBe("Unavailable");
  });

  it("treats a real on-chain zero balance as loaded data, not missing data", () => {
    const formatted = formatPositionRows([rowB]);
    expect(formatted[0]!.amount).toBe("0");
  });

  it("distinguishes empty (all zero/no position) from having any real position", () => {
    expect(hasAnyNonzeroPosition([rowB])).toBe(false);
    expect(hasAnyNonzeroPosition([rowA, rowB])).toBe(true);
    expect(hasAnyNonzeroPosition([rowUnreadable])).toBe(false);
  });
});
