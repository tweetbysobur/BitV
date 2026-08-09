/**
 * ABI fragment for BitVPoolManager — transcribed directly from
 * contracts/src/core/BitVPoolManager.sol (BitV's own contract, not a
 * Cleanverse primitive). Mostly view functions the dashboard reads;
 * `reserveBalance` (Prompt 14) is the one addition used by the
 * Treasury reserve-claim admin panel (Prompt 16) — see
 * services/contracts/abis/bitVTreasury.ts for the actual claim call,
 * which goes through BitVTreasury.claimPoolReserve, not this contract
 * directly (BitVPoolManager.claimReserve only accepts msg.sender ==
 * TREASURY, so the frontend never calls it on PoolManager itself).
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
  {
    type: "function",
    name: "reserveBalance",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;
