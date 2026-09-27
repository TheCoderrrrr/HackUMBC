import { lazy, Suspense, useCallback, useState } from "react";
import { Avatar, Icon, LiveStatus, PROFILE_SUBTITLE } from "./components/ui";
import { Drawers } from "./views/Drawers";
import { Guide } from "./views/Guide";
import { Overview } from "./views/Overview";
import { Plan } from "./views/Plan";
import { errorMessage } from "./api/client";
import { STYLE_INFO } from "./data/styles";
import { MY_ID, useStore, type Tab } from "./store";

// Pages opened less often load on demand, keeping the first download small.
const Explore = lazy(() => import("./views/Explore").then((m) => ({ default: m.Explore })));
const Funds = lazy(() => import("./views/Funds").then((m) => ({ default: m.Funds })));
const Learn = lazy(() => import("./views/Learn").then((m) => ({ default: m.Learn })));
const Chat = lazy(() => import("./views/Chat").then((m) => ({ default: m.Chat })));
const YourNumbers = lazy(() => import("./views/YourNumbers").then((m) => ({ default: m.YourNumbers })));

/** Pages, grouped the way people use them: their money, planning ahead, learning. */
const PAGES: { id: Tab; title: string; icon: string; group: string; description: (first: string) => string }[] = [
  { id: "overview", title: "Overview", icon: "overview", group: "Your money",
    description: (first) => `${first}, here's where you stand today and what to do next.` },
  { id: "plan", title: "Your plan", icon: "plan", group: "Your money",
    description: () => "Where your plan is heading, then one topic at a time." },
  { id: "explore", title: "Explore", icon: "explore", group: "Plan ahead",
    description: () => "Try a different retirement age or contribution and compare the results." },
  { id: "funds", title: "Fund shortlist", icon: "funds", group: "Plan ahead",
    description: () => "Find a target-date fund that fits your timeline and comfort with risk." },
  { id: "learn", title: "Learn", icon: "learn", group: "Learn",
    description: () => "Short lessons on the ideas behind your plan, each applied to your numbers." },
];
const GROUPS = ["Your money", "Plan ahead", "Learn"] as const;

export function App() {
  const { tab, display, profile, load, setDrawer, dataMode, savedMatchesStyle, style, numbersOpen } = useStore();
  const showNumbers = numbersOpen && tab !== "funds";
  const page = PAGES.find((p) => p.id === tab) ?? PAGES[0];
  const [chatOpen, setChatOpen] = useState(false);
  const [chatLoaded, setChatLoaded] = useState(false);
  const closeChat = useCallback(() => setChatOpen(false), []);

  return (
    <div className="app">
      <Sidebar />
      <main className="main">
        <div className="main-inner">
          <header className="topbar">
            <div>
              <h1>{showNumbers ? "Your numbers" : page.title}</h1>
              <p className="page-desc">{showNumbers
                ? "Enter your own finances; ARM builds your plan from them."
                : page.description(profile.name.split(" ")[0])}</p>
            </div>
            <div className="topbar-actions">
              <LiveStatus />
              {display && !showNumbers && tab !== "funds" && tab !== "learn" && (
                <button className="pill neutral" onClick={() => setDrawer("explanation")}>
                  <Icon name="why" /> Why this plan?
                </button>
              )}
            </div>
          </header>

          {load.status === "failed" && display && tab !== "funds" && (
            <div className="banner fade-in">
              <span>{errorMessage(load.error)} Showing the {load.previous?.mode === "lastLive" ? "last live" : "saved"} result.</span>
            </div>
          )}

          {display && dataMode === "saved" && !savedMatchesStyle && tab !== "funds" && tab !== "learn" && (
            <div className="banner fade-in">
              <span>This saved result uses the Balanced style. Turn on live calculation to see {STYLE_INFO[style].label}.</span>
            </div>
          )}

          <Suspense fallback={<PageLoading />}>
            {tab === "funds" && <Funds />}
            {showNumbers && <YourNumbers />}
            {!showNumbers && !display && tab !== "funds" && <EmptyState />}
            {!showNumbers && display && tab === "overview" && <Overview display={display} />}
            {!showNumbers && display && tab === "plan" && <Plan display={display} />}
            {!showNumbers && display && tab === "explore" && <Explore display={display} />}
            {!showNumbers && display && tab === "learn" && <Learn display={display} />}
          </Suspense>
        </div>
      </main>
      {display && <Drawers display={display} />}
      <button className="chat-launcher" type="button" onClick={() => { setChatLoaded(true); setChatOpen(true); }} aria-label="Ask a retirement question" aria-haspopup="dialog" aria-expanded={chatOpen}>
        <Icon name="chat" /> Ask
      </button>
      {chatLoaded && <Suspense fallback={null}><Chat open={chatOpen} onClose={closeChat} /></Suspense>}
      <Guide />
    </div>
  );
}

