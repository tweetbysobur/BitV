/**
 * Read-only ABI fragment for BitVCVAAdapter — transcribed from
 * contracts/src/core/BitVCVAAdapter.sol. `previewTransfer` is
 * deliberately NOT included: it always reverts on-chain (Cleanverse's
 * `canTransfer` return/rejection behavior is unconfirmed — see
 * docs/cva-integration-implementation.md) and must never be presented
 * to a user as a working preview.
 */
export const bitVCVAAdapterAbi = [
  {
    type: "function",
    name: "isRecognizedCVA",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "policyOf",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "isCurrentlyUsable",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;
