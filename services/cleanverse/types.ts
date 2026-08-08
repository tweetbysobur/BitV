/**
 * Cleanverse integration boundary — TYPE DEFINITIONS ONLY.
 *
 * `RuleV2` is confirmed against the official "CVI Integration Guide V2"
 * PDF (provided directly by the user). `CleanverseIdentity` /
 * `CleanverseVerifiedAsset` remain unfilled — see
 * /docs/cleanverse-integration-todo.md for what's still unknown (identity
 * lookup API, off-chain SDK, auth model).
 *
 * Do not add fields, methods, or endpoints here speculatively. Every shape
 * in this file must be traceable to an actual Cleanverse doc reference.
 */

/** Placeholder for whatever identity credential/attestation Cleanverse issues. */
export type CleanverseIdentity = Record<string, never>;

/** Placeholder for whatever verified-asset primitive Cleanverse exposes. */
export type CleanverseVerifiedAsset = Record<string, never>;

/**
 * Mirrors the on-chain `IAPassComplianceValidator.RuleV2` struct
 * (contracts/src/interfaces/external/IAPassComplianceValidator.sol) for
 * off-chain/UI reads via viem. Confirmed field types and semantics from
 * the CVI Integration Guide V2, §3.1: `allowedGroup`/`allowedSubGroup` are
 * `bytes2` (empty = no restriction), `minTier`/`minSubTier` are `uint8`
 * (0 = no restriction), `poolCountryBitmap` is a `uint256` bitmap (0 = no
 * restriction, checked via bitwise AND).
 */
export interface RuleV2 {
  allowedGroup: `0x${string}`; // bytes2
  allowedSubGroup: `0x${string}`; // bytes2
  minTier: number; // uint8
  minSubTier: number; // uint8
  poolCountryBitmap: bigint; // uint256
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
