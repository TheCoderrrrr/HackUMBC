import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { APIError, api } from "./api/client";
import type { Evaluation, FinancialProfile, Health, Scenario } from "./api/types";
import { buildDisplay, type DataMode, type Display } from "./data/display";
import { savedEvaluation, savedProfiles, type Preset } from "./data/saved";

export interface Loaded {
  evaluation: Evaluation;
  mode: DataMode;
}

export type Load =
  | { status: "idle" }
  | { status: "loading"; previous?: Loaded }
  | { status: "loaded"; loaded: Loaded }
  | { status: "failed"; previous?: Loaded; error: unknown };

export type Tab = "overview" | "plan" | "explore" | "funds";
export type Drawer = "explanation" | "snapshot" | "assumptions" | null;
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
  savedPreset: (preset: Preset) => Evaluation | undefined;
}

const StoreContext = createContext<Store | null>(null);

const current = (load: Load): Loaded | undefined =>
  load.status === "loaded" ? load.loaded : load.status === "idle" ? undefined : load.previous;

function stored<T extends string>(key: string, fallback: T): T {
  return (localStorage.getItem(key) as T | null) ?? fallback;
}

export function StoreProvider({ children }: { children: ReactNode }) {
  const profiles = savedProfiles;
  const [profileID, setProfileID] = useState(() => {
    const id = stored("profile", "morgan");
    return profiles.some((p) => p.id === id) ? id : profiles[0].id;
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

  const profile = profiles.find((p) => p.id === profileID) ?? profiles[0];

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

    const savedEval = savedEvaluation(id);
    const saved: Loaded | undefined = savedEval ? { evaluation: savedEval, mode: "saved" } : undefined;
    const live = lastLive.current.get(id);
    const previous: Loaded | undefined = live ? { ...live, mode: "lastLive" } : saved;

    if (!liveEnabled) {
      setLoad(saved ? { status: "loaded", loaded: saved } : { status: "idle" });
      return;
    }
    setLoad({ status: "loading", previous });

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
        setLoad({ status: "failed", previous, error });
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
    savedPreset: (preset) => savedEvaluation(profile.id, preset),
  };

  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>;
}

export function useStore(): Store {
  const store = useContext(StoreContext);
  if (!store) throw new Error("useStore outside StoreProvider");
  return store;
}
