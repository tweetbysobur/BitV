/**
 * Cleanverse integration boundary — CLIENT STUB.
 *
 * This is not a mock and must never be wired up to look like a working
 * integration. Every method throws until it is implemented against
 * Cleanverse's real, documented SDK/API, after the doc review described in
 * /docs/cleanverse-integration-todo.md.
 *
 * Rationale for existing at all: gives the rest of BitV (services, hooks,
 * components) one narrow module to import against, so the real
 * implementation can land later without touching call sites.
 */

const NOT_IMPLEMENTED =
  "Cleanverse integration is not implemented yet. See /docs/cleanverse-integration-todo.md.";

export const cleanverseClient = {
  getIdentity(_address: `0x${string}`): never {
    throw new Error(NOT_IMPLEMENTED);
  },
  getVerifiedAssets(_address: `0x${string}`): never {
    throw new Error(NOT_IMPLEMENTED);
  },
  /**
   * Will eventually read `IAPassComplianceValidator.complianceVerify`
   * (on-chain, via viem — see contracts/src/interfaces/external/
   * IAPassComplianceValidator.sol) for a given pool/user pair. The
   * interface itself is confirmed against the official CVI Integration
   * Guide V2 PDF; left throwing purely because the validator's deployed
   * address on Monad Testnet is still UNCONFIRMED (config/cleanverse.ts).
   */
  checkCompliance(_poolAddress: `0x${string}`, _userAddress: `0x${string}`): never {
    throw new Error(NOT_IMPLEMENTED);
  },
};
