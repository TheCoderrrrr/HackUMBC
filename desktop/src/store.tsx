import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { APIError, api } from "./api/client";
import type { Evaluation, FinancialProfile, Health, PlanningPreference, PlanStyles, Scenario, StoredProfile } from "./api/types";
import { peekProfileKey } from "./data/profileKey";
import { buildDisplay, type DataMode, type Display } from "./data/display";
import { loadSavedEvaluation, peekSavedEvaluation, savedProfiles, type Preset } from "./data/saved";

export interface Loaded {
  evaluation: Evaluation;
  mode: DataMode;
}

export type Load =
  | { status: "idle" }
  | { status: "loading"; previous?: Loaded }
  | { status: "loaded"; loaded: Loaded }
  | { status: "failed"; previous?: Loaded; error: unknown };

export type Tab = "overview" | "plan" | "explore" | "funds" | "learn";
export type StyleLoad = { status: "idle" | "loading" } | { status: "loaded"; data: PlanStyles } | { status: "failed"; error: unknown };
/** Sections of Your plan, in tab order. "debt" only shows when the profile has debt. */
export type PlanSection = "month" | "saving" | "debt" | "emergency" | "fund";
/** A drawer: the whole-plan explanation, reference panels, or one section's "Why". */
export type Drawer = "explanation" | "snapshot" | "assumptions" | { why: PlanSection } | null;
export type Connection = "checking" | "online" | "offline" | "disabled";

interface Store {
  profiles: FinancialProfile[];
  profile: FinancialProfile;
  selectProfile: (id: string) => void;
  tab: Tab;
  setTab: (tab: Tab) => void;
  drawer: Drawer;
  setDrawer: (drawer: Drawer) => void;
  load: Load;
  display: Display | null;
  dataMode: DataMode;
  isLoading: boolean;
  retryable: boolean;
  liveEnabled: boolean;
  setLiveEnabled: (enabled: boolean) => void;
  connection: Connection;
  health: Health | null;
  refresh: () => void;
  checkConnection: () => void;
  evaluateScenario: (scenario: Scenario) => Promise<Evaluation>;
  savedPreset: (preset: Preset) => Promise<Evaluation | undefined>;
  /** The plan style applied to every evaluation of this profile. */
  style: PlanningPreference;
  /** True once the user picked a style for this profile. */
  styleChosen: boolean;
  setStyle: (style: PlanningPreference) => void;
  /** Saved (offline) results use the profile's default style; false when the chosen style differs. */
  savedMatchesStyle: boolean;
  planStyles: StyleLoad;
  /** Getting started: opens by itself once per browser, and anytime from the sidebar. */
  guideOpen: boolean;
  openGuide: () => void;
  closeGuide: () => void;
  /** The plan-style panel (choose and compare styles); open from Your plan or the sidebar. */
  styleOpen: boolean;
  openStyle: () => void;
  closeStyle: () => void;
  /** A scenario another view asks Explore to run next (from a Learn lesson). */
  pendingScenario: Scenario | null;
  setPendingScenario: (scenario: Scenario | null) => void;
  /** People the user added with their own numbers (stored in Tiger Data under their anonymous key). */
  mine: StoredProfile[];
  /** Adds or replaces one of them and selects it. */
  upsertMine: (stored: StoredProfile) => void;
  /** Forgets one of them (after it was erased on the server) and selects a demo profile. */
  removeMine: (profileID: string) => void;
  /** The numbers form: null when closed, else the person being edited (null ID = adding someone new). */
  numbers: { id: string | null } | null;
  numbersOpen: boolean;
  openNumbers: (profileID: string | null) => void;
  closeNumbers: () => void;
  /** The open tab inside Your plan. */
  planSection: PlanSection;
  setPlanSection: (section: PlanSection) => void;
  /** Opens Your plan at a section and brings it into view (from Overview, Learn or the guide). */
  openPlan: (section: PlanSection) => void;
  /** Changes whenever openPlan asks Your plan to scroll its tabs into view. */
  planJump: number;
}

const StoreContext = createContext<Store | null>(null);

/** The profile ID the backend gives the user's own numbers. */
export const isPersonal = (profileID: string) => profileID === "me" || profileID.startsWith("u-");
const MINE_CACHE = "arm:myProfiles";
export const MAX_PEOPLE = 10;
const GUIDE_SEEN = "arm:guideSeen";

