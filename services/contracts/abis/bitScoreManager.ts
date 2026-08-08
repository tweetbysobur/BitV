/**
 * Read-only ABI fragment for BitScoreManager — transcribed from
 * contracts/src/core/BitScoreManager.sol. Score scale is 0-100
 * (uint8) — see docs/bitscore-specification.md.
 */
export const bitScoreManagerAbi = [
  {
    type: "function",
    name: "getScore",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "getTier",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "getRawState",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [
      { name: "positiveContribution", type: "uint8" },
      { name: "liquidationPenalty", type: "uint16" },
      { name: "badDebtPenalty", type: "uint16" },
      { name: "successfulRepayments", type: "uint32" },
      { name: "liquidationCount", type: "uint32" },
      { name: "badDebtCount", type: "uint32" },
    ],
  },
  {
    type: "function",
    name: "MIN_SCORE",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "MAX_SCORE",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "TIER_1_FLOOR",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "TIER_2_FLOOR",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "TIER_3_FLOOR",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "tierAdjustments",
    stateMutability: "view",
    inputs: [{ name: "", type: "uint256" }],
    outputs: [
      { name: "ltvHeadroomBps", type: "int16" },
      { name: "baseRateDiscountRay", type: "uint256" },
    ],
  },
] as const;
