import { describe, expect, it } from "vitest";
import { isLoaded, type DataState } from "@/lib/data-state";

describe("loading/error state model", () => {
  it("distinguishes loading from loaded", () => {
    const loading: DataState<number> = { status: "loading" };
    const loaded: DataState<number> = { status: "loaded", data: 42 };
    expect(isLoaded(loading)).toBe(false);
    expect(isLoaded(loaded)).toBe(true);
  });

  it("carries a reason for unavailable state (missing contract data)", () => {
    const state: DataState<number> = { status: "unavailable", reason: "Contract not configured" };
    expect(state.status).toBe("unavailable");
    expect(state.reason).toBe("Contract not configured");
  });

  it("carries a message for a genuine read error, distinct from unavailable", () => {
    const state: DataState<number> = { status: "error", message: "RPC call reverted" };
    expect(state.status).toBe("error");
    expect(state.message).toBe("RPC call reverted");
  });

  it("supports an explicit empty state distinct from unavailable/error", () => {
    const state: DataState<number[]> = { status: "empty" };
    expect(state.status).toBe("empty");
  });
});
