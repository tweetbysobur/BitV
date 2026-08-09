import type { BitVContractName, DeployedContract, YieldVaultRegistryEntry } from "./types";

/**
 * Deployed BitV contract addresses on Monad Testnet, keyed by contract
 * name. Populated only from confirmed, on-chain-validated deployments —
 * see docs/deployment-addresses-template.md for the full record
 * (deployer, transaction hashes, ValidateDeployment.s.sol result).
 * Every dashboard read must still treat a missing entry as "not
 * connected," never as "zero"/"empty."
 *
 * First real deployment: Build 11, 2026-08-09, Monad Testnet (chain
 * 10143). "ComplianceGuardPool" reuses BitVPoolManager's own address —
 * it is the same deployed contract, self-scoped for its own RuleV2
 * rules. No YieldVault is deployed yet.
 */
export const contractAddresses: Partial<Record<BitVContractName, DeployedContract>> = {
  AccessManager: { address: "0xbc45739e380322f8620687f30a58be2fc391181f", chainId: 10143 },
  Treasury: { address: "0x0c73ca421732511617c99b17f552738a2155f79e", chainId: 10143 },
  BitScoreManager: { address: "0x70aed4ba41319e5e1d53484306859af88051afd8", chainId: 10143 },
  PoolManager: { address: "0x46f89aeee3af4c77c2c77ad3b05412404100cc93", chainId: 10143 },
  ComplianceGuardPool: { address: "0x46f89aeee3af4c77c2c77ad3b05412404100cc93", chainId: 10143 },
  LendingManager: { address: "0x9e1b4a5e49186b732265fea4388f3f16b303decf", chainId: 10143 },
  RWACollateralRegistry: { address: "0x5f0b02b6ba612cf5512fc01c6e20abf5f859df77", chainId: 10143 },
  CVAAdapter: { address: "0x2d2f0bdfea5e7e8c7dda7a6cd9dbd6f93ffd03e8", chainId: 10143 },
};

/** Deployed BitVYieldVault instances. Empty until real vaults are
 * deployed and their strategy composition is confirmed — see
 * YieldVaultRegistryEntry's NatSpec for why `isTestStrategy` must never
 * be guessed. */
export const yieldVaults: readonly YieldVaultRegistryEntry[] = [];

/** RWA collateral assets the dashboard should query
 * BitVRWACollateralRegistry about. Empty until real assets are
 * registered and their addresses are confirmed — never invented. */
export const rwaAssets: readonly DeployedContract[] = [];

/** Debt/collateral pool assets the dashboard should query
 * BitVPoolManager about. Empty until real pools exist.
 *
 * BVTEST (BitVTestToken) — a clearly-labeled, no-real-value testnet
 * asset (see docs/testnet-assets.md), with a pool created via
 * contracts/script/DeployTestnetAssets.s.sol and priced by
 * StaticPriceOracle (testnet-only, non-production — see
 * docs/oracle-deployment-plan.md). Never present this as a real asset
 * or its price as a real market price. */
export const poolAssets: readonly DeployedContract[] = [
  { address: "0xD031f2F863dd481a869814CaE6813b17590C3B45", chainId: 10143 },
];
