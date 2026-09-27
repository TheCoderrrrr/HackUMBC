import { useId, useRef, useState, type ReactNode } from "react";

export interface Series {
  name: string;
  values: number[];
  color: string;
  dashed?: boolean;
  area?: boolean;
  width?: number;
}

/**
 * Responsive SVG line chart on a shared scale. Hover or drag to move the playhead;
 * `renderTooltip` receives the hovered index. Lines keep their stroke width at any size.
 */
export function LineChart({ series, height = 220, index, onIndex, renderTooltip, markers = [] }: {
  series: Series[];
  height?: number;
  index?: number | null;
  onIndex?: (index: number | null) => void;
  renderTooltip?: (index: number) => ReactNode;
  markers?: { index: number; label: string }[];
}) {
  const ref = useRef<HTMLDivElement>(null);
  const gradient = useId();
  const [hover, setHover] = useState<number | null>(null);
  const active = index ?? hover;

  const count = Math.max(...series.map((s) => s.values.length), 2);
  const top = Math.max(...series.flatMap((s) => s.values), 1) * 1.06;
  const W = 1000;
  const H = height;
  const x = (i: number) => (i / (count - 1)) * W;
  const y = (v: number) => H - (v / top) * (H - 6) - 2;

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

  return (
    <div ref={ref} className="chart" style={{ height }}
      onMouseMove={(e) => move(e.clientX)} onMouseLeave={leave}
      onTouchMove={(e) => move(e.touches[0].clientX)} onTouchEnd={leave}>
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" role="img"
        aria-label={series.map((s) => s.name).join(" and ")}>
        <defs>
          <linearGradient id={gradient} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#a8e6a1" stopOpacity="0.28" />
            <stop offset="100%" stopColor="#a8e6a1" stopOpacity="0" />
          </linearGradient>
        </defs>
        {[0.25, 0.5, 0.75].map((f) => (
          <line key={f} x1={0} x2={W} y1={H * f} y2={H * f} stroke="rgba(255,255,255,0.05)" vectorEffect="non-scaling-stroke" />
        ))}
        {series.filter((s) => s.area && s.values.length > 1).map((s) => (
          <path key={`${s.name}-area`} d={`${path(s.values)}L${x(s.values.length - 1)},${H}L0,${H}Z`} fill={`url(#${gradient})`} />
        ))}
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
      </svg>
      {active !== null && series.map((s) => s.values[active] !== undefined && (
        <span key={s.name} style={{
          position: "absolute", left: `${(active / (count - 1)) * 100}%`, top: y(s.values[active]),
          width: 10, height: 10, marginLeft: -5, marginTop: -5, borderRadius: "50%",
          background: s.color, boxShadow: "0 0 0 3px rgba(16,17,20,0.9)", pointerEvents: "none",
        }} />
      ))}
      {active !== null && renderTooltip && (
        <div className="tooltip" style={{
          left: `${Math.min(Math.max((active / (count - 1)) * 100, 12), 88)}%`, top: -8, transform: "translate(-50%, -100%)",
        }}>
          {renderTooltip(active)}
        </div>
      )}
    </div>
  );
}
