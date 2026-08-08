"use client";

import { useReadContract } from "wagmi";
import { iaPassComplianceValidatorAbi } from "@/services/contracts/abis";
import { cleanverseConfig } from "@/config/cleanverse";
import { useWalletStatus } from "./useWalletStatus";
import { deriveCVIStatus, type CVIStatus } from "@/lib/cvi";
import type { Address } from "viem";

export interface CVIStatusResult {
  status: CVIStatus;
  isLoading: boolean;
}

/** CVI (participant) eligibility for a specific protected BitV contract
 * (`poolAddress` in `complianceVerify`'s terms — e.g. BitVLendingManager).
 * Deliberately separate from CVA/RWA-asset status — see lib/cva.ts and
 * useCVAStatus.ts, never merged here. */
export function useCVIStatus(poolAddress: Address | undefined): CVIStatusResult {
  const { address: userAddress, state: walletState } = useWalletStatus();
  const validatorAddress = cleanverseConfig.validatorAddress as Address | undefined;
  const validatorConfigured = Boolean(validatorAddress);

  const enabled =
    walletState === "connected" && validatorConfigured && Boolean(userAddress) && Boolean(poolAddress);

  const { data, isLoading, isError } = useReadContract({
    address: validatorAddress,
    abi: iaPassComplianceValidatorAbi,
    functionName: "complianceVerify",
    args: poolAddress && userAddress ? [poolAddress, userAddress] : undefined,
    query: { enabled },
  });

  const status = deriveCVIStatus({
    walletConnected: walletState === "connected",
    validatorConfigured,
    complianceVerifyResult: data,
    readError: isError,
  });

  return { status, isLoading: enabled && isLoading };
}