function Sidebar() {
  const { tab, setTab, profiles, profile, selectProfile, connection, liveEnabled, setLiveEnabled, checkConnection, style, openGuide, mine, openNumbers } = useStore();
  const connectionText = {
    online: "Backend connected",
    offline: "Backend unreachable",
    checking: "Checking backend…",
    disabled: "Saved data only",
  }[connection];

  return (
    <aside className="sidebar">
      <div className="wordmark">
        ARM
        <small>Adaptive Retirement Management</small>
      </div>

      <nav className="nav" aria-label="Pages">
        {GROUPS.map((group) => (
          <div key={group} className="nav-group" role="group" aria-label={group}>
            <p className="eyebrow nav-group-title">{group}</p>
            {PAGES.filter((p) => p.group === group).map((p) => (
              <button key={p.id} aria-current={tab === p.id ? "page" : undefined} onClick={() => setTab(p.id)}>
                <Icon name={p.icon} /> {p.title}
              </button>
            ))}
            {group === "Learn" && (
              <button onClick={openGuide}><Icon name="play" /> Getting started</button>
            )}
          </div>
        ))}
      </nav>

      <button className="style-chip" onClick={openGuide} title="Change plan style">
        <span className="eyebrow" style={{ padding: 0 }}>Plan style</span>
        <span className="style-chip-row">
          <i style={{ background: STYLE_INFO[style].color }} />
          <span>{STYLE_INFO[style].label}</span>
          <span className="link" style={{ marginLeft: "auto", fontSize: 12 }}>Change</span>
        </span>
      </button>

      <div className="profiles">
        <p className="eyebrow" style={{ marginBottom: 6 }}>Customer</p>
        {profiles.map((p) => (
          <button key={p.id} className="profile-btn" aria-pressed={p.id === profile.id} onClick={() => selectProfile(p.id)}>
            <Avatar id={p.id} name={p.name} size={38} />
            <span>
              <span className="name" style={{ display: "block" }}>{p.name}</span>
              <span className="sub">{p.id === MY_ID ? "Your numbers" : PROFILE_SUBTITLE[p.id] ?? `Age ${p.age}`}</span>
            </span>
          </button>
        ))}
        <button className="add-numbers" onClick={() => { if (mine) selectProfile(MY_ID); openNumbers(); }}>
          <Icon name={mine ? "sliders" : "person"} size={15} /> {mine ? "Edit your numbers" : "Add your numbers"}
        </button>
      </div>

      <div className="sidebar-footer">
        <div className="toggle">
          Live calculation
          <button className="switch" role="switch" aria-checked={liveEnabled} aria-label="Live calculation"
            onClick={() => setLiveEnabled(!liveEnabled)} />
        </div>
        <button className="conn" onClick={checkConnection} title="Check again">
          <span className={`dot ${connection === "online" ? "on" : connection === "offline" ? "off" : connection === "checking" ? "checking" : ""}`} />
          {connectionText}
        </button>
        <p className="fine">Fictional customers · synthetic data · not affiliated with or endorsed by T. Rowe Price.</p>
      </div>
    </aside>
  );
}

function EmptyState() {
  const { load, refresh } = useStore();
  return (
    <div className="glass card" style={{ maxWidth: 520, marginTop: 40 }}>
      <p className="h-card">{load.status === "loading" ? "Calculating your plan…" : "No saved result for this customer"}</p>
      <p className="body" style={{ marginTop: 8 }}>
        {load.status === "failed"
          ? `${errorMessage(load.error)} Turn on the backend and try again.`
          : "Results appear after the backend calculates them."}
      </p>
      {load.status === "loading" ? <span className="spinner" style={{ marginTop: 16, display: "block" }} />
        : <button className="btn-primary" style={{ marginTop: 18 }} onClick={refresh}>Try again</button>}
    </div>
  );
}

function PageLoading() {
  return <p className="caption" style={{ marginTop: 32 }} role="status"><span className="spinner" /> Loading…</p>;
}
