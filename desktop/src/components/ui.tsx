import { useEffect, type ReactNode } from "react";
import { DATA_MODE_LABEL, type CashKind } from "../data/display";
import { moneyExact, splitMoney } from "../data/format";
import { useStore } from "../store";

// ---------- Icons (SF Symbols stand-ins) ----------

const paths: Record<string, ReactNode> = {
  overview: <path d="M3 13h4v7H3zM10 8h4v12h-4zM17 4h4v16h-4z" />,
  plan: <path d="M5 4h14v16H5zM8 8h8M8 12h8M8 16h5" />,
  explore: <path d="M3 17l5-6 4 4 8-9M14 6h6v6" />,
  funds: <path d="M12 3v9h9A9 9 0 1 1 12 3zM15 3.5A9 9 0 0 1 20.5 9H15z" />,
  chat: <path d="M4 5h16v12H9l-5 4V5zM8 9h8M8 13h5" />,
  link: <path d="M14 4h6v6M20 4l-9 9M18 14v6H4V6h6" />,
  why: <path d="M12 21a9 9 0 1 0-8.2-5.3L3 21l5.3-.8A9 9 0 0 0 12 21zM9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6M12 16.5v.01" />,
  doc: <path d="M6 3h8l4 4v14H6zM14 3v4h4M9 12h6M9 16h4" />,
  sliders: <path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0M14 4v4M8 10v4M16 16v4" />,
  arrow: <path d="M5 12h14M13 6l6 6-6 6" />,
  chevron: <path d="M9 6l6 6-6 6" />,
  close: <path d="M6 6l12 12M18 6L6 18" />,
  check: <path d="M5 12.5l4.5 4.5L19 7" />,
  play: <path d="M8 5v14l11-7z" fill="currentColor" />,
  pause: <path d="M7 5h3v14H7zM14 5h3v14h-3z" fill="currentColor" />,
  replay: <path d="M4 12a8 8 0 1 0 2.3-5.7M4 4v5h5" />,
  refresh: <path d="M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5" />,
  compare: <path d="M4 5h7v14H4zM13 5h7v14h-7z" />,
  person: <path d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0" />,
  building: <path d="M4 21V5l8-2v18M12 8l8 2v11M7 8h2M7 12h2M7 16h2M15 13h2M15 17h2" />,
  flag: <path d="M5 21V4M5 4h12l-2 4 2 4H5" />,
  umbrella: <path d="M12 3a9 9 0 0 1 9 9H3a9 9 0 0 1 9-9zM12 12v6a2 2 0 0 0 4 0" />,
  seal: <path d="M12 2l2.4 2.1 3.2-.3.6 3.1 2.8 1.6-1.3 2.9 1.3 2.9-2.8 1.6-.6 3.1-3.2-.3L12 22l-2.4-2.1-3.2.3-.6-3.1-2.8-1.6 1.3-2.9L3 9.4l2.8-1.6.6-3.1 3.2.3zM8.5 12l2.5 2.5 4.5-5" />,
};

export function Icon({ name, size = 18 }: { name: keyof typeof paths | string; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.7}
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {paths[name]}
    </svg>
  );
}

// ---------- Identity ----------

const AVATAR: Record<string, [string, string]> = {
  jordan: ["#3F7A7A", "#2A3F66"],
  casey: ["#52709A", "#35405A"],
  morgan: ["#6FD08A", "#2A7A4A"],
};

export function Avatar({ id, name, size = 40 }: { id: string; name: string; size?: number }) {
  const [a, b] = AVATAR[id] ?? AVATAR.morgan;
  return (
    <span className="avatar" style={{ width: size, height: size, fontSize: size * 0.4, background: `linear-gradient(135deg, ${a}, ${b})` }}
      aria-hidden="true">
      {name.slice(0, 1)}
    </span>
  );
}

export const PROFILE_SUBTITLE: Record<string, string> = {
  morgan: "Competing priorities",
  jordan: "Financially established",
  casey: "Approaching retirement",
};

// ---------- Figures ----------

export function HeroAmount({ cents }: { cents: number }) {
  const parts = splitMoney(cents);
  return (
    <div className="hero" aria-label={moneyExact(cents)}>
      <span className="dollars">{parts.dollars}</span>
      <span className="cents">.{parts.cents}</span>
    </div>
  );
}

export function Figure({ children, size = 52 }: { children: ReactNode; size?: number }) {
  return <span className="figure" style={{ fontSize: size }}>{children}</span>;
}

export function Stat({ value, unit, caption, align = "left", icon }: {
  value: string; unit?: string; caption: string; align?: "left" | "right"; icon?: string;
}) {
  return (
    <div style={{ textAlign: align, flex: 1 }}>
      <div style={{ display: "flex", gap: 5, alignItems: "baseline", justifyContent: align === "right" ? "flex-end" : "flex-start" }}>
        {icon && <span style={{ color: "var(--text-2)", alignSelf: "center", display: "flex" }}><Icon name={icon} size={14} /></span>}
        <span className="figure" style={{ fontSize: 22, letterSpacing: -0.6 }}>{value}</span>
        {unit && <span className="caption" style={{ fontSize: 13 }}>{unit}</span>}
      </div>
      <div className="caption" style={{ marginTop: 3 }}>{caption}</div>
    </div>
  );
}

// ---------- Bands ----------

export const BAND: Record<CashKind | "employer" | "minimum", string> = {
  retirement: "var(--band-retirement)",
  debt: "var(--band-debt)",
  emergency: "var(--band-emergency)",
  remaining: "var(--band-remaining)",
  employer: "var(--band-employer)",
  minimum: "var(--band-minimum)",
};

export const CASH_ACCENT: Record<CashKind, string> = {
  retirement: "var(--accent)",
  debt: "var(--debt-accent)",
  emergency: "var(--positive)",
  remaining: "var(--text)",
};

