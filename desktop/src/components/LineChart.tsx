import { useId, useRef, useState, type ReactNode } from "react";
import { firstReach, niceTicks } from "../data/chart";

export interface Series {
  name: string;
  values: number[];
  color: string;
  dashed?: boolean;
  area?: boolean;
  width?: number;
}

/**
 * Responsive SVG line chart on a shared scale. Hover previews an index; clicking pins it
 * (`onPick`), and the pinned `index` shows whenever the pointer isn't over the chart.
 * Optional: a goal line with "reached" dots, a shaded band between two series, y-axis labels.
 * Lines keep their stroke width at any size.
 */
export function LineChart({
  series, height = 220, index, onIndex, onPick, renderTooltip, markers = [], goal, band, formatY,
}: {
  series: Series[];
  height?: number;
  /** The pinned index, shown when not hovering. */
  index?: number | null;
  /** Hover preview: the index under the pointer, or null when it leaves. */
  onIndex?: (index: number | null) => void;
  /** Click (or tap) to pin an index. */
  onPick?: (index: number) => void;
  renderTooltip?: (index: number) => ReactNode;
  markers?: { index: number; label: string }[];
  /** A horizontal target line; each series gets a dot where it first reaches it. */
  goal?: { value: number; label: string } | null;
  /** Shade the area between two series (by name), e.g. to show a difference. */
  band?: { upper: string; lower: string; color: string } | null;
  /** When set, draws round y-axis ticks labelled with this formatter. */
  formatY?: (value: number) => string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const gradient = useId();
  const [hover, setHover] = useState<number | null>(null);
  const active = hover ?? index ?? null;

  const count = Math.max(...series.map((s) => s.values.length), 2);
  const peak = Math.max(...series.flatMap((s) => s.values), goal?.value ?? 0, 1);
  const ticks = formatY ? niceTicks(peak) : [];
  const top = formatY ? ticks[ticks.length - 1] || peak : peak * 1.06;
  const W = 1000;
  const H = height;
  const x = (i: number) => (i / (count - 1)) * W;
  const y = (v: number) => H - (v / top) * (H - 6) - 2;
  const pct = (i: number) => (i / (count - 1)) * 100;

  const path = (values: number[]) => values.map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join("");

  const pick = (clientX: number) => {
    const rect = ref.current?.getBoundingClientRect();
    if (!rect) return null;
    const t = Math.min(Math.max((clientX - rect.left) / rect.width, 0), 1);
    return Math.round(t * (count - 1));
  };
  const move = (clientX: number) => {
    const i = pick(clientX);
    setHover(i);
    onIndex?.(i);
  };
  const leave = () => {
    setHover(null);
    onIndex?.(null);
  };

  const upper = band ? series.find((s) => s.name === band.upper) : undefined;
  const lower = band ? series.find((s) => s.name === band.lower) : undefined;
  const bandPath = upper && lower ? (() => {
    const n = Math.min(upper.values.length, lower.values.length);
    if (n < 2) return null;
    const top = upper.values.slice(0, n).map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join("");
    const bottom = lower.values.slice(0, n).map((v, i) => [i, v] as const).reverse()
      .map(([i, v]) => `L${x(i).toFixed(1)},${y(v).toFixed(1)}`).join("");
    return `${top}${bottom}Z`;
  })() : null;

  const reaches = goal ? series.map((s) => ({ s, i: firstReach(s.values, goal.value) })).filter((r) => r.i !== null) : [];

  return (
    <div ref={ref} className={`chart ${onPick ? "pickable" : ""} ${formatY ? "with-axis" : ""}`} style={{ height }}
      onMouseMove={(e) => move(e.clientX)} onMouseLeave={leave}
      onClick={(e) => { const i = pick(e.clientX); if (i !== null) onPick?.(i); }}
      onTouchMove={(e) => move(e.touches[0].clientX)}
      onTouchEnd={(e) => { const i = pick(e.changedTouches[0].clientX); if (i !== null) onPick?.(i); leave(); }}>
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" role="img"
        aria-label={series.map((s) => s.name).join(" and ")}>
        <defs>
          <linearGradient id={gradient} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#a8e6a1" stopOpacity="0.28" />
            <stop offset="100%" stopColor="#a8e6a1" stopOpacity="0" />
          </linearGradient>
        </defs>
        {(formatY ? ticks.slice(1) : [0.25, 0.5, 0.75].map((f) => top * (1 - f))).map((v) => (
          <line key={v} x1={0} x2={W} y1={y(v)} y2={y(v)} stroke="rgba(255,255,255,0.05)" vectorEffect="non-scaling-stroke" />
        ))}
        {bandPath && <path d={bandPath} fill={band!.color} fillOpacity={0.16} />}
        {!bandPath && series.filter((s) => s.area && s.values.length > 1).map((s) => (
          <path key={`${s.name}-area`} d={`${path(s.values)}L${x(s.values.length - 1)},${H}L0,${H}Z`} fill={`url(#${gradient})`} />
        ))}
        {goal && (
          <line x1={0} x2={W} y1={y(goal.value)} y2={y(goal.value)} stroke="#f2c46d" strokeWidth={1.5}
            strokeDasharray="6 5" vectorEffect="non-scaling-stroke" />
        )}
        {series.map((s) => s.values.length > 1 && (
          <path key={s.name} d={path(s.values)} fill="none" stroke={s.color} strokeWidth={s.width ?? 2.2}
            strokeDasharray={s.dashed ? "5 4" : undefined} strokeLinecap="round" strokeLinejoin="round"
            vectorEffect="non-scaling-stroke" style={{ transition: "d 0.5s cubic-bezier(0.77,0,0.175,1)" }} />
        ))}
        {markers.map((m) => (
          <line key={m.label} x1={x(m.index)} x2={x(m.index)} y1={0} y2={H} stroke="rgba(168,230,161,0.35)"
            strokeDasharray="2 4" vectorEffect="non-scaling-stroke" />
        ))}
        {active !== null && (
          <line x1={x(active)} x2={x(active)} y1={0} y2={H} stroke="rgba(255,255,255,0.45)" vectorEffect="non-scaling-stroke" />
        )}
        {hover !== null && index !== null && index !== undefined && hover !== index && (
          <line x1={x(index)} x2={x(index)} y1={0} y2={H} stroke="rgba(255,255,255,0.2)" strokeDasharray="3 3" vectorEffect="non-scaling-stroke" />
        )}
      </svg>

      {formatY && ticks.slice(1).map((v) => (
        <span key={v} className="chart-ytick" style={{ top: y(v) }}>{formatY(v)}</span>
      ))}
      {goal && <span className="chart-goal-label" style={{ top: y(goal.value) }}>{goal.label}</span>}
      {goal && reaches.map(({ s, i }) => (
        <span key={`reach-${s.name}`} className="chart-reach" title={`${s.name} reaches the goal`}
          style={{ left: `${pct(i!)}%`, top: y(goal.value), background: s.color }} />
      ))}
      {markers.map((m) => (
        <span key={`m-${m.label}`} className="chart-marker-label" style={{ left: `${Math.min(Math.max(pct(m.index), 6), 94)}%` }}>{m.label}</span>
      ))}
      {active !== null && series.map((s) => s.values[active] !== undefined && (
        <span key={s.name} style={{
          position: "absolute", left: `${pct(active)}%`, top: y(s.values[active]),
          width: 10, height: 10, marginLeft: -5, marginTop: -5, borderRadius: "50%",
          background: s.color, boxShadow: "0 0 0 3px rgba(16,17,20,0.9)", pointerEvents: "none",
        }} />
      ))}
      {active !== null && renderTooltip && (
        <div className="tooltip" style={{
          left: `${Math.min(Math.max(pct(active), 12), 88)}%`, top: -8, transform: "translate(-50%, -100%)",
        }}>
          {renderTooltip(active)}
        </div>
      )}
    </div>
  );
}
