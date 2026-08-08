/**
 * Cleanverse configuration boundary.
 *
 * No validator address is hardcoded here — Cleanverse's real
 * IAPassComplianceValidator deployment address on Monad Testnet is not
 * confirmed in this environment (see docs/cleanverse-integration.md). Do
 * not fill `NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS` with a guessed
 * address.
 */
export const cleanverseConfig = {
  /** Cleanverse IAPassComplianceValidator address on Monad Testnet. Public — it's a contract address, safe to read client-side. */
  validatorAddress: process.env.NEXT_PUBLIC_CLEANVERSE_VALIDATOR_ADDRESS as `0x${string}` | undefined,
  /** Network Cleanverse's validator is deployed to. Currently only Monad Testnet is in scope for BitV. */
  network: "monad-testnet" as const,
  /** Server-only Cleanverse API base URL / key — see services/cleanverse and .env.example. Never NEXT_PUBLIC_. */
  api: {
    baseUrl: process.env.CLEANVERSE_API_BASE_URL,
    hasApiKey: Boolean(process.env.CLEANVERSE_API_KEY),
  },
};
