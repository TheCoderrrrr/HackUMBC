import { useId, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { Icon } from "./ui";

export interface TabItem<T extends string> {
  id: T;
  label: string;
  /** Short status shown under the label, e.g. "$963.80 extra". */
  hint?: string;
}

/**
 * Accessible tab list (WAI-ARIA tabs pattern): arrow keys, Home and End move between tabs,
 * only the selected tab is in the tab order, and the panel is labelled by its tab.
 */
export function Tabs<T extends string>({ items, value, onChange, label, children }: {
  items: TabItem<T>[];
  value: T;
  onChange: (id: T) => void;
  label: string;
  children: ReactNode;
}) {
  const base = useId();
  const refs = useRef(new Map<T, HTMLButtonElement>());

  const move = (e: KeyboardEvent, index: number) => {
    const last = items.length - 1;
    const next = e.key === "ArrowRight" ? (index === last ? 0 : index + 1)
      : e.key === "ArrowLeft" ? (index === 0 ? last : index - 1)
        : e.key === "Home" ? 0 : e.key === "End" ? last : null;
    if (next === null) return;
    e.preventDefault();
    onChange(items[next].id);
    refs.current.get(items[next].id)?.focus();
  };

  return (
    <div className="tabs">
      <div className="tab-list" role="tablist" aria-label={label}>
        {items.map((item, i) => {
          const selected = item.id === value;
          return (
            <button key={item.id} ref={(el) => { if (el) refs.current.set(item.id, el); }}
              id={`${base}-tab-${item.id}`} role="tab" aria-selected={selected} aria-controls={`${base}-panel`}
              tabIndex={selected ? 0 : -1} className="tab" onClick={() => onChange(item.id)} onKeyDown={(e) => move(e, i)}>
              <span className="tab-label">{item.label}</span>
              {item.hint && <span className="tab-hint">{item.hint}</span>}
            </button>
          );
        })}
      </div>
      <div id={`${base}-panel`} role="tabpanel" aria-labelledby={`${base}-tab-${value}`} className="tab-panel fade-in" key={value}>
        {children}
      </div>
    </div>
  );
}

/** A labelled section that opens and closes; closed by default unless `defaultOpen`. */
export function Disclosure({ title, summary, defaultOpen = false, children }: {
  title: string;
  summary?: ReactNode;
  defaultOpen?: boolean;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);
  const id = useId();
  return (
    <section className={`disclosure ${open ? "open" : ""}`}>
      <button className="disclosure-head" aria-expanded={open} aria-controls={id} onClick={() => setOpen(!open)}>
        <span className="disclosure-title">{title}</span>
        {summary && !open && <span className="disclosure-summary">{summary}</span>}
        <span className="disclosure-chevron"><Icon name="chevron" size={14} /></span>
      </button>
      {open && <div id={id} className="disclosure-body fade-in">{children}</div>}
    </section>
  );
}
