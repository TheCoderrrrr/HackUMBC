/** Display helpers for the fund shortlist; all inputs come from /v1/funds/shortlist. */

/** "State Street Target Retirement 2055 Fund, Class K" → "State Street Target Retirement 2055". */
export const shortName = (name: string) => name.replace(/,\s*Class.*$/i, "").replace(/\s+Fund$/i, "");

/**
 * The value to mark as best in a comparison row (lowest for costs, highest otherwise), or
 * undefined when fewer than two funds report it or they're all the same.
 */
export function bestInRow(values: (number | undefined)[], lowest = false): number | undefined {
  const known = values.filter((v): v is number => v !== undefined);
  if (known.length < 2 || known.every((v) => v === known[0])) return undefined;
  return lowest ? Math.min(...known) : Math.max(...known);
}

/** The overall match score: each 0–1 part times its weight, summed (the backend's formula). */
export function weightedScore(parts: Record<string, number>, weights: Record<string, number>): number {
  return Object.entries(weights).reduce((sum, [key, weight]) => sum + weight * (parts[key] ?? 0), 0);
}
