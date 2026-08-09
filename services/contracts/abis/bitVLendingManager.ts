/**
 * Read-only ABI fragment for BitVLendingManager — transcribed from
 * contracts/src/core/BitVLendingManager.sol.
 */
import { protocolErrorsAbi } from "./protocolErrors";

const accountDataOutput = {
  name: "",
  type: "tuple",
  components: [
    { name: "totalCollateralValue", type: "uint256" },
    { name: "totalDebtValue", type: "uint256" },
    { name: "availableBorrowValue", type: "uint256" },
    { name: "weightedMaxLtvValue", type: "uint256" },
    { name: "currentLiquidationThresholdBps", type: "uint256" },
    { name: "healthFactorRay", type: "uint256" },
  ],
} as const;

export const bitVLendingManagerAbi = [
  ...protocolErrorsAbi,
  {
    type: "function",
    name: "getCollateralBalance",
    stateMutability: "view",
    inputs: [
      { name: "user", type: "address" },
      { name: "asset", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "getCurrentDebt",
    stateMutability: "view",
    inputs: [
      { name: "user", type: "address" },
      { name: "asset", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "getUserAccountData",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [accountDataOutput],
  },
  {
    type: "function",
    name: "getUserAccountDataForBorrow",
    stateMutability: "view",
    inputs: [
      { name: "user", type: "address" },
      { name: "debtAsset", type: "address" },
    ],
    outputs: [accountDataOutput],
  },
  {
    type: "function",
    name: "getHealthFactor",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "getEffectiveAvailableBorrowValue",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "getQuotedBaseRateDiscountRay",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "getTotalCollateralByAsset",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "closeFactorBps",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint16" }],
  },
  {
    type: "function",
    name: "bitScoreManager",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "rwaRegistry",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "depositCollateral",
    stateMutability: "nonpayable",
    inputs: [
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "withdrawCollateral",
    stateMutability: "nonpayable",
    inputs: [
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "borrow",
    stateMutability: "nonpayable",
    inputs: [
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "repay",
    stateMutability: "nonpayable",
    inputs: [
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "repaid", type: "uint256" }],
  },
] as const;
