import { describe, expect, it } from "vitest";
import { PROTOCOL_ADMIN_ROLE, deriveClaimPoolReserveState } from "@/lib/treasury";

describe("PROTOCOL_ADMIN_ROLE", () => {
  it("matches Solidity's keccak256(\"PROTOCOL_ADMIN_ROLE\") exactly", () => {
    // Ground truth computed via `cast keccak "PROTOCOL_ADMIN_ROLE"` against
    // the actual BitVAccessManager.sol constant, not assumed.
    expect(PROTOCOL_ADMIN_ROLE).toBe(
      "0xd0c934f24ef5a377dc3832429ce607cbe940a3ca3c6cd7e532bd35b4b212d196",
    );
  });
});

describe("deriveClaimPoolReserveState", () => {
  it("is idle before any write is submitted", () => {
    expect(deriveClaimPoolReserveState("idle", undefined)).toBe("idle");
  });

  it("is pending while the wallet write is in flight", () => {
    expect(deriveClaimPoolReserveState("pending", undefined)).toBe("pending");
  });

  it("is error if the write itself fails (e.g. user rejection)", () => {
    expect(deriveClaimPoolReserveState("error", undefined)).toBe("error");
  });

  it("is confirming once a tx hash exists but the receipt hasn't landed", () => {
    expect(deriveClaimPoolReserveState("success", "pending")).toBe("confirming");
    expect(deriveClaimPoolReserveState("success", undefined)).toBe("confirming");
  });

  it("is success only once the receipt itself confirms success", () => {
    expect(deriveClaimPoolReserveState("success", "success")).toBe("success");
  });

  it("is error if the transaction reverted on-chain, even though the write succeeded", () => {
    expect(deriveClaimPoolReserveState("success", "error")).toBe("error");
  });

  it("never reports success from the write status alone (would hide a revert)", () => {
    // The critical property: writeStatus "success" only means "the wallet
    // accepted and broadcast it" — never treat that as feature success.
    const result = deriveClaimPoolReserveState("success", "pending");
    expect(result).not.toBe("success");
  });
});
