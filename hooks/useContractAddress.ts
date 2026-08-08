"use client";

import { useMemo } from "react";
import { contractAddresses } from "@/services/contracts/addresses";
import type { BitVContractName } from "@/services/contracts/types";
import { useWalletStatus } from "./useWalletStatus";

/** Resolves a BitV contract's deployed address for the currently
 * connected chain, or `undefined` if it isn't configured for that chain
 * — the single check every contract-reading hook uses before attempting
 * a read, so "not deployed"/"not configured" is handled once, not
 * scattered across every hook's own logic. */
export function useContractAddress(name: BitVContractName): `0x${string}` | undefined {
  const { chainId } = useWalletStatus();
  return useMemo(() => {
    const entry = contractAddresses[name];
    if (!entry) return undefined;
    if (chainId !== undefined && entry.chainId !== chainId) return undefined;
    return entry.address;
  }, [name, chainId]);
}
