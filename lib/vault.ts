/**
 * Yield vault display logic. `isTestStrategy` has no on-chain source —
 * BitVYieldVault.strategy() only returns an address, and there is no
 * on-chain flag distinguishing TestYieldStrategy from a production
 * strategy (see contracts/src/vault/TestYieldStrategy.sol's own NatSpec:
 * "NON-PRODUCTION, TEST/DEVELOPMENT ONLY"). BitV's own deployment
 * records (services/contracts/addresses.ts's `yieldVaults` registry)
 * are therefore the only source of truth for this label — never
 * inferred from contract state.
 */
export function getStrategyLabel(isTestStrategy: boolean | undefined): string {
  if (isTestStrategy === undefined) return "Unavailable";
  return isTestStrategy
    ? "Test strategy — non-production, generates no real yield"
    : "Production strategy";
}

export function getPerformanceLabel(isTestStrategy: boolean | undefined): string {
  if (isTestStrategy === undefined) return "Unavailable";
  return isTestStrategy
    ? "Not applicable — this vault's strategy is test/non-production and its reported growth does not reflect real yield"
    : "Estimated from on-chain share price growth";
}
