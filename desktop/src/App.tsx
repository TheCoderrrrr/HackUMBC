import { useCallback, useState } from "react";
import { Avatar, Icon, LiveStatus, PROFILE_SUBTITLE } from "./components/ui";
import { Drawers } from "./views/Drawers";
import { Explore } from "./views/Explore";
import { Chat } from "./views/Chat";
import { Funds } from "./views/Funds";
import { Overview } from "./views/Overview";
import { Plan } from "./views/Plan";
import { errorMessage } from "./api/client";
import { useStore, type Tab } from "./store";

const TABS: { id: Tab; title: string; icon: string }[] = [
  { id: "overview", title: "Overview", icon: "overview" },
  { id: "plan", title: "Your plan", icon: "plan" },
  { id: "explore", title: "Explore", icon: "explore" },
  { id: "funds", title: "Fund shortlist", icon: "funds" },
];

export function App() {
  const { tab, display, profile, load, setDrawer } = useStore();
  const [chatOpen, setChatOpen] = useState(false);
  const closeChat = useCallback(() => setChatOpen(false), []);

  return (
    <div className="app">
      <Sidebar />
      <main className="main">
        <div className="main-inner">
          <header className="topbar">
            <h1>{tab === "overview" ? profile.name : TABS.find((t) => t.id === tab)?.title}</h1>
            <div className="topbar-actions">
              <LiveStatus />
              {display && tab !== "funds" && (
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

          {tab === "funds" && <Funds />}
          {!display && tab !== "funds" && <EmptyState />}
          {display && tab === "overview" && <Overview display={display} />}
          {display && tab === "plan" && <Plan display={display} />}
          {display && tab === "explore" && <Explore display={display} />}
        </div>
      </main>
      {display && <Drawers display={display} />}
      <button className="chat-launcher" type="button" onClick={() => setChatOpen(true)} aria-label="Ask a retirement question" aria-haspopup="dialog" aria-expanded={chatOpen}>
        <Icon name="chat" /> Ask
      </button>
      <Chat open={chatOpen} onClose={closeChat} />
    </div>
  );
}

function Sidebar() {
  const { tab, setTab, profiles, profile, selectProfile, connection, liveEnabled, setLiveEnabled, checkConnection } = useStore();
  const connectionText = {
    online: "Backend connected",
    offline: "Backend unreachable",
    checking: "Checking backend…",
    disabled: "Saved data only",
  }[connection];

  return (
    <aside className="sidebar">
      <div className="wordmark">
        Adaptive
        <small>Retirement that adapts to your life</small>
      </div>

      <nav className="nav" aria-label="Sections">
        {TABS.map((t) => (
          <button key={t.id} aria-current={tab === t.id ? "page" : undefined} onClick={() => setTab(t.id)}>
            <Icon name={t.icon} /> {t.title}
          </button>
        ))}
      </nav>

      <div className="profiles">
        <p className="eyebrow" style={{ marginBottom: 6 }}>Customer</p>
        {profiles.map((p) => (
          <button key={p.id} className="profile-btn" aria-pressed={p.id === profile.id} onClick={() => selectProfile(p.id)}>
            <Avatar id={p.id} name={p.name} size={38} />
            <span>
              <span className="name" style={{ display: "block" }}>{p.name}</span>
              <span className="sub">{PROFILE_SUBTITLE[p.id] ?? `Age ${p.age}`}</span>
            </span>
          </button>
        ))}
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
