/**
 * CVA (Cleanverse Verified Asset) recognition status — the
 * asset/policy layer, kept structurally separate from CVI (lib/cvi.ts).
 * Mirrors BitVRWACollateralRegistry's two-stage model exactly (Build
 * 07.1): `adminAttestedCVA` (a BitV admin's claim) and
 * `isCVAInterfaceVerified` (a live, on-chain interface-shape probe via
 * BitVCVAAdapter). See docs/cva-integration-specification.md §7 and
 * docs/cva-integration-implementation.md.
 *
 * IMPORTANT: none of these labels ever claim "Cleanverse approved" —
 * per the approved specification, no on-chain query for Cleanverse's
 * own off-chain CVA approval exists. Do not add a label here that
 * implies otherwise.
 */
export interface CVAStatusFlags {
  adminAttestedCVA: boolean;
  interfaceVerified: boolean;
}

export type CVARecognitionLabel =
  | "Fully recognized (BitV verification only)"
  | "Admin attested — interface not verified"
  | "Interface verified — not admin attested"
  | "Not attested as CVA";

export function deriveCVALabel(flags: CVAStatusFlags): CVARecognitionLabel {
  if (flags.adminAttestedCVA && flags.interfaceVerified) {
    return "Fully recognized (BitV verification only)";
  }
  if (flags.adminAttestedCVA) return "Admin attested — interface not verified";
  if (flags.interfaceVerified) return "Interface verified — not admin attested";
  return "Not attested as CVA";
}

/** Explicit, reusable disclaimer — every CVA-status UI element that
 * shows `deriveCVALabel`'s output must also surface this (or
 * equivalent) text, per the task's instruction not to imply Cleanverse
 * approval beyond what's actually confirmed. */
export const CVA_RECOGNITION_DISCLAIMER =
  "BitV verification confirms the asset's configured contract responds the way a CVA policy contract is expected to. It does not confirm Cleanverse has approved this asset as a CVA — no on-chain query for that fact exists.";
