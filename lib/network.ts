/**
 * Wallet/network connection status derivation — pure function, no wagmi
 * dependency, so it's testable without mocking a wallet provider. The
 * hook that calls this (hooks/useWalletStatus.ts) supplies real wagmi
 * state.
 */
export type WalletConnectionState =
  | "disconnected"
  | "connecting"
  | "connected"
  | "wrong-network"
  | "unsupported-network";

export interface WalletConnectionInputs {
  isConnected: boolean;
  isConnecting: boolean;
  /** Current chain id from the connector, or `undefined` if the wallet
   * hasn't reported one (or reports a chain wagmi doesn't recognize). */
  chainId: number | undefined;
  /** BitV's only supported network — Monad Testnet, per config/chains.ts.
   * Never widen this to include a mainnet BitV doesn't actually
   * support. */
  expectedChainId: number;
}

export function deriveWalletConnectionState(inputs: WalletConnectionInputs): WalletConnectionState {
  if (inputs.isConnecting) return "connecting";
  if (!inputs.isConnected) return "disconnected";
  if (inputs.chainId === undefined) return "unsupported-network";
  if (inputs.chainId !== inputs.expectedChainId) return "wrong-network";
  return "connected";
}
