"use client";

import { useReadContract } from "wagmi";
import { bitVRWACollateralRegistryAbi } from "@/services/contracts/abis";
import { useContractAddress } from "./useContractAddress";
import { deriveCVALabel, type CVARecognitionLabel } from "@/lib/cva";
import type { DataState } from "@/lib/data-state";
import type { Address } from "viem";

export interface CVAStatusData {
  adminAttestedCVA: boolean;
  interfaceVerified: boolean;
  label: CVARecognitionLabel;
}

/** Reads BitVRWACollateralRegistry's two-stage CVA status
 * (isCVAAdminAttested / isCVAInterfaceVerified) for one RWA asset —
 * kept structurally separate from CVI (useCVIStatus.ts) and never
 * merged. See lib/cva.ts for the label derivation and the explicit
 * "never claim Cleanverse approval" discipline. */
export function useCVAStatus(assetAddress: Address | undefined): DataState<CVAStatusData> {
  const registryAddress = useContractAddress("RWACollateralRegistry");
  const enabled = Boolean(registryAddress) && Boolean(assetAddress);

  const attestedRead = useReadContract({
    address: registryAddress,
    abi: bitVRWACollateralRegistryAbi,
    functionName: "isCVAAdminAttested",
    args: assetAddress ? [assetAddress] : undefined,
    query: { enabled },
  });
  const verifiedRead = useReadContract({
    address: registryAddress,
    abi: bitVRWACollateralRegistryAbi,
    functionName: "isCVAInterfaceVerified",
    args: assetAddress ? [assetAddress] : undefined,
    query: { enabled },
  });

  if (!registryAddress) {
    return { status: "unavailable", reason: "BitVRWACollateralRegistry is not configured for this network." };
  }
  if (!assetAddress) return { status: "unavailable", reason: "No asset selected." };
  if (attestedRead.isLoading || verifiedRead.isLoading) return { status: "loading" };
  if (attestedRead.isError || verifiedRead.isError || attestedRead.data === undefined || verifiedRead.data === undefined) {
    return { status: "error", message: "Could not read CVA status from the registry." };
  }

  const adminAttestedCVA = attestedRead.data;
  const interfaceVerified = verifiedRead.data;
  return {
    status: "loaded",
    data: { adminAttestedCVA, interfaceVerified, label: deriveCVALabel({ adminAttestedCVA, interfaceVerified }) },
  };
}
