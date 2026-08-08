import { describe, expect, it } from "vitest";
import { formatHealthFactor, getHealthFactorStatus } from "@/lib/health-factor";

const RAY = 10n ** 27n;
const MAX_UINT256 = 2n ** 256n - 1n;

describe("health factor display states", () => {
  it("is unavailable when the value hasn't loaded", () => {
    expect(getHealthFactorStatus(undefined)).toBe("unavailable");
    expect(formatHealthFactor(undefined)).toBe("Unavailable");
  });

  it("is no-debt for the type(uint256).max sentinel", () => {
    expect(getHealthFactorStatus(MAX_UINT256)).toBe("no-debt");
    expect(formatHealthFactor(MAX_UINT256)).toBe("∞");
  });

  it("is danger below 1.0", () => {
    expect(getHealthFactorStatus((RAY * 99n) / 100n)).toBe("danger");
  });

  it("is warning between 1.0 and 1.5", () => {
    expect(getHealthFactorStatus(RAY)).toBe("warning");
    expect(getHealthFactorStatus((RAY * 149n) / 100n)).toBe("warning");
  });

  it("is healthy at 1.5 and above", () => {
    expect(getHealthFactorStatus((RAY * 15n) / 10n)).toBe("healthy");
    expect(getHealthFactorStatus(RAY * 10n)).toBe("healthy");
  });

  it("formats a real ray value to two decimals", () => {
    expect(formatHealthFactor((RAY * 175n) / 100n)).toBe("1.75");
  });
});