export interface BandSegment {
  label: string;
  value: string;
  weight: number;
  fill: string;
}

/** Proportional band whose segments carry their own label and amount. */
export function SegmentedBand({ segments, height = 64, minPercent = 18 }: {
  segments: BandSegment[]; height?: number; minPercent?: number;
}) {
  const total = segments.reduce((s, x) => s + x.weight, 0) || 1;
  return (
    <div className="band" style={{ height }} role="img" aria-label={segments.map((s) => `${s.label} ${s.value}`).join(", ")}>
      {segments.map((s) => (
        <div key={s.label} className="band-seg" style={{ background: s.fill, flexGrow: Math.max((s.weight / total) * 100, minPercent), flexBasis: 0 }}>
          <div className="seg-text">
            <div className="seg-label">{s.label}</div>
            <div className="seg-value">{s.value}</div>
          </div>
        </div>
      ))}
    </div>
  );
}

/** Share-labelled band; only funded categories get a slice. */
export function ShareBand({ items, height = 40 }: { items: { key: string; amount: number; fill: string }[]; height?: number }) {
  const funded = items.filter((i) => i.amount > 0);
  const total = funded.reduce((s, i) => s + i.amount, 0);
  return (
    <div className="band" style={{ height }}>
      {funded.map((i) => (
        <div key={i.key} className="band-seg" style={{ background: i.fill, flexGrow: i.amount, flexBasis: 0, borderRadius: 8 }}>
          {height >= 24 && <div className="seg-center">{((i.amount / total) * 100).toFixed(1)}%</div>}
        </div>
      ))}
    </div>
  );
}

export function MonthMeter({ months, target }: { months: number; target: number }) {
  return (
    <div className="meter" role="progressbar" aria-valuenow={months} aria-valuemax={target}>
      {Array.from({ length: Math.max(Math.round(target), 1) }, (_, i) => (
        <div key={i}><i style={{ width: `${Math.min(Math.max(months - i, 0), 1) * 100}%` }} /></div>
      ))}
    </div>
  );
}

export function AllocationRing({ stocks, size = 124 }: { stocks: number; size?: number }) {
  const stroke = 12;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const gap = 0.012 * c;
  const stockLen = Math.max(stocks * c - 2 * gap, 0);
  const bondLen = Math.max((1 - stocks) * c - 2 * gap, 0);
  return (
    <div style={{ position: "relative", width: size, height: size, flex: "none" }}>
      <svg width={size} height={size} style={{ transform: "rotate(-90deg)" }}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--accent)" strokeWidth={stroke} strokeLinecap="round"
          strokeDasharray={`${stockLen} ${c}`} strokeDashoffset={-gap} />
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--bonds)" strokeWidth={stroke} strokeLinecap="round"
          strokeDasharray={`${bondLen} ${c}`} strokeDashoffset={-(stocks * c + gap)} />
      </svg>
      <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", textAlign: "center" }}>
        <div>
          <div className="figure" style={{ fontSize: 22 }}>{Math.round(stocks * 1000) / 10}%</div>
          <div className="caption" style={{ fontSize: 11 }}>stocks</div>
        </div>
      </div>
    </div>
  );
}

// ---------- Headers ----------

export function SectionHeader({ title, onWhy, subtitle }: { title: string; onWhy?: () => void; subtitle?: string }) {
  return (
    <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 12, marginBottom: 16 }}>
      <div>
        <h2 className="h-section">{title}</h2>
        {subtitle && <p className="caption" style={{ marginTop: 3 }}>{subtitle}</p>}
      </div>
      {onWhy && <button className="link" onClick={onWhy} aria-label={`Why? ${title}`}>Why?</button>}
    </div>
  );
}

// ---------- Status ----------

export function LiveStatus() {
  const { dataMode, isLoading, retryable, refresh } = useStore();
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <span className="badge">
        <span className={`dot ${dataMode === "live" ? "on" : ""}`} />
        {DATA_MODE_LABEL[dataMode]}
      </span>
      {isLoading && <span className="spinner" aria-label="Updating live calculation" />}
      {retryable && (
        <button className="link" onClick={refresh} style={{ display: "inline-flex", alignItems: "center", gap: 5 }}
          title="Couldn't reach the server. Showing the previous result.">
          <Icon name="refresh" size={14} /> Retry
        </button>
      )}
    </div>
  );
}

// ---------- Drawer ----------

export function Drawer({ title, subtitle, onClose, children, footer }: {
  title: string; subtitle?: string; onClose: () => void; children: ReactNode; footer?: ReactNode;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <>
      <div className="scrim" onClick={onClose} />
      <aside className="drawer" role="dialog" aria-modal="true" aria-label={title}>
        <div className="drawer-head">
          <div>
            <h2>{title}</h2>
            {subtitle && <p className="label" style={{ marginTop: 4, color: "var(--caption)" }}>{subtitle}</p>}
          </div>
          <button className="close" onClick={onClose} aria-label="Close"><Icon name="close" size={16} /></button>
        </div>
        <div className="drawer-body">{children}</div>
        {footer && <div className="drawer-foot">{footer}</div>}
      </aside>
    </>
  );
}

export function Stepper({ onDecrement, onIncrement, canDecrement, canIncrement, label }: {
  onDecrement: () => void; onIncrement: () => void; canDecrement: boolean; canIncrement: boolean; label: string;
}) {
  return (
    <div className="stepper" role="group" aria-label={label}>
      <button onClick={onDecrement} disabled={!canDecrement} aria-label={`Decrease ${label}`}>−</button>
      <span />
      <button onClick={onIncrement} disabled={!canIncrement} aria-label={`Increase ${label}`}>+</button>
    </div>
  );
}
