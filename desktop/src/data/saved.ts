import type { Evaluation, FinancialProfile } from "../api/types";

// Saved results shown before (or without) a live calculation. Eric's offline bundle is
// preferred once it exists in the iOS resources; until then the contract examples, which are
// real engine responses, stand in for the `original` preset.
//
// Only the small index files (manifest, profiles) ship in the main bundle. Each saved result is
// its own chunk, fetched the first time a profile or preset needs it and then cached, so the
// first page load doesn't download every demo evaluation.

export type Preset = "original" | "retire-plus-two" | "contribution-plus-one";

interface Manifest {
  schema_version: string;
  profiles_file: string;
  default_profile_ids: string[];
  artifacts: { profile_id: string; preset_id: Preset; filename: string; kind: "standard" | "demonstration" }[];
}

const DEMO = "../../../ios/AdaptiveRetirement/Resources/Demo/";
const indexFiles = import.meta.glob("../../../ios/AdaptiveRetirement/Resources/Demo/{manifest,profiles}.json", {
  eager: true,
  import: "default",
}) as Record<string, unknown>;
const artifactLoaders = import.meta.glob("../../../ios/AdaptiveRetirement/Resources/Demo/*.json", {
  import: "default",
}) as Record<string, () => Promise<unknown>>;
const exampleProfilesFile = import.meta.glob("../../../contracts/examples/demo-profiles.response.json", {
  eager: true,
  import: "default",
}) as Record<string, { profiles: FinancialProfile[] }>;
const exampleLoaders = import.meta.glob("../../../contracts/examples/evaluate-*.response.json", {
  import: "default",
}) as Record<string, () => Promise<unknown>>;

const manifest = indexFiles[`${DEMO}manifest.json`] as Manifest | undefined;
const bundleProfiles = manifest
  ? (indexFiles[`${DEMO}${manifest.profiles_file}`] as { profiles: FinancialProfile[] } | undefined)?.profiles
  : undefined;

export const usesBundle = Boolean(manifest && bundleProfiles);

const exampleProfiles = Object.values(exampleProfilesFile)[0]?.profiles ?? [];
const allProfiles: FinancialProfile[] = bundleProfiles ?? exampleProfiles;
const defaultIDs = manifest?.default_profile_ids ?? ["morgan", "jordan", "casey"];

/** Profiles for the picker, in the bundle's order. */
export const savedProfiles: FinancialProfile[] = defaultIDs
  .map((id) => allProfiles.find((p) => p.id === id))
  .filter((p): p is FinancialProfile => Boolean(p));

const cache = new Map<string, Promise<Evaluation | undefined>>();
const settled = new Map<string, Evaluation | undefined>();

async function fetchSaved(profileID: string, preset: Preset): Promise<Evaluation | undefined> {
  if (manifest) {
    const entry = manifest.artifacts.find((a) => a.profile_id === profileID && a.preset_id === preset);
    const load = entry ? artifactLoaders[`${DEMO}${entry.filename}`] : undefined;
    if (!load) return undefined;
    const artifact = (await load()) as { profile_id: string; evaluation: Evaluation };
    // Never show another profile's numbers, even if a file were misnamed.
    return artifact.profile_id === profileID && artifact.evaluation.profile_id === profileID ? artifact.evaluation : undefined;
  }
  if (preset !== "original") return undefined;
  const load = exampleLoaders[`../../../contracts/examples/evaluate-${profileID}.response.json`];
  return load ? ((await load()) as Evaluation) : undefined;
}

/** Exact saved evaluation, or undefined. Never interpolated. Loaded once, then cached. */
export function loadSavedEvaluation(profileID: string, preset: Preset = "original"): Promise<Evaluation | undefined> {
  const key = `${profileID}/${preset}`;
  let pending = cache.get(key);
  if (!pending) {
    pending = fetchSaved(profileID, preset).then(
      (evaluation) => {
        settled.set(key, evaluation);
        return evaluation;
      },
      () => {
        cache.delete(key); // allow a retry if the chunk failed to load
        return undefined;
      },
    );
    cache.set(key, pending);
  }
  return pending;
}

/** The saved evaluation if it has already loaded; `undefined` otherwise (not yet loaded or none). */
export function peekSavedEvaluation(profileID: string, preset: Preset = "original"): Evaluation | undefined {
  return settled.get(`${profileID}/${preset}`);
}
