import { keccak256, toBytes } from "viem";

/** keccak256("PROTOCOL_ADMIN_ROLE") — must always equal
 * BitVAccessManager.sol's own `PROTOCOL_ADMIN_ROLE` constant. Verified
 * against `cast keccak "PROTOCOL_ADMIN_ROLE"` in
 * tests/treasury.test.ts, not just asserted. */
export const PROTOCOL_ADMIN_ROLE = keccak256(toBytes("PROTOCOL_ADMIN_ROLE"));

export type ClaimPoolReserveState = "idle" | "pending" | "confirming" | "success" | "error";

export type WriteStatus = "idle" | "pending" | "success" | "error";
export type ReceiptStatus = "pending" | "success" | "error";

/** Pure derivation of useClaimPoolReserve's UI state from wagmi's
 * useWriteContract/useWaitForTransactionReceipt statuses — extracted so
 * the "never show success before the receipt confirms" rule is
 * unit-testable without a wagmi/React render harness. */
export function deriveClaimPoolReserveState(
  writeStatus: WriteStatus,
  receiptStatus: ReceiptStatus | undefined,
): ClaimPoolReserveState {
  if (writeStatus === "pending") return "pending";
  if (writeStatus === "error") return "error";
  if (writeStatus === "success") {
    if (receiptStatus === "success") return "success";
    if (receiptStatus === "error") return "error";
    return "confirming"; // receiptStatus === "pending" or not yet started
  }
  return "idle";
}
