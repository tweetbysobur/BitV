/**
 * ABI fragment for BitVTreasury — transcribed directly from
 * contracts/src/core/BitVTreasury.sol. Only what the dashboard's
 * Treasury administration panel (Prompt 16) needs: the reserve-claim
 * write call and its event. `withdraw`/`receiveFee` are not exposed
 * here — this milestone's frontend scope is strictly the reserve-claim
 * flow closed in Prompt 14.
 */
import { protocolErrorsAbi } from "./protocolErrors";

export const bitVTreasuryAbi = [
  ...protocolErrorsAbi,
  {
    type: "function",
    name: "claimPoolReserve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "poolManager", type: "address" },
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "claimed", type: "uint256" }],
  },
  {
    type: "event",
    name: "PoolReserveClaimed",
    inputs: [
      { name: "poolManager", type: "address", indexed: true },
      { name: "asset", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
] as const;
