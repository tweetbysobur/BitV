/**
 * Read-only ABI fragment for BitVPoolManager — transcribed directly from
 * contracts/src/core/BitVPoolManager.sol (BitV's own contract, not a
 * Cleanverse primitive). Only the view functions the dashboard actually
 * reads are included; write functions are intentionally omitted from
 * this milestone's read-only data layer.
 */
export const bitVPoolManagerAbi = [
  {
    type: "function",
    name: "getPool",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "isActive", type: "bool" },
          { name: "isPaused", type: "bool" },
          { name: "isBorrowingEnabled", type: "bool" },
          { name: "isCollateralEnabled", type: "bool" },
          { name: "ltvBps", type: "uint16" },
          { name: "maxLtvWithScoreBps", type: "uint16" },
          { name: "liquidationThresholdBps", type: "uint16" },
          { name: "liquidationBonusBps", type: "uint16" },
          { name: "reserveFactorBps", type: "uint16" },
          { name: "supplyCap", type: "uint256" },
          { name: "borrowCap", type: "uint256" },
          { name: "totalScaledSupply", type: "uint256" },
          { name: "totalScaledDebt", type: "uint256" },
          { name: "liquidityIndexRay", type: "uint256" },
          { name: "borrowIndexRay", type: "uint256" },
          { name: "lastUpdateTimestamp", type: "uint40" },
          { name: "interestRateModel", type: "address" },
          { name: "priceOracle", type: "address" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [
      { name: "asset", type: "address" },
      { name: "user", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "totalSupplied",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "totalBorrowed",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "availableLiquidity",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "utilizationRay",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "lendingManager",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
] as const;
