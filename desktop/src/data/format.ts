const whole = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
const exact = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: 2 });

/** "$35,000" */
export const money = (cents: number) => whole.format(Math.round(cents / 100));
/** "$963.80" */
export const moneyExact = (cents: number) => exact.format(cents / 100);

/** 0.05 → "5%", 0.605 → "60.5%" */
export function percent(rate: number): string {
  const value = Math.round(rate * 1000) / 10;
  return `${Number.isInteger(value) ? value.toFixed(0) : value.toFixed(1)}%`;
}

export function months(value: number): string {
  const rounded = Math.round(value * 10) / 10;
  const text = Number.isInteger(rounded) ? rounded.toFixed(0) : rounded.toFixed(1);
  return `${text} ${rounded === 1 ? "month" : "months"}`;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** Month index from the profile's as-of date → "Sep 2028". */
export function monthLabel(asOf: string, month: number): string {
  const [year, mon] = asOf.split("-").map(Number);
  const absolute = mon - 1 + month;
  return `${MONTHS[absolute % 12]} ${year + Math.floor(absolute / 12)}`;
}

/** "Sep 2027" for a plan month, or the given words for "already" (month 0) and "never within the plan" (null). */
export function when(month: number | null, asOf: string, done = "Already", never = "Not before retirement"): string {
  if (month === null) return never;
  return month === 0 ? done : monthLabel(asOf, month);
}

export function asOfLabel(asOf: string): string {
  const [year, mon, day] = asOf.split("-").map(Number);
  return `${MONTHS[mon - 1]} ${day}, ${year}`;
}
