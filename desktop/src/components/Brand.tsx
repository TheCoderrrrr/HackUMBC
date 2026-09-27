/**
 * The sidebar header: the README logo (blocks forming an "A" that rise into place, apex glowing)
 * beside the illuminated ARM wordmark, over a strip of rising blocks from the README banner.
 */

// Front blocks of assets/logo.svg on its 26-unit grid: [column, row, colour].
const BLOCKS: [number, number, string][] = [
  [3, 0, "#FFFFFF"],
  [2, 1, "#67E8F9"], [4, 1, "#67E8F9"],
  [2, 2, "#38BDF8"], [4, 2, "#38BDF8"],
  [1, 3, "#0EA5E9"], [5, 3, "#0EA5E9"],
  [1, 4, "#3B82F6"], [2, 4, "#3B82F6"], [3, 4, "#3B82F6"], [4, 4, "#3B82F6"], [5, 4, "#3B82F6"],
  [0, 5, "#2563EB"], [6, 5, "#2563EB"],
  [0, 6, "#1D4ED8"], [6, 6, "#1D4ED8"],
];

export function Logo({ size = 44 }: { size?: number }) {
  return (
    <svg className="logo" width={size} height={size} viewBox="-4 -4 186 186" aria-hidden="true">
      {BLOCKS.map(([c, r, fill], i) => (
        <g key={i} className="logo-block" style={{ animationDelay: `${(6 - r) * 70 + c * 12}ms` }}>
          <rect x={c * 26 + 3.5} y={r * 26 + 3.5} width="20" height="20" rx="5.2" fill="#0C2F5A" />
          <rect x={c * 26} y={r * 26} width="20" height="20" rx="5.2" fill={fill} className={r === 0 ? "logo-apex" : undefined} />
        </g>
      ))}
    </svg>
  );
}

/** Bar heights of the banner's rising-blocks strip (percent). */
const RISE = [22, 34, 28, 46, 40, 58, 52, 70, 64, 82, 76, 94];

export function Brand() {
  return (
    <div className="brand">
      <div className="brand-row">
        <Logo />
        <div>
          <p className="brand-title">ARM</p>
          <p className="brand-sub">Adaptive Retirement Management</p>
        </div>
      </div>
      <div className="brand-rise" aria-hidden="true">
        {RISE.map((h, i) => <i key={i} style={{ height: `${h}%`, animationDelay: `${i * 90}ms` }} />)}
      </div>
    </div>
  );
}
