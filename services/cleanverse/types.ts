/**
 * Cleanverse integration boundary — TYPE DEFINITIONS ONLY.
 *
 * These types are intentionally unfilled placeholders. They must not be
 * treated as verified against Cleanverse's official docs until that review
 * happens — see /docs/cleanverse-integration-todo.md for exactly what is
 * still unknown (identity primitives, verified-asset primitives, SDK/API
 * surface, auth model, integration flow).
 *
 * Do not add fields, methods, or endpoints here speculatively. Every shape
 * in this file must be traceable to an actual Cleanverse doc reference once
 * that review is done.
 */

/** Placeholder for whatever identity credential/attestation Cleanverse issues. */
export type CleanverseIdentity = Record<string, never>;

/** Placeholder for whatever verified-asset primitive Cleanverse exposes. */
export type CleanverseVerifiedAsset = Record<string, never>;

/**
 * Mirrors the on-chain `IAPassComplianceValidator.RuleV2` struct
 * (contracts/src/interfaces/external/IAPassComplianceValidator.sol) for
 * off-chain/UI reads via viem. Field TYPES here are an engineering
 * assumption, not confirmed from Cleanverse's docs — see that file's
 * header and docs/cleanverse-integration.md.
 */
export interface RuleV2 {
  allowedGroup: bigint;
  allowedSubGroup: bigint;
  minTier: bigint;
  minSubTier: bigint;
  poolCountryBitmap: bigint;
}

/**
 * BitV's own UI-facing compliance status model — NOT a Cleanverse type.
 * Wraps the result of a `complianceVerify` call (or the absence of one
 * yet) into states the frontend can render without guessing at
 * intermediate values.
 */
export type ComplianceStatus =
  | { state: "loading" }
  | { state: "verification-required" }
  | { state: "eligible" }
  | { state: "ineligible" }
  | { state: "error"; message: string };
