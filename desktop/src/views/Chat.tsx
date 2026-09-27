import { useEffect, useRef, useState, type FormEvent } from "react";
import { APIError, api, type EducationReply, type EducationTurn } from "../api/client";
import type { ScreenContext } from "../api/chatContext";
import { Icon } from "../components/ui";

type Message = EducationTurn & { reply?: EducationReply };

const STARTERS: Record<ScreenContext["screen"], string[]> = {
  overview: ["Why is this my next step?", "What does my emergency savings mean?", "How does the employer match help?"],
  plan: ["Why did my plan choose this order?", "Explain my contribution rate", "What does this debt APR mean?"],
  explore: ["What changes in this scenario?", "Why are the projections different?", "Is this return guaranteed?"],
  funds: ["How were these funds ranked?", "What does the risk score mean?", "How do the fund fees compare?"],
  learn: ["What is a target-date fund?", "What is an employer match?", "What does investment risk mean?"],
};
const SCREEN_LABEL: Record<ScreenContext["screen"], string> = {
  overview: "Overview", plan: "Your plan", explore: "Explore", funds: "Fund shortlist", learn: "Learn",
};

function originLabel(reply: EducationReply) {
  if (reply.mode === "ai") return "AI-generated explanation";
  return reply.topic === "out_of_scope" ? "Built-in answer" : "Built-in answer · Gemini unavailable or question restricted";
}

export function Chat({ open, onClose, context }: { open: boolean; onClose: () => void; context: ScreenContext }) {
  const [messages, setMessages] = useState<Message[]>([]);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState("");
  const active = useRef<AbortController | null>(null);
  const thread = useRef<HTMLDivElement | null>(null);
  const questionInput = useRef<HTMLInputElement | null>(null);
  const panel = useRef<HTMLElement | null>(null);

  useEffect(() => () => active.current?.abort(), []);
  useEffect(() => {
    // scrollIntoView would also scroll the panel and page; move only the thread.
    const log = thread.current;
    if (!open || !messages.length || !log) return;
    log.scrollTo({ top: log.scrollHeight, behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
  }, [messages, sending, open]);
  useEffect(() => {
    if (!open) return;
    const returnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    questionInput.current?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
      if (event.key !== "Tab") return;
      const controls = panel.current?.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled), summary, details[open] a');
      if (!controls?.length) return;
      const first = controls[0], last = controls[controls.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
      returnFocus?.focus();
    };
  }, [open, onClose]);

  async function ask(question: string) {
    const message = question.trim();
    if (!message || message.length > 500 || sending) return;
    const history = messages.slice(-4).map(({ role, content }) => ({ role, content: content.slice(0, 500) }));
    const controller = new AbortController();
    active.current = controller;
    setError("");
    setSending(true);
    setDraft("");
    setMessages((current) => [...current, { role: "user", content: message }]);
    try {
      const reply = await api.educationChat(message, history, context, controller.signal);
      setMessages((current) => [...current, { role: "assistant", content: reply.answer, reply }]);
    } catch (failure) {
      if (!controller.signal.aborted) {
        setMessages((current) => current.slice(0, -1));
        setDraft(message);
        setError(failure instanceof APIError && failure.kind === "server"
          ? failure.body?.message ?? "The learning assistant could not answer right now."
          : failure instanceof APIError && failure.kind === "timedOut"
            ? "The learning assistant took too long. Try again."
            : "Could not reach the learning assistant. Check the backend and try again.");
      }
    } finally {
      if (active.current === controller) active.current = null;
      setSending(false);
    }
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    void ask(draft);
  }

  if (!open) return null;

  return (
    <>
    <div className="scrim chat-scrim" onClick={onClose} />
    <section ref={panel} className="chat-page chat-panel" role="dialog" aria-modal="true" aria-label="Retirement learning assistant">
      <div className="chat-panel-head">
        <div className="chat-identity"><span className="chat-mark"><Icon name="chat" size={18} /></span><div><strong>Adaptive guide</strong><span>Looking at {SCREEN_LABEL[context.screen]}</span></div></div>
        <button type="button" className="close" onClick={onClose} aria-label="Close chat"><Icon name="close" size={18} /></button>
      </div>
      <div ref={thread} className="chat-thread" role="log" aria-live="polite" aria-label="Conversation">
        {messages.length === 0 && (
          <>
          <div className="chat-intro">
            <h2>What’s on your mind?</h2>
            <p>Ask about what you see on {SCREEN_LABEL[context.screen]}, or explore a retirement topic.</p>
          </div>
          <div className="chat-starters">
            <p className="chat-label">Try a question</p>
            {STARTERS[context.screen].map((question) => (
              <button type="button" key={question} disabled={sending} onClick={() => void ask(question)}><span>{question}</span><span aria-hidden="true">↗</span></button>
            ))}
          </div>
          </>
        )}
        {messages.map((item, index) => {
          const links = item.reply?.sources.filter((source) => source.url.startsWith("https://")) ?? [];
          return (
            <article className={`chat-message ${item.role}`} key={index}>
              <p className="chat-label">{item.role === "user" ? "You" : "Adaptive guide"}</p>
              <p>{item.content}</p>
              {item.reply && (links.length ? (
                <details className="chat-sources">
                  <summary>{originLabel(item.reply)} · References</summary>
                  {links.map((source) => (
                    <a href={source.url} target="_blank" rel="noopener noreferrer" key={source.url}>{source.title}</a>
                  ))}
                </details>
              ) : <p className="chat-origin">{originLabel(item.reply)}</p>)}
            </article>
          );
        })}
        {sending && <p className="chat-pending" role="status"><span className="chat-dots" aria-hidden="true"><i /><i /><i /></span>Thinking about your question…</p>}
      </div>

      <form className="chat-form" onSubmit={submit}>
        {error && <p className="chat-error" role="alert">{error}</p>}
        <label className="chat-sr" htmlFor="chat-question">Ask about retirement</label>
        <div className="chat-composer">
          <input ref={questionInput} id="chat-question" value={draft} maxLength={500} disabled={sending}
            onChange={(event) => setDraft(event.target.value)} placeholder="Ask a retirement question…" />
          <button className="chat-send" type="submit" aria-label="Send question" disabled={sending || !draft.trim()}><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="M12 19V5m-6 6 6-6 6 6" /></svg></button>
        </div>
        <p className="chat-footnote">Your question, recent chat, and a summary of this screen may be sent to Google Gemini. Educational only; keep personal details private.</p>
      </form>
    </section>
    </>
  );
}
