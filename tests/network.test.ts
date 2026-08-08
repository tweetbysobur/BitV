import { describe, expect, it } from "vitest";
import { deriveWalletConnectionState } from "@/lib/network";

const MONAD_TESTNET_CHAIN_ID = 10143;

describe("wallet/network state derivation", () => {
  it("is disconnected when there's no active connection", () => {
    expect(
      deriveWalletConnectionState({
        isConnected: false,
        isConnecting: false,
        chainId: undefined,
        expectedChainId: MONAD_TESTNET_CHAIN_ID,
      }),
    ).toBe("disconnected");
  });

  it("is connecting while a connection is being established", () => {
    expect(
      deriveWalletConnectionState({
        isConnected: false,
        isConnecting: true,
        chainId: undefined,
        expectedChainId: MONAD_TESTNET_CHAIN_ID,
      }),
    ).toBe("connecting");
  });

  it("is unsupported-network when connected but no chain id is reported", () => {
    expect(
      deriveWalletConnectionState({
        isConnected: true,
        isConnecting: false,
        chainId: undefined,
        expectedChainId: MONAD_TESTNET_CHAIN_ID,
      }),
    ).toBe("unsupported-network");
  });

  it("is wrong-network when connected to a different chain (e.g. Ethereum mainnet)", () => {
    expect(
      deriveWalletConnectionState({
        isConnected: true,
        isConnecting: false,
        chainId: 1,
        expectedChainId: MONAD_TESTNET_CHAIN_ID,
      }),
    ).toBe("wrong-network");
  });

  it("is connected only when connected to Monad Testnet specifically", () => {
    expect(
      deriveWalletConnectionState({
        isConnected: true,
        isConnecting: false,
        chainId: MONAD_TESTNET_CHAIN_ID,
        expectedChainId: MONAD_TESTNET_CHAIN_ID,
      }),
    ).toBe("connected");
  });
});
