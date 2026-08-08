/**
 * Read-only ABI fragment for Cleanverse's IAPassComplianceValidator —
 * transcribed from contracts/src/interfaces/external/
 * IAPassComplianceValidator.sol, itself transcribed from the official
 * "Cleanverse Compliance Protocol (CCP) Integration Guide (For CVI
 * Compliance Validator) V2" — see docs/cleanverse-integration.md.
 * This is a Cleanverse contract, not a BitV one — the dashboard reads
 * it directly only for `complianceVerify`, the CVI eligibility check;
 * everything else about CVA/CVI stays behind BitVComplianceGuard/
 * BitVCVAAdapter per the existing architecture.
 */
export const iaPassComplianceValidatorAbi = [
  {
    type: "function",
    name: "complianceVerify",
    stateMutability: "view",
    inputs: [
      { name: "poolAddress", type: "address" },
      { name: "userAddress", type: "address" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "getRulesV2",
    stateMutability: "view",
    inputs: [{ name: "poolAddress", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple[]",
        components: [
          { name: "allowedGroup", type: "bytes2" },
          { name: "allowedSubGroup", type: "bytes2" },
          { name: "minTier", type: "uint8" },
          { name: "minSubTier", type: "uint8" },
          { name: "poolCountryBitmap", type: "uint256" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "isRegistered",
    stateMutability: "view",
    inputs: [{ name: "poolAddress", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;
