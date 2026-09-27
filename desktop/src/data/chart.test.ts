import { describe, expect, it } from "vitest";
import { firstReach, gapAt, goalPresets, moneyShort, niceTicks, parseGoal, yearMarkers, yearsSooner } from "./chart";

describe("gapAt", () => {
  it("is plan minus comparison at the index", () => {
    expect(gapAt([100, 250, 400], [100, 200, 300], 2)).toBe(100);
    expect(gapAt([100, 150], [120, 160], 1)).toBe(-10);
  });
  it("is null past the end of either series", () => {
    expect(gapAt([1, 2, 3], [1, 2], 2)).toBeNull();
    expect(gapAt([1], [1, 2], 1)).toBeNull();
  });
});

describe("firstReach and yearsSooner", () => {
  const plan = [0, 50, 120, 200, 300];
  const habits = [0, 40, 90, 140, 210];
  it("finds the first index at or above the goal", () => {
    expect(firstReach(plan, 120)).toBe(2);
    expect(firstReach(plan, 121)).toBe(3);
    expect(firstReach(plan, 0.5)).toBe(1);
  });
  it("returns null when the goal is never reached or not positive", () => {
    expect(firstReach(plan, 301)).toBeNull();
    expect(firstReach(plan, 0)).toBeNull();
    expect(firstReach(plan, -5)).toBeNull();
  });
  it("counts years sooner, and null when either never gets there", () => {
    expect(yearsSooner(plan, habits, 200)).toBe(1); // plan year 3, habits year 4
    expect(yearsSooner(plan, habits, 50)).toBe(1); // plan year 1, habits year 2
    expect(yearsSooner(plan, habits, 40)).toBe(0); // both at year 1
    expect(yearsSooner(plan, habits, 250)).toBeNull(); // habits never reach 250
  });
});

describe("goalPresets", () => {
  it("offers the two largest reached round amounts and one stretch", () => {
    expect(goalPresets(146_256_220)).toEqual([750_000_00, 1_000_000_00, 1_500_000_00]);
  });
  it("works for small and very large balances", () => {
    expect(goalPresets(9_000_000)).toEqual([100_000_00]);
    expect(goalPresets(900_000_000)).toEqual([3_000_000_00, 5_000_000_00]);
  });
});

describe("niceTicks", () => {
  it("covers the maximum with round steps from zero", () => {
    const ticks = niceTicks(146_256_220);
    expect(ticks[0]).toBe(0);
    expect(ticks[ticks.length - 1]).toBeGreaterThanOrEqual(146_256_220);
    const step = ticks[1] - ticks[0];
    expect(ticks.every((t, i) => t === i * step)).toBe(true);
    expect([1, 2, 2.5, 5].some((m) => step / 10 ** Math.floor(Math.log10(step)) === m)).toBe(true);
    expect(ticks.length).toBeGreaterThanOrEqual(4);
    expect(ticks.length).toBeLessThanOrEqual(6);
  });
  it("handles zero", () => expect(niceTicks(0)).toEqual([0]));
});

describe("parseGoal", () => {
  it.each([
    ["1000000", 100_000_000],
    ["$1,000,000", 100_000_000],
    ["1.5m", 150_000_000],
    ["800k", 80_000_000],
    [" 250,000 ", 25_000_000],
  ])("parses %s", (text, cents) => expect(parseGoal(text)).toBe(cents));
  it.each(["", "abc", "-5", "0", "1e9", "999999999999"])("rejects %s", (text) => expect(parseGoal(text)).toBeNull());
});

describe("moneyShort", () => {
  it.each([
    [146_256_220, "$1.46M"],
    [100_000_000, "$1M"],
    [75_000_000, "$750k"],
    [950_000, "$9.5k"],
    [90_000, "$900"],
    [0, "$0"],
    [-2_500_000, "-$25k"],
  ])("%i cents → %s", (cents, text) => expect(moneyShort(cents)).toBe(text));
});

describe("yearMarkers", () => {
  it("places a milestone at the first yearly point on or after it", () => {
    expect(yearMarkers([{ month: 16, label: "Debt cleared" }], 32)).toEqual([{ index: 2, label: "Debt cleared" }]);
    expect(yearMarkers([{ month: 12, label: "A" }], 32)).toEqual([{ index: 1, label: "A" }]);
  });
  it("merges milestones in the same year so labels never overlap (Morgan: months 16 and 21)", () => {
    expect(yearMarkers([{ month: 16, label: "Debt cleared" }, { month: 21, label: "Emergency fund full" }], 32))
      .toEqual([{ index: 2, label: "Debt cleared · Emergency fund full" }]);
  });
  it("leaves out already-done, never, and past-the-chart milestones, and sorts by year", () => {
    expect(yearMarkers([
      { month: 0, label: "done" }, { month: null, label: "never" }, { month: 400, label: "late" },
      { month: 30, label: "B" }, { month: 5, label: "A" },
    ], 32)).toEqual([{ index: 1, label: "A" }, { index: 3, label: "B" }]);
  });
});

