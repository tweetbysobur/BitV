import { describe, expect, it } from "vitest";
import { deriveCVIStatus } from "@/lib/cvi";

describe("CVI status rendering", () => {
  it("is unavailable when no wallet is connected", () => {
    expect(
      deriveCVIStatus({
        walletConnected: false,
        validatorConfigured: true,
        complianceVerifyResult: true,
        readError: false,
      }),
    ).toBe("unavailable");
  });

  it("is unavailable when the validator address isn't configured", () => {
    expect(
      deriveCVIStatus({
        walletConnected: true,
        validatorConfigured: false,
        complianceVerifyResult: true,
        readError: false,
      }),
    ).toBe("unavailable");
  });

  it("is unavailable on a read error, even if a stale result exists", () => {
    expect(
      deriveCVIStatus({
        walletConnected: true,
        validatorConfigured: true,
        complianceVerifyResult: true,
        readError: true,
      }),
    ).toBe("unavailable");
  });

  it("is unavailable while the read is pending", () => {
    expect(
      deriveCVIStatus({
        walletConnected: true,
        validatorConfigured: true,
        complianceVerifyResult: undefined,
        readError: false,
      }),
    ).toBe("unavailable");
  });

  it("is verified only when complianceVerify actually returns true", () => {
    expect(
      deriveCVIStatus({
        walletConnected: true,
        validatorConfigured: true,
        complianceVerifyResult: true,
        readError: false,
      }),
    ).toBe("verified");
  });

  it("is not-verified when complianceVerify returns false", () => {
    expect(
      deriveCVIStatus({
        walletConnected: true,
        validatorConfigured: true,
        complianceVerifyResult: false,
        readError: false,
      }),
    ).toBe("not-verified");
  });
});