function cacheMine(list: StoredProfile[]) {
  try {
    localStorage.setItem(MINE_CACHE, JSON.stringify(list));
  } catch {
    // Storage unavailable: the list still loads from Tiger Data next time.
  }
}

const current = (load: Load): Loaded | undefined =>
  load.status === "loaded" ? load.loaded : load.status === "idle" ? undefined : load.previous;

function stored<T extends string>(key: string, fallback: T): T {
  return (localStorage.getItem(key) as T | null) ?? fallback;
}

export function StoreProvider({ children }: { children: ReactNode }) {
  // People with their own numbers: a local copy for instant start, refreshed from Tiger Data when live.
  const [mine, setMineState] = useState<StoredProfile[]>(() => {
    try {
      const cached = JSON.parse(localStorage.getItem(MINE_CACHE) ?? "[]");
      return Array.isArray(cached) ? (cached as StoredProfile[]) : [];
    } catch {
      return [];
    }
  });
  const [numbers, setNumbers] = useState<{ id: string | null } | null>(null);
  const profiles = useMemo(() => [...savedProfiles, ...mine.map((m) => m.profile)], [mine]);
  const [profileID, setProfileID] = useState(() => {
    const id: string = stored<string>("profile", "morgan");
    return isPersonal(id) || savedProfiles.some((p) => p.id === id) ? id : savedProfiles[0].id;
  });
  const [tab, setTab] = useState<Tab>(() => {
    const saved = localStorage.getItem("tab");
    return saved === "plan" || saved === "explore" || saved === "funds" ? saved : "overview";
  });
  const [drawer, setDrawer] = useState<Drawer>(null);
  const [liveEnabled, setLiveEnabledState] = useState(() => stored("live", "on") === "on");
  const [load, setLoad] = useState<Load>({ status: "idle" });
  const [connection, setConnection] = useState<Connection>("checking");
  const [health, setHealth] = useState<Health | null>(null);

  const generation = useRef(0);
  const inflight = useRef<AbortController | null>(null);
  const lastLive = useRef(new Map<string, Loaded>());
  const lastDecision = useRef<{ profileID: string; decisionID: string } | null>(null);

  const baseProfile = profiles.find((p) => p.id === profileID) ?? profiles[0];

  const upsertMine = useCallback((next: StoredProfile) => {
    const id = next.profile.id;
    lastLive.current.delete(id);
    setMineState((list) => {
      const updated = list.some((m) => m.profile.id === id)
        ? list.map((m) => (m.profile.id === id ? next : m))
        : [...list, next];
      cacheMine(updated);
      return updated;
    });
    setProfileID(id);
    localStorage.setItem("profile", id);
  }, []);

  const removeMine = useCallback((id: string) => {
    lastLive.current.delete(id);
    setMineState((list) => {
      const updated = list.filter((m) => m.profile.id !== id);
      cacheMine(updated);
      return updated;
    });
    setProfileID((current) => (current === id ? savedProfiles[0].id : current));
    localStorage.setItem("profile", savedProfiles[0].id);
  }, []);

  // With live calculation on, the list stored in Tiger Data wins over the local copy.
  useEffect(() => {
    const key = peekProfileKey();
    if (!key || !liveEnabled) return;
    const controller = new AbortController();
    api.profiles.list(key, controller.signal)
      .then(({ profiles: remote }) => {
        setMineState(remote);
        cacheMine(remote);
      })
      .catch(() => {
        // Offline or database off: keep the local copy.
      });
    return () => controller.abort();
  }, [liveEnabled]);

  // A selected personal profile that no longer exists falls back to the first demo profile.
  const selectedMissing = isPersonal(profileID) && !mine.some((m) => m.profile.id === profileID);
  const [styles, setStyles] = useState<Record<string, PlanningPreference>>(() => {
    const out: Record<string, PlanningPreference> = {};
    for (const p of profiles) {
      const value = localStorage.getItem(`style:${p.id}`);
      if (value === "balanced" || value === "cash_security" || value === "debt_reduction") out[p.id] = value;
    }
    return out;
  });
  const styleChosen = profileID in styles;
  const style: PlanningPreference = styles[profileID] ?? baseProfile.planning_preference ?? "balanced";
  // Every evaluation, preset and saved run uses the profile with the chosen style applied.
  const profile = useMemo(() => ({ ...baseProfile, planning_preference: style }), [baseProfile, style]);
  const [guideOpen, setGuideOpen] = useState(() => localStorage.getItem(GUIDE_SEEN) === null);
  const [styleOpen, setStyleOpen] = useState(false);
  const [pendingScenario, setPendingScenario] = useState<Scenario | null>(null);
  const [planSection, setPlanSection] = useState<PlanSection>("month");
  const [planJump, setPlanJump] = useState(0);
  const openPlan = useCallback((section: PlanSection) => {
    setPlanSection(section);
    setTab("plan");
    setPlanJump((n) => n + 1);
  }, []);
  const [planStyles, setPlanStyles] = useState<StyleLoad>({ status: "idle" });
  const styleCache = useRef(new Map<string, PlanStyles>());

  const setStyle = useCallback((next: PlanningPreference) => {
    localStorage.setItem(`style:${profileID}`, next);
    lastDecision.current = null;
    setStyles((prev) => ({ ...prev, [profileID]: next }));
  }, [profileID]);

  // Style comparisons don't depend on the chosen style, so they're fetched per profile and cached.
  useEffect(() => {
    const cached = styleCache.current.get(baseProfile.id);
    if (cached) {
      setPlanStyles({ status: "loaded", data: cached });
      return;
    }
    if (!liveEnabled) {
      setPlanStyles({ status: "idle" });
      return;
    }
    const controller = new AbortController();
    setPlanStyles({ status: "loading" });
    api.planStyles(baseProfile, controller.signal)
      .then((data) => {
        styleCache.current.set(baseProfile.id, data);
        setPlanStyles({ status: "loaded", data });
      })
      .catch((error: unknown) => {
        if (!controller.signal.aborted) setPlanStyles({ status: "failed", error });
      });
    return () => controller.abort();
  }, [baseProfile, liveEnabled]);

  useEffect(() => localStorage.setItem("tab", tab), [tab]);

  const selectProfile = useCallback((id: string) => {
    setProfileID((previous) => {
      if (previous !== id) lastDecision.current = null;
      return id;
    });
    localStorage.setItem("profile", id);
  }, []);

  const setLiveEnabled = useCallback((enabled: boolean) => {
    localStorage.setItem("live", enabled ? "on" : "off");
    lastLive.current.clear();
    lastDecision.current = null;
    setLiveEnabledState(enabled);
  }, []);

  const checkConnection = useCallback(() => {
    if (!liveEnabled) {
      setConnection("disabled");
      return;
    }
    setConnection("checking");
    api
      .health()
      .then((h) => {
        setHealth(h);
        setConnection("online");
      })
      .catch(() => setConnection("offline"));
  }, [liveEnabled]);

  // Never blocks the first dashboard: saved data renders while this runs.
  useEffect(checkConnection, [checkConnection]);

  const refresh = useCallback(() => {
    generation.current += 1;
    const token = generation.current;
    inflight.current?.abort();
    const id = profile.id;

    const asSaved = (evaluation?: Evaluation): Loaded | undefined => (evaluation ? { evaluation, mode: "saved" } : undefined);
    const live = lastLive.current.get(id);
    const savedNow = asSaved(peekSavedEvaluation(id));
    const previous: Loaded | undefined = live ? { ...live, mode: "lastLive" } : savedNow;

    if (!liveEnabled) {
      if (savedNow) {
        setLoad({ status: "loaded", loaded: savedNow });
        return;
      }
      setLoad({ status: "loading" });
      void loadSavedEvaluation(id).then((evaluation) => {
        if (token !== generation.current) return;
        const saved = asSaved(evaluation);
        setLoad(saved ? { status: "loaded", loaded: saved } : { status: "idle" });
      });
      return;
    }
    setLoad({ status: "loading", previous });
    // The saved result (a separate chunk) fills in behind the live request the first time.
    if (!previous) {
      void loadSavedEvaluation(id).then((evaluation) => {
        const saved = asSaved(evaluation);
        if (token !== generation.current || !saved) return;
        setLoad((cur) => (cur.status === "loading" || cur.status === "failed") && !cur.previous ? { ...cur, previous: saved } : cur);
      });
    }

    const controller = new AbortController();
    inflight.current = controller;
    const previousID = lastDecision.current?.profileID === id ? lastDecision.current.decisionID : null;
    api
      .evaluate({ profile, scenario: null, previous_decision_id: previousID }, controller.signal)
      .then((evaluation) => {
        if (token !== generation.current || evaluation.profile_id !== id) return;
        const loaded: Loaded = { evaluation, mode: "live" };
        lastLive.current.set(id, loaded);
        lastDecision.current = { profileID: id, decisionID: evaluation.decision_summary.decision_id };
        setLoad({ status: "loaded", loaded });
        setConnection("online");
      })
      .catch((error: unknown) => {
        if (token !== generation.current) return;
        if (error instanceof APIError && error.kind === "cancelled") return;
        if (error instanceof APIError && (error.kind === "unreachable" || error.kind === "timedOut")) {
          setConnection("offline");
        }
        setLoad((cur) => ({ status: "failed", previous: cur.status === "loading" ? cur.previous ?? previous : previous, error }));
      });
  }, [profile, liveEnabled]);

  useEffect(() => {
    refresh();
    return () => inflight.current?.abort();
  }, [refresh]);

  const evaluateScenario = useCallback(
    async (scenario: Scenario) => {
      if (!liveEnabled) throw new APIError("unreachable");
      const id = profile.id;
      const previousID = lastDecision.current?.profileID === id ? lastDecision.current.decisionID : null;
      const evaluation = await api.evaluate({ profile, scenario, previous_decision_id: previousID });
      if (evaluation.profile_id === id) {
        lastDecision.current = { profileID: id, decisionID: evaluation.decision_summary.decision_id };
      }
      return evaluation;
    },
    [profile, liveEnabled],
  );

  const shown = current(load);
  const display = useMemo(
    () => (shown && shown.evaluation.profile_id === profile.id ? buildDisplay(profile, shown.evaluation, shown.mode) : null),
    [shown, profile],
  );

  const value: Store = {
    profiles,
    profile,
    selectProfile,
    tab,
    setTab,
    drawer,
    setDrawer,
    load,
    display,
    dataMode: shown?.mode ?? "saved",
    isLoading: load.status === "loading",
    retryable: load.status === "failed" && (!(load.error instanceof APIError) || load.error.retryable),
    liveEnabled,
    setLiveEnabled,
    connection: liveEnabled ? connection : "disabled",
    health,
    refresh,
    checkConnection,
    evaluateScenario,
    savedPreset: (preset) => loadSavedEvaluation(profile.id, preset),
    style,
    styleChosen,
    setStyle,
    savedMatchesStyle: style === (baseProfile.planning_preference ?? "balanced"),
    planStyles,
    guideOpen,
    openGuide: () => { setStyleOpen(false); setGuideOpen(true); },
    closeGuide: () => {
      setGuideOpen(false);
      try { localStorage.setItem(GUIDE_SEEN, "1"); } catch { /* storage unavailable: it shows again next time */ }
    },
    styleOpen,
    openStyle: () => { setDrawer(null); setStyleOpen(true); },
    closeStyle: () => setStyleOpen(false),
    pendingScenario,
    setPendingScenario,
    mine,
    upsertMine,
    removeMine,
    numbers: numbers ?? (selectedMissing ? { id: null } : null),
    numbersOpen: numbers !== null || selectedMissing,
    // The form replaces the page it opens on; Funds doesn't show it, so opening it from there moves to Overview.
    openNumbers: (id: string | null) => {
      setNumbers({ id });
      setTab((t) => (t === "funds" ? "overview" : t));
    },
    closeNumbers: () => {
      setNumbers(null);
      if (selectedMissing) {
        setProfileID(savedProfiles[0].id);
        localStorage.setItem("profile", savedProfiles[0].id);
      }
    },
    planSection,
    setPlanSection,
    openPlan,
    planJump,
  };

  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>;
}

export function useStore(): Store {
  const store = useContext(StoreContext);
  if (!store) throw new Error("useStore outside StoreProvider");
  return store;
}
