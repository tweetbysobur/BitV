/**
 * CVI (Cleanverse Verified Identity) eligibility status — the
 * participant-eligibility layer, derived only from
 * `IAPassComplianceValidator.complianceVerify`. Never merged with CVA
 * (asset-level) status — see lib/cva.ts for that, kept in a separate
 * module deliberately.
 */
export type CVIStatus = "verified" | "not-verified" | "unavailable";

export interface CVIStatusInputs {
  walletConnected: boolean;
  /** True only if a real, non-empty validator address is configured
   * (NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS) — never assume one. */
  validatorConfigured: boolean;
  /** Result of `complianceVerify(pool, user)`, or `undefined` if the
   * read hasn't resolved / isn't applicable. */
  complianceVerifyResult: boolean | undefined;
  /** True if the on-chain read itself failed (RPC error, revert,
   * contract not deployed at the configured address, etc.). */
  readError: boolean;
}

export function deriveCVIStatus(inputs: CVIStatusInputs): CVIStatus {
  if (!inputs.walletConnected) return "unavailable";
  if (!inputs.validatorConfigured) return "unavailable";
  if (inputs.readError) return "unavailable";
  if (inputs.complianceVerifyResult === undefined) return "unavailable";
  return inputs.complianceVerifyResult ? "verified" : "not-verified";
}
