import { useCallback, useEffect, useId, useLayoutEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { GLOSSARY, type TermId } from "../data/glossary";
import { useStore } from "../store";

// One popover open at a time, across the whole app.
let openKey: string | null = null;
const listeners = new Set<() => void>();
const setOpenKey = (key: string | null) => {
  openKey = key;
  listeners.forEach((l) => l());
};
const subscribe = (l: () => void) => {
  listeners.add(l);
  return () => listeners.delete(l);
};

const WIDTH = 280;
const GAP = 8;
const MARGIN = 12;

/**
 * A key term with a "?" button that opens a short definition. Click or Enter toggles it;
 * Esc, a click elsewhere, or scrolling closes it. Definitions quote the engine's assumptions.
 */
export function Term({ id, children }: { id: TermId; children?: ReactNode }) {
  const key = useId();
  const open = useSyncExternalStore(subscribe, () => openKey === key);
  const button = useRef<HTMLButtonElement>(null);
  const pop = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ top: number; left: number; above: boolean } | null>(null);
  const { display } = useStore();
  const entry = GLOSSARY[id];

  const close = useCallback((refocus = false) => {
    if (openKey === key) setOpenKey(null);
    if (refocus) button.current?.focus();
  }, [key]);

  // Place below the button, or above when there isn't room; keep inside the viewport.
  useLayoutEffect(() => {
    if (!open || !button.current) return;
    const place = () => {
      const r = button.current!.getBoundingClientRect();
      const h = pop.current?.offsetHeight ?? 120;
      const left = Math.min(Math.max(r.left + r.width / 2 - WIDTH / 2, MARGIN), window.innerWidth - WIDTH - MARGIN);
      const above = r.bottom + GAP + h > window.innerHeight - MARGIN && r.top - GAP - h > MARGIN;
      setPos({ top: above ? r.top - GAP - h : r.bottom + GAP, left, above });
    };
    place();
    const raf = requestAnimationFrame(place); // re-measure once the popover has its real height
    return () => cancelAnimationFrame(raf);
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        close(true);
      }
    };
    const onPointer = (e: PointerEvent) => {
      const t = e.target as Node;
      if (!pop.current?.contains(t) && !button.current?.contains(t)) close();
    };
    const onScroll = () => close();
    window.addEventListener("keydown", onKey, true);
    window.addEventListener("pointerdown", onPointer, true);
    window.addEventListener("scroll", onScroll, true);
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("keydown", onKey, true);
      window.removeEventListener("pointerdown", onPointer, true);
      window.removeEventListener("scroll", onScroll, true);
      window.removeEventListener("resize", onScroll);
    };
  }, [open, close]);

  useEffect(() => () => close(), [close]);

  const popId = `${key}-def`;
  return (
    <span className="term">
      {children ?? entry.title}
      <button ref={button} type="button" className="term-btn" aria-label={`What is ${entry.title}?`}
        aria-expanded={open} aria-controls={open ? popId : undefined}
        onClick={(e) => {
          e.stopPropagation();
          setOpenKey(open ? null : key);
        }}>
        ?
      </button>
      {open && createPortal(
        <div ref={pop} id={popId} role="tooltip" className={`term-pop ${pos?.above ? "above" : ""}`}
          style={{ top: pos?.top ?? -9999, left: pos?.left ?? -9999, width: WIDTH }}>
          <p className="term-pop-title">{entry.title}</p>
          <p className="term-pop-text">{entry.text(display?.evaluation.assumptions)}</p>
        </div>,
        document.body,
      )}
    </span>
  );
}
