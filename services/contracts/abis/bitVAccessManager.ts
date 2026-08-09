/**
 * ABI fragment for BitVAccessManager — transcribed directly from
 * contracts/src/core/BitVAccessManager.sol (standard OpenZeppelin
 * AccessControl underneath). Only `hasRole` and the `PROTOCOL_ADMIN_ROLE`
 * constant getter are exposed, since the dashboard's one current use is
 * gating the Treasury reserve-claim admin panel (Prompt 16) — never a
 * substitute for the contract's own on-chain role enforcement, which
 * this UI check mirrors, not replaces.
 */
export const bitVAccessManagerAbi = [
  {
    type: "function",
    name: "hasRole",
    stateMutability: "view",
    inputs: [
      { name: "role", type: "bytes32" },
      { name: "account", type: "address" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "PROTOCOL_ADMIN_ROLE",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bytes32" }],
  },
] as const;
