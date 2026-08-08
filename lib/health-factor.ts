/**
 * Health factor display logic. On-chain, `healthFactorRay` is a
 * ray-scaled (1e27) uint256, with `type(uint256).max` used as the
 * "no debt" sentinel (see BitVLendingManager._accountData). This module
 * turns that raw value into a display string and a UI status bucket —
 * pure functions, no contract calls.
 */
const RAY = 10n ** 27n;
const MAX_UINT256 = 2n ** 256n - 1n;

export type HealthFactorStatus = "no-debt" | "healthy" | "warning" | "danger" | "unavailable";

/** Thresholds are BitV UI conventions, not on-chain values: liquidation
 * happens at healthFactorRay < 1 RAY (danger); "warning" gives users a
 * buffer before that point. Kept as ray-scaled bigints (never converted
 * through `Number()`, which silently loses precision past
 * `Number.MAX_SAFE_INTEGER` — RAY (1e27) already exceeds it by twelve
 * orders of magnitude, so a naive `Number(healthFactorRay) / Number(RAY)`
 * comparison can flip right at a boundary like exactly 1.5x, a real bug
 * caught during this milestone's own test run, not a hypothetical). */
const WARNING_THRESHOLD_RAY = (RAY * 3n) / 2n; // 1.5x
const DANGER_THRESHOLD_RAY = RAY; // 1.0x

export function getHealthFactorStatus(healthFactorRay: bigint | undefined): HealthFactorStatus {
  if (healthFactorRay === undefined) return "unavailable";
  if (healthFactorRay === MAX_UINT256) return "no-debt";
  if (healthFactorRay < DANGER_THRESHOLD_RAY) return "danger";
  if (healthFactorRay < WARNING_THRESHOLD_RAY) return "warning";
  return "healthy";
}

/** Formats to two decimal places using integer (bigint) arithmetic
 * throughout — see the precision note above for why `Number(ray)` must
 * never be used directly on a RAY-scaled value. */
export function formatHealthFactor(healthFactorRay: bigint | undefined): string {
  if (healthFactorRay === undefined) return "Unavailable";
  if (healthFactorRay === MAX_UINT256) return "∞"; // no outstanding debt
  const scaled = (healthFactorRay * 100n) / RAY; // hf * 100, still exact
  const whole = scaled / 100n;
  const fraction = scaled % 100n;
  return `${whole}.${fraction.toString().padStart(2, "0")}`;
}
