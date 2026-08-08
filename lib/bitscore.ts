/**
 * BitScore tier mapping — reflects the CURRENT 0-100 scale
 * (contracts/src/core/BitScoreManager.sol, docs/bitscore-specification.md),
 * not the earlier 0-1000 model. Score is BitV's own protocol-native risk
 * signal (never a Cleanverse primitive) — see BitScoreManager's NatSpec.
 */
export type BitScoreTier = "Restricted" | "Standard" | "Established" | "Trusted";

export interface BitScoreTierInfo {
  tier: BitScoreTier;
  min: number;
  max: number;
}

/** Exact tier bands per BitScoreManager.sol's TIER_1_FLOOR/TIER_2_FLOOR/
 * TIER_3_FLOOR constants (25/50/75) and MIN_SCORE/MAX_SCORE (0/100). */
export const BITSCORE_TIERS: readonly BitScoreTierInfo[] = [
  { tier: "Restricted", min: 0, max: 24 },
  { tier: "Standard", min: 25, max: 49 },
  { tier: "Established", min: 50, max: 74 },
  { tier: "Trusted", min: 75, max: 100 },
];

/** On-chain `getTier` already returns a 0-3 index — this array maps
 * that index directly, for display without recomputing from the raw
 * score. */
export const BITSCORE_TIER_BY_INDEX: readonly BitScoreTier[] = [
  "Restricted",
  "Standard",
  "Established",
  "Trusted",
];

export function getBitScoreTierFromScore(score: number): BitScoreTierInfo {
  if (!Number.isFinite(score) || score < 0 || score > 100) {
    throw new RangeError(`BitScore out of the 0-100 range: ${score}`);
  }
  const tier = BITSCORE_TIERS.find((t) => score >= t.min && score <= t.max);
  if (!tier) throw new RangeError(`BitScore out of the 0-100 range: ${score}`);
  return tier;
}

export function getBitScoreTierFromIndex(tierIndex: number): BitScoreTier {
  const tier = BITSCORE_TIER_BY_INDEX[tierIndex];
  if (tier === undefined) throw new RangeError(`Unknown BitScore tier index: ${tierIndex}`);
  return tier;
}
