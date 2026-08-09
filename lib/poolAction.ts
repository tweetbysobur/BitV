import type { WriteStatus, ReceiptStatus, ClaimPoolReserveState } from "./treasury";

export type PoolActionState = ClaimPoolReserveState;

/** Same derivation rule as deriveClaimPoolReserveState (lib/treasury.ts):
 * never report "success" before the on-chain receipt confirms. Reused
 * here for the approve/deposit/withdraw actions on the Lending page. */
export function derivePoolActionState(
  writeStatus: WriteStatus,
  receiptStatus: ReceiptStatus | undefined,
): PoolActionState {
  if (writeStatus === "pending") return "pending";
  if (writeStatus === "error") return "error";
  if (writeStatus === "success") {
    if (receiptStatus === "success") return "success";
    if (receiptStatus === "error") return "error";
    return "confirming";
  }
  return "idle";
}
