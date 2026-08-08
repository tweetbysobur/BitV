/**
 * Read-only ABI fragment for BitVRWACollateralRegistry — transcribed
 * from contracts/src/core/BitVRWACollateralRegistry.sol (Build 06.1 /
 * 07.1's two-stage CVA status model).
 */
export const bitVRWACollateralRegistryAbi = [
  {
    type: "function",
    name: "isRegisteredAsset",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "isEligibleForNewActivity",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "isDebtAssetAllowed",
    stateMutability: "view",
    inputs: [
      { name: "asset", type: "address" },
      { name: "debtAsset", type: "address" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "getCollateralCap",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "getAssetConfig",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "status", type: "uint8" },
          { name: "underlyingPool", type: "address" },
          { name: "ltvBps", type: "uint16" },
          { name: "maxLtvWithScoreBps", type: "uint16" },
          { name: "liquidationThresholdBps", type: "uint16" },
          { name: "liquidationBonusBps", type: "uint16" },
          { name: "collateralCap", type: "uint256" },
          { name: "oracle", type: "address" },
          { name: "maxOracleStalenessSeconds", type: "uint32" },
          { name: "lastPriceVerifiedTimestamp", type: "uint40" },
          { name: "adminAttestedCVA", type: "bool" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "getAllowedDebtAssets",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "address[]" }],
  },
  {
    type: "function",
    name: "isCVAAdminAttested",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "isCVAInterfaceVerified",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "isCVAFullyRecognized",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "cvaAdapter",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
] as const;

/** BitVRWACollateralRegistry.AssetStatus enum ordering — mirrors
 * contracts/src/core/BitVRWACollateralRegistry.sol exactly. */
export const RWA_ASSET_STATUS = ["Unregistered", "Active", "Frozen", "Delisted"] as const;
