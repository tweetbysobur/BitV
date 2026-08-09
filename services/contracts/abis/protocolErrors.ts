/**
 * Custom Solidity error ABI fragments — transcribed from
 * contracts/src/libraries/ProtocolErrors.sol, VaultErrors.sol, and
 * RWAErrors.sol. Spread into the relevant contract ABIs (never called
 * directly) purely so viem/wagmi can decode a revert into the actual
 * error name + args instead of surfacing "execution reverted for an
 * unknown reason" — viem's error decoding only works when the ABI
 * passed to the write call includes the `error` entries a contract can
 * revert with. Without this, every one of BitV's ~20 custom Solidity
 * errors was undecodable in the UI.
 */
export const protocolErrorsAbi = [
  { type: "error", name: "PoolAlreadyExists", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "PoolNotActive", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "PoolIsPaused", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "BorrowingDisabled", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "CollateralDisabled", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "ZeroAmount", inputs: [] },
  {
    type: "error",
    name: "AmountExceedsBalance",
    inputs: [
      { name: "requested", type: "uint256" },
      { name: "available", type: "uint256" },
    ],
  },
  {
    type: "error",
    name: "AmountExceedsAvailableLiquidity",
    inputs: [
      { name: "requested", type: "uint256" },
      { name: "available", type: "uint256" },
    ],
  },
  {
    type: "error",
    name: "SupplyCapExceeded",
    inputs: [
      { name: "newTotal", type: "uint256" },
      { name: "cap", type: "uint256" },
    ],
  },
  {
    type: "error",
    name: "BorrowCapExceeded",
    inputs: [
      { name: "newTotal", type: "uint256" },
      { name: "cap", type: "uint256" },
    ],
  },
  {
    type: "error",
    name: "InsufficientCollateral",
    inputs: [
      { name: "requiredValue", type: "uint256" },
      { name: "availableValue", type: "uint256" },
    ],
  },
  { type: "error", name: "NoOutstandingDebt", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "PositionIsHealthy", inputs: [{ name: "healthFactorRay", type: "uint256" }] },
  { type: "error", name: "PriceOracleNotSet", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "ZeroAddress", inputs: [] },
  { type: "error", name: "CallerNotLendingManager", inputs: [] },
  { type: "error", name: "CallerNotTreasury", inputs: [] },
  { type: "error", name: "InvalidRiskParams", inputs: [] },
  {
    type: "error",
    name: "Unauthorized",
    inputs: [
      { name: "caller", type: "address" },
      { name: "role", type: "bytes32" },
    ],
  },
  { type: "error", name: "ZeroPrice", inputs: [{ name: "asset", type: "address" }] },
  // Vault (VaultErrors.sol)
  { type: "error", name: "ZeroShares", inputs: [] },
  { type: "error", name: "DepositsPaused", inputs: [] },
  { type: "error", name: "WithdrawalsPaused", inputs: [] },
  { type: "error", name: "StrategyOperationsPaused", inputs: [] },
  {
    type: "error",
    name: "BelowMinimumDeposit",
    inputs: [
      { name: "assets", type: "uint256" },
      { name: "minDeposit", type: "uint256" },
    ],
  },
  {
    type: "error",
    name: "VaultCapExceeded",
    inputs: [
      { name: "newTotal", type: "uint256" },
      { name: "cap", type: "uint256" },
    ],
  },
  { type: "error", name: "OnlySelfService", inputs: [] },
  { type: "error", name: "StrategyNotSet", inputs: [] },
  {
    type: "error",
    name: "InsufficientLiquidity",
    inputs: [
      { name: "requested", type: "uint256" },
      { name: "available", type: "uint256" },
    ],
  },
  // RWA (RWAErrors.sol)
  { type: "error", name: "AssetAlreadyRegistered", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "AssetNotRegistered", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "AssetDelisted", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "InvalidOraclePrice", inputs: [{ name: "asset", type: "address" }] },
  { type: "error", name: "AssetNotEligibleForDeposit", inputs: [{ name: "asset", type: "address" }] },
  {
    type: "error",
    name: "CollateralCapExceeded",
    inputs: [
      { name: "asset", type: "address" },
      { name: "newTotal", type: "uint256" },
      { name: "cap", type: "uint256" },
    ],
  },
] as const;
