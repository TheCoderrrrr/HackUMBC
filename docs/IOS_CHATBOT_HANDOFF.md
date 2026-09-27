# iOS chatbot handoff

This is the implementation and design brief for the Mac teammate. The goal is a screen-aware retirement guide that can be opened from **Overview**, **Plan**, **Explore**, and **Funds** without making chat its own tab. The visual treatment should feel like the rest of Adaptive Retirement: dark, calm, light on borders, and easy to read. The app should answer questions about the plan and fund figures the user is seeing, plus follow-ups, through the backend's Gemini chat endpoint.

## Current files

- `ios/AdaptiveRetirement/App/AdaptiveRetirementApp.swift`: `MainTabView` adds the floating **Ask** control to the tab view, opens `.educationChat`, and owns `chatMessages` so the conversation survives closing the sheet or changing tabs.
- `ios/AdaptiveRetirement/App/AppStore.swift`: `ActiveSheet.educationChat`, `chatScreenFacts` for Explore and Funds; `AppStore.defaultDemoKey` supplies the `X-Demo-Key` header the chat request sends when the server sets `DEMO_KEY`.
- `ios/AdaptiveRetirement/Features/Education/EducationChatView.swift`: sheet UI, section-specific starter questions, message list, composer, screen context request, and response/source display.
- `ios/AdaptiveRetirement/Features/Explore/ExploreView.swift`: publishes the selected timeline month and visible comparison values for chat.
- `ios/AdaptiveRetirement/Features/Funds/FundsView.swift`: publishes selected filters and the visible shortlist for chat.
- `ios/AdaptiveRetirement/DesignSystem/Theme.swift`: use the existing `Palette`, `TypeScale`, and `Space` tokens. Do not add an unrelated color or font system.
- `docs/EDUCATION_CHAT.md`: backend behavior and API contract.

The SwiftUI changes were written on Windows and **have not been compiled in Xcode**. Start by opening `ios/AdaptiveRetirement.xcodeproj` and fixing any compiler or layout issues. The project uses a synchronized file group, so the Education view should appear in the app target without a manual project-file entry; verify that in Xcode. A second Windows pass checked every referenced token and API type against the source, pinned the request task to the main actor (the target is Swift 5 / iOS 17), labeled out-of-scope replies as a plain built-in answer without an empty references disclosure, scrolled the transcript to the latest message on reopen and while loading, and kept the Ask button from riding up with the keyboard.

## Visual design

The small floating Ask button is a dark capsule with a hairline border, green icon and label, and a soft shadow. It sits above the tab bar near the bottom trailing edge. Keep a 44-point minimum hit area and a clear VoiceOver label. Check that it does not cover page controls, the home indicator, or the keyboard on small iPhones and with large Dynamic Type.

Present a large native sheet with a simple navigation title, **Adaptive guide**, and a visible **Done** button. Respect the system swipe-to-dismiss gesture. The chat view uses `Palette.page` as its background. Avoid a card around the entire transcript: the conversation should read as text on the sheet.

When the conversation is empty, show a short headline, one line explaining the purpose, and four suggested questions as full-width rows separated by subtle hairlines. Each row has a small arrow at the trailing edge. Once the user asks something, hide that welcome content so the conversation has room.

Put user messages on the trailing side in a faint green rounded bubble. Put assistant responses on the leading side as open text with an `ADAPTIVE GUIDE` label, generous line spacing, and no heavy background. Long answers must wrap and scroll naturally. Show a progress indicator while waiting; keep the current user question visible. Put references in a disclosure group under the response, collapsed initially. This keeps the main answer readable while preserving source access.

Anchor the composer at the bottom of the sheet: rounded dark field, circular green send button, disabled state while sending, and nearby error text. The current character limit is 500. Under the field, keep a short notice that questions, recent chat, and a summary of the current screen may be sent to Google Gemini, and that users should not type sensitive details. Do not claim a response was AI generated when `mode` is `template`.

## Behavior and data flow

The iPhone sends `POST /v1/education/chat` to the backend URL in `AppStore.serverBaseURL`. JSON request:

```json
{
  "message": "Why do fund fees matter?",
  "history": [
    { "role": "user", "content": "What is an expense ratio?" },
    { "role": "assistant", "content": "..." }
  ],
  "context": {
    "screen": "funds",
    "data_mode": "live",
    "facts": [
      { "label": "selected_risk_tolerance", "value": "moderate" },
      { "label": "fund_1_expense_ratio", "value": "0.09%" }
    ]
  }
}
```

Send at most the last four turns. The context has a screen ID, data mode, and at most 40 short label/value facts derived from the current app view. Refresh it when the selected profile, Explore comparison, or Funds shortlist changes. The backend response has `answer`, `mode` (`ai` or `template`), `topic`, and server-selected `sources` with `title` and `url`. Display the actual `answer`; do not replace it with local topic text. Open only valid HTTPS source links. Keep the Gemini key in `backend/.env`; never put it in the iOS app, Xcode scheme, bundle, or repository.

The app attaches a bounded summary of visible plan and fund data, including some synthetic balances, contributions, and shortlist facts. It does not send the full raw account record, credentials, or hidden evaluation object. The question, recent chat, and screen summary reach the backend and, when Gemini answers, Google Gemini. The backend may use a built-in answer when Gemini is unavailable or the question is restricted. The app distinguishes those cases through `mode`. The chat UI keeps messages only in memory for the current app session.

The sheet owns transient loading and error state. `MainTabView` owns the message list and draft, so closing and reopening the sheet retains context. Switching customers clears the old conversation so one person's questions are not applied to another person's plan. On dismissal, cancel an in-flight request. On cancellation or failure, remove only that request's user message and restore its draft; never remove a later message from a newly opened sheet. The network request timeout is 16 seconds, longer than the backend's separate education deadline.

## Mac verification checklist

1. Build `ios/AdaptiveRetirement.xcodeproj` for an iPhone simulator. Resolve any Swift concurrency, type inference, or project membership errors.
2. Open Ask from Overview, Plan, Explore, and Funds. Ask a question, close the sheet, change tabs, and reopen it. Verify the same conversation remains and no separate chat tab appears.
3. With a Gemini-enabled backend, ask two different questions on the same topic and a follow-up such as “Why does that matter?” Verify the responses address the wording and history and show the AI label.
4. Test with Gemini unavailable. Verify the built-in answer is labeled honestly. Also test backend offline, a slow response, a 429 response, dismissing while a request is in flight, and retrying after failure.
5. Check VoiceOver order and labels, large Dynamic Type, small-screen layout, dark-mode contrast, keyboard avoidance, safe areas, and HTTPS source links.
6. Switch between the fictional customers while chat is closed and verify the old customer's chat is cleared. Compare the JSON `context.facts` in an Xcode network inspection with the exact values visible on each screen; check that no unrelated account fields are attached.

Start the backend with `AI_PROVIDER=gemini`, `AI_MODEL=gemini-3.5-flash-lite`, and `GEMINI_API_KEY` set in `backend/.env`. Use the existing HTTPS tunnel for an iPhone device. The key stays on the server. See `docs/RUNBOOK.md` for backend and tunnel setup.
