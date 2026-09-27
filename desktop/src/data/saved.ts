import type { Evaluation, FinancialProfile } from "../api/types";
import exampleProfiles from "../../../contracts/examples/demo-profiles.response.json";
import exampleMorgan from "../../../contracts/examples/evaluate-morgan.response.json";
import exampleJordan from "../../../contracts/examples/evaluate-jordan.response.json";
import exampleCasey from "../../../contracts/examples/evaluate-casey.response.json";

// Saved results shown before (or without) a live calculation. Eric's offline bundle is
// preferred once it exists in the iOS resources; until then the contract examples, which are
// real engine responses, stand in for the `original` preset.

export type Preset = "original" | "retire-plus-two" | "contribution-plus-one";

interface Manifest {
  schema_version: string;
  profiles_file: string;
  default_profile_ids: string[];
  artifacts: { profile_id: string; preset_id: Preset; filename: string; kind: "standard" | "demonstration" }[];
}

const bundleFiles = import.meta.glob("../../../ios/AdaptiveRetirement/Resources/Demo/*.json", {
  eager: true,
  import: "default",
}) as Record<string, unknown>;

function bundleFile<T>(name: string): T | undefined {
  const key = Object.keys(bundleFiles).find((path) => path.endsWith(`/${name}`));
  return key ? (bundleFiles[key] as T) : undefined;
}

const manifest = bundleFile<Manifest>("manifest.json");
const bundleProfiles = manifest
  ? bundleFile<{ profiles: FinancialProfile[] }>(manifest.profiles_file)?.profiles
  : undefined;

export const usesBundle = Boolean(manifest && bundleProfiles);

const examples: Record<string, Evaluation> = {
  morgan: exampleMorgan as unknown as Evaluation,
  jordan: exampleJordan as unknown as Evaluation,
  casey: exampleCasey as unknown as Evaluation,
};

const allProfiles: FinancialProfile[] = bundleProfiles ?? (exampleProfiles.profiles as unknown as FinancialProfile[]);
const defaultIDs = manifest?.default_profile_ids ?? ["morgan", "jordan", "casey"];

/** Profiles for the picker, in the bundle's order. */
export const savedProfiles: FinancialProfile[] = defaultIDs
  .map((id) => allProfiles.find((p) => p.id === id))
  .filter((p): p is FinancialProfile => Boolean(p));

/** Exact saved evaluation, or undefined. Never interpolated. */
export function savedEvaluation(profileID: string, preset: Preset = "original"): Evaluation | undefined {
  if (manifest) {
    const entry = manifest.artifacts.find((a) => a.profile_id === profileID && a.preset_id === preset);
    const artifact = entry ? bundleFile<{ profile_id: string; evaluation: Evaluation }>(entry.filename) : undefined;
    if (artifact && artifact.profile_id === profileID && artifact.evaluation.profile_id === profileID) {
      return artifact.evaluation;
    }
    return undefined;
  }
  return preset === "original" ? examples[profileID] : undefined;
}
