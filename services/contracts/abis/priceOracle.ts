/**
 * Read-only ABI fragment for IPriceOracle — transcribed from
 * contracts/src/interfaces/IPriceOracle.sol. BitV-original interface,
 * not a Cleanverse primitive. The only deployed implementation on
 * Monad Testnet is StaticPriceOracle (admin-set prices, no economic
 * security) — see docs/oracle-deployment-plan.md. Never present a
 * price read through this ABI as production market pricing.
 */
export const priceOracleAbi = [
  {
    type: "function",
    name: "getPrice",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [
      { name: "price", type: "uint256" },
      { name: "decimals", type: "uint8" },
    ],
  },
] as const;
