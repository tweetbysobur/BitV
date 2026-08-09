"use client";

import { useReadContracts } from "wagmi";
import { bitVYieldVaultAbi } from "@/services/contracts/abis";
import { yieldVaults } from "@/services/contracts/addresses";
import { useWalletStatus } from "./useWalletStatus";
import type { DataState } from "@/lib/data-state";
import type { Address } from "viem";

export interface VaultPositionRow {
  vaultAddress: Address;
  isTestStrategy: boolean;
  underlyingAsset: Address | undefined;
  underlyingSymbol: string | undefined;
  userShares: bigint | undefined;
  /** Assets your shares currently convert to, per the vault's own
   * `convertToAssets` — never computed client-side, so it can never
   * drift from the contract's own share-price math. */
  userUnderlyingValue: bigint | undefined;
  /** `maxWithdraw(user)` — the exact assets amount the vault will
   * currently let this user withdraw, already folding in idle
   * liquidity and withdrawalsPaused. Distinct from userUnderlyingValue:
   * if idle liquidity is short, maxWithdraw can be lower than the
   * user's full share value. */
  maxWithdrawAssets: bigint | undefined;
  /** The vault's own ERC20 `decimals()` — NOT the same as the
   * underlying asset's decimals. BitVYieldVault uses a 6-decimal
   * inflation-attack offset (`_decimalsOffset()`), so share decimals =
   * asset decimals + 6. Always format `userShares` with this value,
   * never assume it matches the underlying asset. */
  shareDecimals: number | undefined;
  totalAssets: bigint | undefined;
  strategyAddress: Address | undefined;
  depositsPaused: boolean | undefined;
  withdrawalsPaused: boolean | undefined;
  performanceFeeBps: bigint | undefined;
}

/** Reads every deployed BitVYieldVault (services/contracts/
 * addresses.ts's `yieldVaults` — empty until real vaults are deployed)
 * for the connected wallet's position. `isTestStrategy` comes only from
 * that static registry, never inferred — see lib/vault.ts. Two batched
 * reads: the second (convertToAssets/maxWithdraw) depends on the first
 * batch's share balance, so it can't be combined into one call. */
export function useVaultPositions(): DataState<VaultPositionRow[]> {
  const { address: userAddress, state: walletState } = useWalletStatus();
  const enabled = walletState === "connected" && Boolean(userAddress) && yieldVaults.length > 0;

  const { data, isLoading, isError } = useReadContracts({
    contracts: yieldVaults.flatMap((vault) => [
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "asset", args: [] },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "balanceOf", args: userAddress ? [userAddress] : undefined },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "decimals", args: [] },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "totalAssets", args: [] },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "strategy", args: [] },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "depositsPaused", args: [] },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "withdrawalsPaused", args: [] },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "performanceFeeBps", args: [] },
    ]),
    query: { enabled },
  });

  const READS_PER_VAULT = 8;
  const shareBalances = yieldVaults.map((vault, i) => {
    const shares = data?.[i * READS_PER_VAULT + 1];
    return shares?.status === "success" ? (shares.result as bigint) : undefined;
  });

  const conversionsEnabled = enabled && !isLoading && !isError && shareBalances.some((s) => s !== undefined);

  const { data: conversionData, isLoading: conversionsLoading } = useReadContracts({
    contracts: yieldVaults.flatMap((vault, i) => [
      {
        address: vault.address,
        abi: bitVYieldVaultAbi,
        functionName: "convertToAssets",
        args: [shareBalances[i] ?? 0n],
      },
      { address: vault.address, abi: bitVYieldVaultAbi, functionName: "maxWithdraw", args: userAddress ? [userAddress] : undefined },
    ]),
    query: { enabled: conversionsEnabled },
  });

  if (yieldVaults.length === 0) return { status: "empty" };
  if (walletState !== "connected") return { status: "unavailable", reason: "Wallet not connected." };
  if (isLoading) return { status: "loading" };
  if (isError || !data) return { status: "error", message: "Could not read vault data from the contract." };
  if (conversionsEnabled && conversionsLoading) return { status: "loading" };

  const rows: VaultPositionRow[] = yieldVaults.map((vault, i) => {
    const [asset, shares, shareDecimals, total, strategy, depositsPaused, withdrawalsPaused, feeBps] = data.slice(
      i * READS_PER_VAULT,
      i * READS_PER_VAULT + READS_PER_VAULT,
    );
    const underlyingAsset = asset?.status === "success" ? (asset.result as Address) : undefined;
    const conversions = conversionData?.slice(i * 2, i * 2 + 2);
    const underlyingValue = conversions?.[0];
    const maxWithdraw = conversions?.[1];
    return {
      vaultAddress: vault.address,
      isTestStrategy: vault.isTestStrategy,
      underlyingAsset,
      underlyingSymbol: undefined, // resolved separately per-symbol if the underlying is known
      userShares: shares?.status === "success" ? (shares.result as bigint) : undefined,
      shareDecimals: shareDecimals?.status === "success" ? (shareDecimals.result as number) : undefined,
      userUnderlyingValue: underlyingValue?.status === "success" ? (underlyingValue.result as bigint) : undefined,
      maxWithdrawAssets: maxWithdraw?.status === "success" ? (maxWithdraw.result as bigint) : undefined,
      totalAssets: total?.status === "success" ? (total.result as bigint) : undefined,
      strategyAddress: strategy?.status === "success" ? (strategy.result as Address) : undefined,
      depositsPaused: depositsPaused?.status === "success" ? (depositsPaused.result as boolean) : undefined,
      withdrawalsPaused:
        withdrawalsPaused?.status === "success" ? (withdrawalsPaused.result as boolean) : undefined,
      performanceFeeBps: feeBps?.status === "success" ? (feeBps.result as bigint) : undefined,
    };
  });

  return { status: "loaded", data: rows };
}
