/**
 * Chart helpers. All inputs are yearly values sampled from the engine's projection
 * (`yearlyBalances`: the point at month 12·y, the same rule as the backend's yearly roll-ups).
 * Nothing here projects or simulates money; it only compares and searches engine values.
 */

/** Plan minus comparison at one index, or null if either side has no value there. */
export function gapAt(plan: number[], other: number[], index: number): number | null {
  const a = plan[index];
  const b = other[index];
  return a === undefined || b === undefined ? null : a - b;
}

/** First index whose value is at or above `goal`, or null if the series never reaches it. */
export function firstReach(values: number[], goal: number): number | null {
  if (!(goal > 0)) return null;
  const i = values.findIndex((v) => v >= goal);
  return i === -1 ? null : i;
}

/** How many years sooner `plan` reaches the goal than `other`; null when either never reaches it. */
export function yearsSooner(plan: number[], other: number[], goal: number): number | null {
  const a = firstReach(plan, goal);
  const b = firstReach(other, goal);
  return a === null || b === null ? null : b - a;
}

const PRESET_DOLLARS = [100_000, 250_000, 500_000, 750_000, 1_000_000, 1_500_000, 2_000_000, 3_000_000, 5_000_000];

/**
 * Up to three round goal amounts (in cents) worth trying for this projection: the largest
 * presets the plan reaches by retirement, plus the next one up as a stretch goal.
 */
export function goalPresets(finalPlanCents: number): number[] {
  const final = finalPlanCents / 100;
  const reached = PRESET_DOLLARS.filter((d) => d <= final);
  const stretch = PRESET_DOLLARS.find((d) => d > final);
  const picks = [...reached.slice(-2), ...(stretch ? [stretch] : [])];
  return picks.map((d) => d * 100);
}

/** Round axis ticks (in cents) from 0 up to at least `max`, 3–5 steps of 1/2/2.5/5 × 10^n. */
export function niceTicks(maxCents: number): number[] {
  if (!(maxCents > 0)) return [0];
  const raw = maxCents / 4;
  const magnitude = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * magnitude).find((s) => s >= raw) ?? raw;
  const ticks: number[] = [];
  for (let v = 0; v < maxCents + step; v += step) ticks.push(Math.round(v));
  return ticks;
}

/** Parses a typed dollar amount ("1,200,000", "$1.2m", "800k") to cents; null if not a positive amount. */
export function parseGoal(text: string): number | null {
  const t = text.trim().toLowerCase().replace(/[$,\s]/g, "");
  const m = /^(\d+(?:\.\d+)?)([km]?)$/.exec(t);
  if (!m) return null;
  const n = Number(m[1]) * (m[2] === "m" ? 1_000_000 : m[2] === "k" ? 1_000 : 1);
  return n > 0 && n <= 100_000_000 ? Math.round(n * 100) : null;
}

/** "$1.46M", "$750k", "$9.5k", "$900": compact money for axes, chips and goal labels. */
export function moneyShort(cents: number): string {
  const d = Math.round(cents) / 100;
  const sign = d < 0 ? "-" : "";
  const a = Math.abs(d);
  if (a >= 1_000_000) return `${sign}$${+(a / 1_000_000).toFixed(2)}M`;
  if (a >= 1_000) return `${sign}$${+(a / 1_000).toFixed(a >= 100_000 ? 0 : 1)}k`;
  return `${sign}$${Math.round(a)}`;
}

/**
 * Milestones placed on a yearly chart. A milestone in month m is drawn at year ceil(m / 12), the
 * first yearly point on or after it; milestones landing in the same year share one label.
 * Months of 0 (already done), null (never) or beyond the chart are left out.
 */
export function yearMarkers(milestones: { month: number | null; label: string }[], years: number): { index: number; label: string }[] {
  const byYear = new Map<number, string[]>();
  for (const m of milestones) {
    if (m.month === null || m.month <= 0 || m.month > years * 12) continue;
    const index = Math.ceil(m.month / 12);
    byYear.set(index, [...(byYear.get(index) ?? []), m.label]);
  }
  return [...byYear.entries()].sort(([a], [b]) => a - b).map(([index, labels]) => ({ index, label: labels.join(" · ") }));
}

