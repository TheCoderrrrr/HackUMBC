# Educational chat

The retirement-learning chat opens from the floating **Ask** button on every desktop and iPhone tab. Closing the panel or sheet keeps the conversation in memory while the selected customer stays the same; switching customers clears it. It explains the figures and labels on Overview, Plan, Explore, and Fund shortlist, plus general retirement topics. It is separate from `/v1/evaluate`; it does not recalculate a plan or rank funds.

## API

`POST /v1/education/chat`

```json
{
  "message": "What is a target-date fund?",
  "history": [{ "role": "user", "content": "What is investment risk?" }],
  "context": { "screen": "plan", "data_mode": "live", "facts": [
    { "label": "next_step", "value": "Tackle the credit card" },
    { "label": "next_step_monthly_amount", "value": "$963.80" }
  ] }
}
```

`message` is required, at most 500 characters. `history` is optional, at most four turns of at most 500 characters each. `context` is optional, with a screen ID, data mode, and at most 40 short label/value facts. The response contains `answer`, `mode` (`ai` or `template`), `topic`, and server-owned Investor.gov `sources` where a general topic has a matching source; screen-specific answers may have no link. The endpoint is rate-limited and uses at most one model call with a 12-second deadline. When AI is unavailable, times out, or returns an invalid answer, the server returns a built-in answer.

## Grounding and privacy

When configured for Gemini, the model receives the current chat question and up to four recent chat turns, plus a server-written topic note. The endpoint also accepts a bounded summary of the currently visible screen, including displayed synthetic plan amounts or fund facts. It does not send the full account or evaluation object. An obvious password, key, SSN, card number, or account identifier in the chat question, history, or screen facts prevents a model call and returns the built-in answer. This detector cannot guarantee that every sensitive detail is recognized, so the clients warn users not to enter them. Numbers and percentages alone are allowed in educational questions. The clients keep conversation state only in memory and mark built-in answers.

The model returns a structured prose answer bounded to 900 characters. The system instruction limits it to retirement education, asks it to decline unrelated tasks and personalized directives, and forbids invented citations, current rates, new fund recommendations, and calculations. The backend rejects blank or malformed answers, links, and numerical figures not present in the user's question or screen facts. Source links always come from the server's topic map, so they are relevant reading rather than citations proving every generated sentence. The assistant has no retrieval or fact verification; model prose can still be wrong. Without screen context, clearly unrelated questions receive an out-of-scope template. When adding a general topic, include a directly relevant server-owned link and fallback.

## Verification

From the repository root on Windows:

```powershell
.\.venv\Scripts\python.exe -m pytest backend/tests/test_education.py -q
.\.venv\Scripts\python.exe -m pytest backend -q
```

From `desktop/`: `npm.cmd run build`. The iPhone view needs an Xcode build and on-device check on a Mac; this Windows workspace has no Swift compiler. Test a normal topic, a follow-up, an out-of-scope question, a personalized question, model-disabled fallback, rate limit, backend outage, and source links on both clients.
