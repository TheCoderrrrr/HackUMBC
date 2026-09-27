# Integration Audit: Frontend, Backend and the Connection Between Them

**Date:** 2026-09-27 · **Branch audited:** `Eric` at `e6f022c`, plus the two staged iOS changes · **Scope:** every file under `backend/`, `ios/`, `contracts/`, and the top-level docs.

This report lists every defect and risk found after merging the SwiftUI app with the FastAPI backend. Each issue gives the symptom, the root cause with file and line, and a fix. Owners follow `BACKEND_TEAM_SPLIT.md`: **A** = Neil (API, schemas, AI pipeline), **B** = Kevin (state, policy, template explanations), **C** = Eric (simulation, evaluator, export), **iOS** = Tyler (SwiftUI app). Fixes in another owner's files are proposals for that owner.

---

## Contents

1. [How this was tested](#1-how-this-was-tested)
2. [Summary](#2-summary)
3. [Deep dive: "Compare scenario" → "Couldn't calculate this scenario."](#3-deep-dive-compare-scenario--couldnt-calculate-this-scenario)
4. [Connection and deployment issues](#4-connection-and-deployment-issues)
5. [Frontend issues](#5-frontend-issues)
6. [Backend issues](#6-backend-issues)
7. [Tooling and documentation issues](#7-tooling-and-documentation-issues)
8. [Verified working (no action needed)](#8-verified-working-no-action-needed)
9. [Recommended fix order](#9-recommended-fix-order)

---

## 1. How this was tested

These checks ran against the real code, not only a reading of it:

| Check | Result |
|---|---|
| `pytest` (backend) | 341 passed |
| `xcodebuild` for the iOS Simulator, with the staged changes | BUILD SUCCEEDED |
| **Scenario sweep:** every profile (Jordan, Morgan, Casey, Morgan cash-security) × every retirement age the Stepper allows (age+1 … 80) × Adaptive plus every Fixed rate the Stepper allows (0 … 20% in 0.5 steps), through `POST /v1/evaluate` | **6,594 / 6,594 returned 200 with a feasible custom projection.** No 422, no 500. Slowest 0.40 s. |
| **Swift decode check:** compiled `APIContract.swift` + `DemoRepository.swift` with `swiftc` and decoded 30 live responses (rules and simulated-AI, base, scenario, and replay-with-changes) plus `/v1/demo-profiles`, the 7 response and error examples in `contracts/examples`, and all 13 files of the saved bundle | 51 / 51 decoded. A Swift-encoded `EvaluateRequest` was accepted by the backend (200). |
| Saved-bundle freshness: re-ran `scripts.export_demo` into a temp dir and diffed the manifest | Identical; the bundle matches the current engine |
| Live tunnels: one `GET /health` and one app-identical scenario `POST` to each ngrok domain | Both up, but they are **two different servers with different configs** (see §3, §4) |

---

## 2. Summary

| Severity | Count | Meaning |
|---|---:|---|
| 🔴 Critical | 4 | Breaks a demo-critical feature, or makes the app show untrue labels |
| 🟠 High | 5 | Wrong behavior on a common path |
| 🟡 Medium | 13 | Wrong in edge cases, misleading, or fragile |
| ⚪ Low | 14 | Polish, dead code, docs |

| ID | Sev | Area | Owner | Issue |
|---|:-:|---|---|---|
| [A1](#a1--non-json-http-errors-collapse-into-the-generic-message) | 🔴 | Connection | iOS | Non-JSON HTTP errors (ngrok 404/502) all become "Couldn't calculate this scenario." |
| [A2](#a2--the-app-and-the-readme-point-at-two-different-servers) | 🔴 | Deployment | iOS + all | App default URL and README URL are two different laptops with different configs |
| [A3](#a3--the-saved-preset-fallback-can-never-run-while-a-server-url-is-set) | 🟠 | iOS | iOS | Saved-preset fallback is unreachable while a server URL is set (always, by default) |
| [A4](#a4--the-offline-bundle-is-not-in-the-app) | 🟠 | iOS | C → iOS | Offline bundle was never copied into `Resources/Demo/` |
| [A5](#a5--glass-buttons-may-swallow-taps-on-ios-26) | 🟠 | iOS | iOS | Interactive Liquid Glass swallows taps; fix staged for one style only |
| [A6](#a6--time-budget-and-payload-size-leave-little-room-under-the-8-s-client-timeout) | 🟡 | Connection | A + iOS | Time budget and 110–190 KB uncompressed payloads crowd the 8 s timeout |
| [A7](#a7--compare-results-can-vanish-or-never-appear) | 🟡 | iOS | iOS | Compare results can vanish silently or never render |
| [A8](#a8--misleading-422-for-blocked-profiles-and-over-cap-rates) | 🟡 | Backend | C + A | Misleading 422 for blocked profiles and over-cap rates |
| [B1](#b1--provenance-labels-are-untrue-when-no-calculation-is-loaded) | 🔴 | iOS | iOS | "Saved demo calculation" / "Saved AI-assisted priorities" shown on hand-typed data |
| [B2](#b2--almost-none-of-the-ai-and-decision-output-reaches-the-screen) | 🔴 | iOS | iOS | Almost none of the AI / decision output reaches the screen |
| [B3](#b3--hard-coded-per-profile-copy-can-contradict-the-engine) | 🟠 | iOS | iOS | Hard-coded per-profile copy can contradict the engine |
| [B4](#b4--evaluationdisplay-mixes-response-values-with-demodata-values) | 🟡 | iOS | iOS | `EvaluationDisplay` mixes response values with `DemoData` values |
| [B5](#b5--illustrative-payoff-shows-a-hard-coded-date) | 🟡 | iOS | iOS | "Illustrative payoff" can show a hard-coded Sep 2028 |
| [B6](#b6--assumptions-sheet-ignores-the-responses-assumptions) | 🟡 | iOS | iOS | Assumptions sheet ignores the response's `assumptions` |
| [B7](#b7--onboarding-focus-is-cosmetic-and-the-cash-security-demo-is-unreachable) | 🟡 | iOS | iOS | Onboarding focus is cosmetic; cash-security demo unreachable |
| [B8](#b8--onboarding-debt-result-says-credit-card-for-everyone) | ⚪ | iOS | iOS | Onboarding debt result says "credit card" for everyone |
| [B9](#b9--rate-1-pt-preset-is-lower-than-morgans-current-rate) | ⚪ | Product | iOS + C | "Rate +1 pt" is below Morgan's current 8% |
| [B10](#b10--non-retryable-failures-are-invisible) | 🟡 | iOS | iOS | Non-retryable failures are invisible (no banner, no Retry) |
| [C1](#c1--neither-live-server-actually-produces-ai-decisions) | 🟠 | Backend config | A | Neither live server produces AI decisions |
| [C2](#c2--public-unauthenticated-endpoint-spends-the-teams-openai-budget) | 🟡 | Security | A | Public, unauthenticated endpoint spends the team's OpenAI budget |
| [C3](#c3--top-level-warnings-mix-every-month-of-every-projection) | 🟡 | Backend | C | Top-level `warnings` mix every month of every projection |
| [C4](#c4--prose-validators-reject-ordinary-english) | ⚪ | Backend | A + B | Prose validators reject ordinary English ("no one", "certain") |
| [C5](#c5--template-text-shows-raw-floats-and-debt-ids) | ⚪ | Backend | B | Template text shows raw floats and debt IDs |
| [C6](#c6--dead-and-duplicate-code-around-decision-ids-and-hashes) | ⚪ | Backend | A | Dead/duplicate decision-ID and hash code |
| [C7](#c7--tests-read-the-developers-real-env) | ⚪ | Tests | A | Tests read the developer's real `.env` |
| [C8](#c8--body-size-guard-only-checks-content-length) | ⚪ | Backend | A | Body-size guard only checks `Content-Length` |
| [D1](#d1--smokepy-never-tests-a-successful-compare-and-crashes-on-html-errors) | 🟡 | Tooling | A | `smoke.py` never tests a successful compare; crashes on HTML errors |
| [D2](#d2--serve_demosh-can-leave-a-tunnel-serving-502s) | 🟡 | Tooling | A | `serve_demo.sh` can leave a tunnel serving 502s |
| [D3](#d3--docs-disagree-on-tunnel-bundle-status-and-expected-results) | ⚪ | Docs | all | Docs disagree on tunnel, bundle status and expected results |
| [D4](#d4--two-fixes-to-tylers-files-are-staged-but-not-committed) | ⚪ | Process | C + iOS | Two fixes to Tyler's files are staged, not committed |
| [E1–E6](#e-smaller-frontend-findings) | ⚪/🟡 | iOS | iOS | Smaller frontend findings |

---

## 3. Deep dive: "Compare scenario" → "Couldn't calculate this scenario."

### What the message actually means

The text comes from exactly one place, the `default:` branch of the error mapper in [ScenarioControls.swift:305-312](ios/AdaptiveRetirement/Features/Explore/ScenarioControls.swift#L305-L312):

```swift
switch error as? APIError {
case .server(_, let body): return body.message          // backend JSON error envelope
case .timedOut:            return "The calculation took too long. Try again."
case .unreachable, .invalidBaseURL: return "Reconnect for a custom scenario. ..."
default:                   return "Couldn't calculate this scenario."
}
```

So the message only appears for errors that are **not** a backend error envelope, a timeout, or a dead connection. That leaves three cases from [APIClient.swift](ios/AdaptiveRetirement/Services/APIClient.swift):

| `APIError` | Raised when | Line |
|---|---|---|
| `.unexpectedStatus(Int)` | A non-2xx response whose body is **not** the backend's JSON envelope | [APIClient.swift:97-102](ios/AdaptiveRetirement/Services/APIClient.swift#L97-L102) |
| `.invalidResponse` | A 2xx body that fails to decode as `API.Evaluation`, or the profile ID isn't found | [APIClient.swift:103-107](ios/AdaptiveRetirement/Services/APIClient.swift#L103-L107), [AppStore.swift:253](ios/AdaptiveRetirement/App/AppStore.swift#L253) |
| `.cancelled` | The URL task was cancelled while the SwiftUI task wasn't | [APIClient.swift:84-88](ios/AdaptiveRetirement/Services/APIClient.swift#L84-L88) |

### What it is not

- **Not the engine.** The sweep sent every combination the scenario controls can produce (6,594 requests). All returned 200 with a feasible custom projection. A real infeasible scenario returns a JSON envelope (`INFEASIBLE_SCENARIO`) and would show the backend's own message, not this one.
- **Not a contract mismatch.** 51 real payloads, including AI-sourced decisions and replay changes, decode with the app's own `APIContract.swift`, and Swift-encoded requests are accepted.
- **Not a sanitized 500.** A backend 500 is an envelope, so it would show "Something went wrong. Please try again."

### Root cause: the tunnel, not the calculation

When a request goes through ngrok and the laptop side isn't answering, **ngrok itself** answers with an HTML error page:

| Situation | ngrok answers | App sees | App shows |
|---|---|---|---|
| `uvicorn` stopped, crashed, or restarting (`--reload`) while `ngrok` still runs | **502** HTML (`ERR_NGROK_8012`) | `.unexpectedStatus(502)` | **"Couldn't calculate this scenario."** |
| `ngrok` stopped, laptop asleep, or pointed at the wrong domain | **404** HTML (`ERR_NGROK_3200`, endpoint offline) | `.unexpectedStatus(404)` | **"Couldn't calculate this scenario."** |
| Server up | JSON | decoded | result |

Two conditions in this repo make that happen **intermittently**:

1. **Two servers ([A2](#a2--the-app-and-the-readme-point-at-two-different-servers)).** The app's built-in URL is `coral-sandbox-apron.ngrok-free.dev` ([AppStore.swift:81](ios/AdaptiveRetirement/App/AppStore.swift#L81)). The README tells people to run `unsheathe-chemicals-truth.ngrok-free.dev` ([README.md:220-222](README.md#L220-L222)). Both answered during this audit. They are different laptops: one reported `AI_UNAVAILABLE` (no key), the other `TIMEOUT`. Whenever the laptop behind the app's URL sleeps, restarts uvicorn, or closes ngrok, every Compare fails with this message, even if the README laptop is running fine.
2. **`serve_demo.sh` doesn't stop the tunnel when the API dies ([D2](#d2--serve_demosh-can-leave-a-tunnel-serving-502s)).** If uvicorn exits, ngrok keeps the domain alive and serves 502s, which is the first row above.

It feels random because the **first** load on app launch fails quietly: a 404 or 502 isn't "retryable" ([APIClient.swift:19-26](ios/AdaptiveRetirement/Services/APIClient.swift#L19-L26)), so no Retry banner appears ([B10](#b10--non-retryable-failures-are-invisible)), and the screens keep showing `DemoData` under a "Saved demo calculation" badge ([B1](#b1--provenance-labels-are-untrue-when-no-calculation-is-loaded)). Nothing looks wrong until someone presses Compare.

**Secondary causes of the same message** (rarer):
- A 2xx **non-JSON** page (for example if ngrok's browser-warning interstitial is ever served despite the `ngrok-skip-browser-warning` header) → `.invalidResponse`.
- `/v1/demo-profiles` returns a list without the selected profile ID → `.invalidResponse` ([AppStore.swift:247-255](ios/AdaptiveRetirement/App/AppStore.swift#L247-L255)). This happens only when the bundle is missing ([A4](#a4--the-offline-bundle-is-not-in-the-app)) and the server's fixtures differ from the app's IDs.

### How to confirm on a device

1. Open **Explore → Modeling assumptions** and read the server URL the phone is actually using.
2. From the laptop, run `curl -si https://<that-domain>/health | head -5`. An `ngrok-error-code` header means the tunnel answered, not FastAPI.
3. In the uvicorn log, a Compare press that reached FastAPI prints `POST /v1/evaluate 200 …ms`. If the log shows nothing, the request died at ngrok.

### Fix

**iOS (Tyler), in `APIClient.swift` and `ScenarioControls.swift`:**

```swift
// APIClient.send: classify non-envelope failures instead of dropping them.
guard (200..<300).contains(http.statusCode) else {
    if let envelope = try? JSONDecoder().decode(API.ErrorEnvelope.self, from: data) {
        throw APIError.server(status: http.statusCode, body: envelope.error)
    }
    // ngrok answers for a dead laptop or tunnel: treat as unreachable, which is retryable.
    if http.value(forHTTPHeaderField: "ngrok-error-code") != nil || [404, 502, 503, 504].contains(http.statusCode) {
        throw APIError.unreachable
    }
    throw APIError.unexpectedStatus(http.statusCode)
}
```

- Give `.unexpectedStatus` and `.invalidResponse` their own messages that include the status ("The server answered with an error (502). Check that the backend is running."), so the message says what went wrong.
- After any transport failure, fall back to the saved preset if one matches ([A3](#a3--the-saved-preset-fallback-can-never-run-while-a-server-url-is-set)).
- In `#if DEBUG`, log the status code and the first 200 bytes of an undecodable body.

**Deployment (all):** pick one demo domain and one laptop, and put it in exactly one place ([A2](#a2--the-app-and-the-readme-point-at-two-different-servers)). **Tooling (Neil):** make `serve_demo.sh` exit when uvicorn exits ([D2](#d2--serve_demosh-can-leave-a-tunnel-serving-502s)).

---

## 4. Connection and deployment issues

### A1 🔴 Non-JSON HTTP errors collapse into the generic message
Covered in full in [§3](#3-deep-dive-compare-scenario--couldnt-calculate-this-scenario). Owner: iOS.

### A2 🔴 The app and the README point at two different servers
- **Where:** [AppStore.swift:81](ios/AdaptiveRetirement/App/AppStore.swift#L81) (`coral-sandbox-apron`), [README.md:220-222](README.md#L220-L222) (`unsheathe-chemicals-truth`), [ios/IOS_INTEGRATION.md:134](ios/IOS_INTEGRATION.md#L134) (`coral-sandbox-apron`).
- **What happens:** A fresh install talks to `coral-sandbox-apron`. Anyone following the README starts `unsheathe-chemicals-truth`. The phone never reaches that server unless someone types the URL in the Assumptions sheet. The two servers also run different configs. During this audit, the same Morgan scenario returned `rules_fallback / AI_UNAVAILABLE` in 2.1 s from one and `rules_fallback / TIMEOUT` in 4.5 s from the other.
- **Fix:**
  1. Agree on one demo domain and one host laptop. Record it in `backend/RUNBOOK.md`.
  2. Move the default URL out of Swift into `ios/Config/*.xcconfig` → Info.plist (`SERVER_BASE_URL`). A developer can then override it in the git-ignored `Signing.local.xcconfig`, as signing already works.
  3. Show the active host (just the domain) under the `LiveStatusRow` badge in DEBUG builds, so testers can see which server they're on.

### A3 🟠 The saved-preset fallback can never run while a server URL is set
- **Where:** [ScenarioControls.swift:276-285](ios/AdaptiveRetirement/Features/Explore/ScenarioControls.swift#L276-L285), [AppStore.swift:164](ios/AdaptiveRetirement/App/AppStore.swift#L164).
- **What happens:** Saved presets are used only when `!store.isLiveEnabled`, which means "no URL configured". Because `defaultServerBaseURL` is always set, `isLiveEnabled` is always true, even in Airplane Mode. Offline, a preset chip + Compare tries the network, fails, and shows "Reconnect for a custom scenario. **Saved presets still work offline.**" Tapping the preset again repeats the same failure, so the message's promise is false.
- **Fix:** Try live first, then fall back on a transport error (`.unreachable`, `.timedOut`, `.unexpectedStatus`, `.invalidResponse`) when `compared.preset` has a saved artifact:
  ```swift
  } catch {
      guard !Task.isCancelled, comparedDraft == compared else { return }
      if let preset = compared.preset?.demoPreset,
         let saved = store.savedEvaluation(for: profile.id, preset: preset) {
          result = saved.evaluation
          status = "Offline. Showing the saved calculation for this preset."
      } else {
          status = Self.message(for: error)
      }
  }
  ```
  This only helps once [A4](#a4--the-offline-bundle-is-not-in-the-app) is done.

### A4 🟠 The offline bundle is not in the app
- **Where:** `ios/AdaptiveRetirement/Resources/` contains only `Fonts/`. The 12-file bundle is in `backend/fixtures/generated/` and is current (re-export produced an identical manifest).
- **What happens:** `DemoRepository` throws `bundleMissing`, so `savedEvaluation(...)` is always nil. Offline, every screen shows hand-typed `DemoData`, and every saved preset is unavailable. The profile lookup also always falls through to `GET /v1/demo-profiles`, which adds a network round trip before the first evaluation.
- **Fix:** Copy the bundle (README step 6):
  ```bash
  mkdir -p ios/AdaptiveRetirement/Resources/Demo
  cp backend/fixtures/generated/*.json ios/AdaptiveRetirement/Resources/Demo/
  ```
  The project uses a synchronized root group, so Xcode picks the files up automatically, and `DemoRepository.url(for:)` already handles flattened paths. Add a CI or pre-demo check that the manifest in `Resources/Demo` matches `fixtures/generated/manifest.json`.

### A5 🟠 Glass buttons may swallow taps on iOS 26
- **Where:** The staged change in [Components.swift:204-209](ios/AdaptiveRetirement/Components/Components.swift#L204-L209) removes `.interactive()` from `PrimaryButtonStyle`, with the comment "interactive glass on a button label takes the touch, so the action never fires." `Compare scenario` uses that style.
- **What happens:** In the **committed** code, `Compare scenario` (and every other primary button) may not fire on iOS 26 devices. The same pattern is still present elsewhere, because `glassCapsule()` is **interactive by default** ([Components.swift:566-569](ios/AdaptiveRetirement/Components/Components.swift#L566-L569)):
  - Saved-scenario preset chips: [ScenarioControls.swift:357](ios/AdaptiveRetirement/Features/Explore/ScenarioControls.swift#L357)
  - "Why this plan?": [OverviewView.swift:200](ios/AdaptiveRetirement/Features/Overview/OverviewView.swift#L200)
  - [Components.swift:240](ios/AdaptiveRetirement/Components/Components.swift#L240)
- **Fix:** Commit the staged change. Then change the `glassCapsule` default to `interactive: false`, and opt in only on non-button decorations. Verify each button on an iOS 26 device, since the simulator may not reproduce this.

### A6 🟡 Time budget and payload size leave little room under the 8 s client timeout
- **Where:** [config.py:113](backend/app/config.py#L113) caps `AI_TOTAL_TIMEOUT_SECONDS` at `8 − 1 = 7 s`. [README.md:323](README.md#L323) suggests raising it toward 7 s. [APIClient.swift:37](ios/AdaptiveRetirement/Services/APIClient.swift#L37) times out at 8 s.
- **Measured:** A rules-only request took 2.1 s through the tunnel (engine ≈ 0.1 s), and an AI-timeout request took 4.5 s. Responses are 110–190 KB with no `Content-Encoding`, because every projection carries a point for every month (up to 540 × 3).
- **What happens:** With a 7 s AI budget and about 2 s of tunnel and transfer time, cellular requests go past 8 s. The app then shows "The calculation took too long." A 4 s budget works today, but raising it as the README suggests would break this.
- **Fix:**
  - Backend (Neil): `app.add_middleware(GZipMiddleware, minimum_size=1024)` in `create_app`. JSON of this shape usually compresses 85–90%.
  - Engine/API (Eric + Neil): the app only reads yearly points (`yearlyRetirementBalances`) and a few milestones. Either send yearly points plus month 0 and the last month, or add an optional request flag for point resolution.
  - Config (Neil): tie the cap to measured overhead, for example `IOS_TIMEOUT_SECONDS - 3`, and remove the "raise toward 7 s" option from the README.

### A7 🟡 Compare results can vanish or never appear
- **Where:** [ScenarioControls.swift:264](ios/AdaptiveRetirement/Features/Explore/ScenarioControls.swift#L264), [ScenarioControls.swift:290-302](ios/AdaptiveRetirement/Features/Explore/ScenarioControls.swift#L290-L302), [ScenarioControls.swift:454-459](ios/AdaptiveRetirement/Features/Explore/ScenarioControls.swift#L454-L459).
- **What happens:**
  1. Switching tabs while a compare is running cancels it (`onDisappear`). The task returns silently, `status` stays nil, and on return nothing shows: no result and no error.
  2. `OutcomeRows.strategies` returns `[]` when the **base** evaluation is missing (`guard let evaluation`). If the base load failed but Compare succeeded, the rows still say "Shown after a live calculation." while a valid scenario response is in hand.
  3. On success, the only visible feedback is a caption. The scenario isn't drawn on the chart, and the outcome rows it fills start collapsed. Users can easily believe Compare did nothing.
- **Fix:** Keep the compare task in the store (or don't cancel on `onDisappear`). In `OutcomeRows`, fall back to `custom?.projections.current/adaptive` when `evaluation` is nil. On success, expand the first row, and draw the custom series on `ComparisonChart` using the same yearly sampling.

### A8 🟡 Misleading 422 for blocked profiles and over-cap rates
- **Where:** [simulation.py:380-381](backend/app/engine/simulation.py#L380-L381) (C), [simulation.py:358-363](backend/app/engine/simulation.py#L358-L363) (C), [engine_port.py:110-116](backend/app/engine_port.py#L110-L116) (A).
- **Reproduced:**
  - A profile with a cash-flow shortfall plus an **Adaptive** scenario (no rate) → `422 INFEASIBLE_SCENARIO`: "This scenario is short $363.20 in month 1. Choose a lower contribution rate…", pointing at `scenario.employee_contribution_rate`. No rate was chosen, and the same profile without a scenario returns 200 with a blocked plan.
  - Rate 50% for Morgan → "This scenario is short $1,458.34". That amount is the excess **over the contribution cap**, not a cash shortfall.
- **Fix:**
  - Eric: in `run_simulation`, return a blocked projection (as `current`/`adaptive` do) for `custom` when `contribution_override is None`. Raise `InfeasibleScenario` only for a fixed rate. Add a `reason` (`"cash"` or `"cap"`) to `InfeasibleScenario`.
  - Neil: branch the message on `reason`. For example: "A {rate}% election exceeds the annual contribution limit." Point at `scenario.retirement_age` when there is no rate.
  - The iOS Stepper stops at 20%, which is under the cap for all demo profiles, so this is latent for the demo.

---

## 5. Frontend issues

### B1 🔴 Provenance labels are untrue when no calculation is loaded
- **Where:** [DemoData.swift:141](ios/AdaptiveRetirement/Models/DemoData.swift#L141), [178](ios/AdaptiveRetirement/Models/DemoData.swift#L178), [214](ios/AdaptiveRetirement/Models/DemoData.swift#L214) (`origin: .savedAI`); [AppStore.swift:70](ios/AdaptiveRetirement/App/AppStore.swift#L70) (`dataMode = .saved`); [AppStore.swift:192-198](ios/AdaptiveRetirement/App/AppStore.swift#L192-L198).
- **What happens:** With no bundle ([A4](#a4--the-offline-bundle-is-not-in-the-app)) and no working server, the screens render hand-typed `DemoData`, yet:
  - the badge says **"Saved demo calculation"**, and
  - "Why this plan?" says **"Saved AI-assisted priorities"**.

  No calculation and no AI produced those values. The README's guardrail "Every response says `ai` or `rules_fallback`" is broken on the client side. The same labels also appear while a live request is loading.
- **Fix:** Add `DataMode.preview = "Illustrative preview"`, and set `origin` to a new `.none` / "Not calculated" for fixtures. Use `.preview` whenever `evaluationLoad.current == nil`. Derive `origin` only from `LoadedEvaluation.origin`.

### B2 🔴 Almost none of the AI and decision output reaches the screen
- **Where:** Search the app for `rationale`, `orderedPriorities`, `fallbackReason`, `constraintChecks`, `stateSummary`, `.changes`, `.warnings`. None of them is read outside `APIContract.swift`. [ExplanationSheet.swift:101-110](ios/AdaptiveRetirement/Features/Sheets/ExplanationSheet.swift#L101-L110); [EvaluationDisplay.swift:43-48](ios/AdaptiveRetirement/Models/EvaluationDisplay.swift#L43-L48).
- **What happens:**
  - "Why this plan?" is built from `DemoData` strings. The decision's ordered priorities, per-priority rationale, evidence and tradeoffs, the fallback reason, the explanation's `state_summary`, and "what changed" (`explanation.changes`) are never displayed.
  - The AI `narrative` replaces the fixture narrative only when `explanation.source == .ai`. For Morgan it is hidden anyway, because `explanationSummary` returns a hard-coded sentence whenever there is an extra debt payment.
  - The template explanation (the labeled fallback) is never shown. A rules-fallback plan displays fixture prose written for the AI plan.

  The README's "✅ Shows the decision, evidence, tradeoffs and what changed" is not true in the app.
- **Fix:** Build `ExplanationSheet` from the response:
  - **Priorities:** `decisionSummary.orderedPriorities` + `rationale[i].summary`, `tradeoff`.
  - **Narrative:** `explanation.narrative` (either source) with a source chip ("AI-written" or "Template").
  - **Why it fell back:** a readable `fallbackReason` ("AI timed out, so the standard order was used").
  - **What changed:** `explanation.changes`, when non-empty.

  Keep `DemoData` copy only as the no-evaluation preview.

### B3 🟠 Hard-coded per-profile copy can contradict the engine
- **Where:** [OverviewView.swift:425-440](ios/AdaptiveRetirement/Features/Overview/OverviewView.swift#L425-L440) (headline by `profile.id`), `primaryActionDetail` in [DemoData.swift](ios/AdaptiveRetirement/Models/DemoData.swift), [ExplanationSheet.swift:101-138](ios/AdaptiveRetirement/Features/Sheets/ExplanationSheet.swift#L101-L138), [PlanView.swift](ios/AdaptiveRetirement/Features/Plan/PlanView.swift) `PlanCopy.debtNote`, river phase copy in [ExploreTimeline.swift:184-204](ios/AdaptiveRetirement/Features/Explore/ExploreTimeline.swift#L184-L204).
- **What happens:** Copy such as "Keep the match. Tackle the debt.", "Reserves are full and your loan rate is low", "After this debt is paid off, rebuild savings before increasing contributions", and "Contribution increased" is fixed per profile. It stays the same when the engine returns something different: a `cash_security` order, a rules fallback, a blocked plan (`cash-flow-shortfall` / `missing-match-input`), or a future fixture change.
- **Fix:** Drive the headline and detail from `plan.primaryActionID` and its `reasonCodes` (the backend already emits `HIGH_APR_DEBT`, `MAINTAIN_CONTRIBUTION`, `BUILD_FULL_RESERVE`, and so on). Keep one short copy template per reason code, and fill amounts from `reason.facts`.

### B4 🟡 `EvaluationDisplay` mixes response values with `DemoData` values
- **Where:** [EvaluationDisplay.swift](ios/AdaptiveRetirement/Models/EvaluationDisplay.swift).
- **What happens:**
  - [Line 35](ios/AdaptiveRetirement/Models/EvaluationDisplay.swift#L35): extra debt payment = action total − the **fixture** minimum, not the engine's capped minimum. The reason facts already carry `extra_payment_cents`.
  - [Lines 21-29](ios/AdaptiveRetirement/Models/EvaluationDisplay.swift#L21-L29): if the adaptive rate differs from the current rate and the match isn't full, the employer amount falls back to the **fixture** value. The response has it in the contribution reason's `employer_contribution_cents`.
  - Salary, take-home, living costs, cash, retirement balance, and debt balances/APRs are never taken from the profile that was sent. The **Financial snapshot** sheet therefore shows `DemoData`, not the inputs the engine used.
- **Fix:** Read the extra payment and employer match from `plan.reasons[].facts`. Build the display `Profile` inputs from the `API.FinancialProfile` used for the request (keep it on `LoadedEvaluation`). Today the values match for the three fixtures, so this is fragile rather than visibly wrong.

### B5 🟡 "Illustrative payoff" shows a hard-coded date
- **Where:** [ExploreTimeline.swift:160-166](ios/AdaptiveRetirement/Features/Explore/ExploreTimeline.swift#L160-L166), [PlanView.swift](ios/AdaptiveRetirement/Features/Plan/PlanView.swift) `PlanCopy.debtCleared`.
- **What happens:** Without an evaluation, or when the milestone guard fails (`debt < reserve`, `reserve ≤ 48`), month 24 (**Sep 2028**) is used. The engine's actual payoff for Morgan is month 16 (**Jan 2028**). Plan shows the fallback as a calendar date.
- **Fix:** Show a payoff date only when it comes from `projections.adaptive.debtFreeMonth`; otherwise hide the stat block.

### B6 🟡 Assumptions sheet ignores the response's `assumptions`
- **Where:** [AssumptionsSheet.swift:5](ios/AdaptiveRetirement/Features/Sheets/AssumptionsSheet.swift#L5), [ModelAssumptions.swift](ios/AdaptiveRetirement/Models/ModelAssumptions.swift).
- **What happens:** The sheet renders a Swift copy of the assumptions. Its limitations list has 4 items; the backend's `assumptions.limitations` has 8 (catch-up contributions, vesting, the 15% heuristic, and others are missing). It also says "Over 10% APR", but the engine uses **≥ 10%** ([state.py:65](backend/app/engine/state.py#L65)).
- **Fix:** Render `evaluation.assumptions` when present, with the Swift copy as the offline fallback. Change "Over" to "At least".

### B7 🟡 Onboarding focus is cosmetic, and the cash-security demo is unreachable
- **Where:** [SetupFlowView.swift:201-205](ios/AdaptiveRetirement/Features/Onboarding/SetupFlowView.swift#L201-L205), [ProfilePickerSheet.swift:12](ios/AdaptiveRetirement/Features/Sheets/ProfilePickerSheet.swift#L12).
- **What happens:** "Pay down debt / Build a cash buffer / Save for retirement" only changes which card onboarding shows. It is never sent as `planning_preference`, so choosing "Build a cash buffer" doesn't change the plan. The `morgan-cash-security` demonstration (exported, in the bundle, and described in the README) can't be selected anywhere, because the picker iterates `Profile.all` (three profiles).
- **Fix:** Either label the focus step as a view preference, or map `.cash → cash_security`, `.debt → debt_reduction` and send it with the evaluation (the backend supports it). Add a "See it with a cash-first preference" link for Morgan that loads `morgan-cash-security`.

### B8 ⚪ Onboarding debt result says "credit card" for everyone
- **Where:** [OnboardingComponents.swift:88-93](ios/AdaptiveRetirement/Features/Onboarding/OnboardingComponents.swift#L88-L93).
- **What happens:** Jordan (student loan, no extra payment) sees "**$0.00** Extra to your credit card each month". Casey (no debt) sees the same.
- **Fix:** Use the debt's name. When there is no extra payment, show "No extra debt payment needed" or skip the debt result.

### B9 ⚪ "Rate +1 pt" preset is lower than Morgan's current rate
- **Where:** [ScenarioControls.swift:333-335](ios/AdaptiveRetirement/Features/Explore/ScenarioControls.swift#L333-L335), `export_demo.py` preset definition.
- **What happens:** For Morgan, "+1 pt" means the opening Adaptive rate + 1 = **6%, held fixed**. Her current election is 8%. The saved result ($1.14M) is below both Current ($1.32M) and Adaptive ($1.46M). A "+1" label suggesting more saving that produces the lowest balance will confuse a demo audience.
- **Fix:** Rename the chip ("Fixed at 6%") or define the preset as current + 1 point. The second option changes `export_demo.py` and requires a re-export.

### B10 🟡 Non-retryable failures are invisible
- **Where:** [AppStore.swift:150-153](ios/AdaptiveRetirement/App/AppStore.swift#L150-L153), [Components.swift:396-408](ios/AdaptiveRetirement/Components/Components.swift#L396-L408).
- **What happens:** `retryableError` returns nil for `.unexpectedStatus(404)`, `.invalidResponse`, and non-retryable envelopes. The launch evaluation can fail with no banner and no Retry, while the badge keeps saying "Saved demo calculation".
- **Fix:** Show a small error state for any failure (with Retry always available for a manual re-request). With [A1](#a1--non-json-http-errors-collapse-into-the-generic-message)'s mapping, a dead tunnel becomes `.unreachable` and gets the Retry control anyway.

### E. Smaller frontend findings

| ID | Sev | Where | Issue | Fix |
|---|:-:|---|---|---|
| E1 | 🟡 | [AppStore.swift:222-236](ios/AdaptiveRetirement/App/AppStore.swift#L222-L236) | A scenario response replaces `lastLiveDecision`, so the next base refresh diffs against the scenario's decision. Its adaptive/current projections (and possibly the AI order) can also differ from the base on screen. | Keep scenario decisions out of `lastLiveDecision`. |
| E2 | ⚪ | [ScenarioControls.swift:272](ios/AdaptiveRetirement/Features/Explore/ScenarioControls.swift#L272) | Editing a control and reverting it sets `preset = nil`, so the draft no longer equals `.original` and an identical request goes out. | Compare only age, policy and rate. |
| E3 | ⚪ | [OverviewView.swift:435-437](ios/AdaptiveRetirement/Features/Overview/OverviewView.swift#L435-L437) | Next-step detail names `debts.first`, not the debt receiving the extra payment. | Use the primary action's `debtID`. |
| E4 | ⚪ | [AssumptionsSheet.swift:119-123](ios/AdaptiveRetirement/Features/Sheets/AssumptionsSheet.swift#L119-L123) | "Save" is disabled when the text equals the current URL, so there's no way to force a reconnect from this sheet. | Enable a "Reconnect" action that calls `refreshEvaluation()`. |
| E5 | ⚪ | [ComparisonChart.swift:40-41](ios/AdaptiveRetirement/Features/Explore/ComparisonChart.swift#L40-L41) | `.catmullRom` can overshoot between yearly points. | Use `.monotone`. |
| E6 | ⚪ | [AppStore.swift:76](ios/AdaptiveRetirement/App/AppStore.swift#L76), [AssumptionsSheet.swift:90](ios/AdaptiveRetirement/Features/Sheets/AssumptionsSheet.swift#L90) | Comments still say "Cloudflare tunnel". | Update to ngrok. |

---

## 6. Backend issues

### C1 🟠 Neither live server actually produces AI decisions
- **Where:** [.env.example:9](backend/.env.example#L9) and [config.py:100](backend/app/config.py#L100) default `AI_REASONING_EFFORT=low`. README speed table.
- **Measured:** `coral-sandbox-apron` → `AI_UNAVAILABLE` (no key for the selected provider). `unsheathe-chemicals-truth` → `TIMEOUT` (GPT-6 Luna at effort `low` needs about 7.6 s against a 4 s budget, per the README's own measurements).
- **What happens:** Every live decision is `rules_fallback`. The README's step 6 check ("**Why?** shows **AI-assisted priorities**") cannot pass on either server.
- **Fix (team decision, owner Neil):** Choose one option from the README's open item and make it the committed default. Measured options: `AI_REASONING_EFFORT=none` (decision fits the budget; explanations mostly fall back) or `AI_PROVIDER=gemini` (both calls fit; free-tier rate limit). Put the chosen key on the one demo host from [A2](#a2--the-app-and-the-readme-point-at-two-different-servers). Add an `ai_available` field to `/health` so `smoke.py` can warn when AI is off.

### C2 🟡 Public, unauthenticated endpoint spends the team's OpenAI budget
- **Where:** [api.py:32-38](backend/app/api.py#L32-L38); both ngrok domains are committed in this public repo.
- **What happens:** Anyone with the URL can `POST /v1/evaluate`. Each call makes up to two LLM calls. The global limit is 120/min, which allows about 240 LLM calls a minute from strangers. Because the rate limit is global, outside traffic can also push the demo phone into `429 RATE_LIMITED`.
- **Fix:** Require a shared header (`X-Demo-Key`) checked in the middleware, with the value in `.env` and in the git-ignored xcconfig. Lower `evaluations_per_minute` and make it per-client. Avoid committing live tunnel domains.

### C3 🟡 Top-level `warnings` mix every month of every projection
- **Where:** [evaluate.py:135-139](backend/app/engine/evaluate.py#L135-L139) (C).
- **What happens:** `warnings` merges state warnings with every month's allocator warnings from `current`, `adaptive` and `custom`. Morgan's response includes `UNASSIGNED_SURPLUS` even though her opening plan has no residual cash (the surplus appears years later, after the card is paid off). Items like `CURRENT_INFEASIBLE_MONTH_n` appear in the same flat list. A client can't tell which projection or month a warning belongs to.
- **Fix:** Keep top-level `warnings` to state plus opening-month plan warnings. Add `warnings` per projection (a contract change: Neil updates `schemas.py` and `contracts/`, Tyler updates `APIContract.swift`).

### C4 ⚪ Prose validators reject ordinary English
- **Where:** [pipeline.py:44-50](backend/app/ai/pipeline.py#L44-L50) (A), [policy.py:50-61](backend/app/engine/policy.py#L50-L61) (B).
- **What happens:** The explanation filter bans the words `one`, `half`, `quarter`, `double`, `twice`, so "no one", "one of your priorities" or "a quarter of the way" force the template. The rationale filter bans `age`, `older`, `certain`, so "a certain buffer" or "average" contexts force `UNSUPPORTED_RATIONALE_CLAIM` → rules fallback. Together these push the already-low AI success rate lower.
- **Fix:** Only reject number words next to units or other numbers (B's `_NUMERIC_PROSE` already does this), and allow "no one" / "one of". Log the rejection reason so the rate can be measured.

### C5 ⚪ Template text shows raw floats and debt IDs
- **Where:** [explanations.py:131-138](backend/app/engine/explanations.py#L131-L138), [explanations.py:55-61](backend/app/engine/explanations.py#L55-L61) (B).
- **What happens:** `{months:g}` prints "covers 0.952381 months". The debt narrative reads "Pay $1,363.80 on debt **morgan-card** at 25% APR". (Hidden today by [B2](#b2--almost-none-of-the-ai-and-decision-output-reaches-the-screen), visible after it's fixed.)
- **Fix:** Round months to one decimal. Name debts by type ("your credit card").

### C6 ⚪ Dead and duplicate code around decision IDs and hashes
- **Where:** [decisions.py:25-26](backend/app/decisions.py#L25-L26), [pipeline.py:56-58](backend/app/ai/pipeline.py#L56-L58), [canonical.py:59-60](backend/app/engine/canonical.py#L59-L60).
- **What happens:** `new_decision_id()` (`dec_…`) is never called. Live IDs come from `policy.validate_decision` without a prefix, while saved IDs are `dec_saved_*`. `pipeline.profile_hash` and `canonical.profile_hash` are two different hash functions, and the stored `DecisionSnapshot.profile_hash` is never read.
- **Fix:** Delete the unused helper or use it for live IDs. Keep one `profile_hash` (the canonical one) or drop the unused field.

### C7 ⚪ Tests read the developer's real `.env`
- **Where:** [config.py:16](backend/app/config.py#L16) runs `load_dotenv` at import.
- **What happens:** Tests that call `load_settings()` inherit whatever is in `backend/.env` or the shell. Reproduced: `AI_ENABLED=false pytest` fails `test_ai_available_checks_the_selected_providers_key`.
- **Fix:** Load `.env` in `load_settings()` (or `main.py`), not at import. Have the test helper clear `AI_ENABLED` and the other AI variables.

### C8 ⚪ Body-size guard only checks `Content-Length`
- **Where:** [main.py:34-37](backend/app/main.py#L34-L37).
- **What happens:** A chunked request without `Content-Length` skips the 128 KiB limit.
- **Fix:** Reject missing `Content-Length` on `POST`, or cap the body read. Low risk behind ngrok.

---

## 7. Tooling and documentation issues

### D1 🟡 `smoke.py` never tests a successful compare, and crashes on HTML errors
- **Where:** [smoke.py:21-31](backend/scripts/smoke.py#L21-L31), [smoke.py:72-74](backend/scripts/smoke.py#L72-L74).
- **What happens:** The only scenario it sends is the deliberately infeasible one, so "RESULT: OK" says nothing about Compare. `json.load(err)` on ngrok's HTML 404/502 page raises `JSONDecodeError` with a traceback instead of a clear FAIL. That is exactly the failure behind [§3](#3-deep-dive-compare-scenario--couldnt-calculate-this-scenario).
- **Fix:** Add one feasible Adaptive scenario and one feasible Fixed-rate scenario per profile, checking `projections.custom.feasible`. Catch non-JSON bodies and print the status plus the `ngrok-error-code` header. Send the `ngrok-skip-browser-warning` header the app sends. Also check that the app's default domain and the README domain are the same.

### D2 🟡 `serve_demo.sh` can leave a tunnel serving 502s
- **Where:** [serve_demo.sh](backend/scripts/serve_demo.sh).
- **What happens:** uvicorn runs in the background and ngrok in the foreground. If uvicorn exits (crash, port already in use, a bad `.env` raising `ConfigError`), ngrok keeps the domain up and answers 502 → "Couldn't calculate this scenario." The script also starts the tunnel without waiting for `/health`. It ignores a second argument, although the README passes `8000`.
- **Fix:**
  ```bash
  until curl -sf http://127.0.0.1:8000/health >/dev/null; do
    kill -0 "$API_PID" 2>/dev/null || { echo "API failed to start" >&2; exit 1; }
    sleep 0.3
  done
  ngrok http --url="$DOMAIN" 8000 --log=stdout --log-level=warn &
  NGROK_PID=$!
  wait -n "$API_PID" "$NGROK_PID"   # whichever dies first stops the demo
  ```
  Remove the stray `8000` from the README, or read `PORT="${2:-8000}"`.

### D3 ⚪ Docs disagree on tunnel, bundle status and expected results
| Doc | Problem |
|---|---|
| `BACKEND.md` §15, `FRONTEND.md`, `ios/IOS_INTEGRATION.md`, `smoke.py` docstring | Still describe Cloudflare Quick Tunnels; the team moved to ngrok |
| `ios/IOS_INTEGRATION.md:134` | Says the bundle "is still waiting on Eric's `fixtures/decisions.json`"; it exists and the bundle is exported |
| [README.md:217-222](README.md#L217-L222) | "2. Tunnel" section begins at "3." (authtoken and claim-domain steps missing); the smoke command uses a placeholder domain while the start command uses a real one |
| [README.md:251-252](README.md#L251-L252) | Promises AI-assisted priorities ([C1](#c1--neither-live-server-actually-produces-ai-decisions)), working offline presets ([A3](#a3--the-saved-preset-fallback-can-never-run-while-a-server-url-is-set)) and the Morgan demonstration in the UI ([B7](#b7--onboarding-focus-is-cosmetic-and-the-cash-security-demo-is-unreachable)) |
| [README.md:323](README.md#L323) | Suggests raising the AI budget to 7 s, which breaks the 8 s client timeout through the tunnel ([A6](#a6--time-budget-and-payload-size-leave-little-room-under-the-8-s-client-timeout)) |

### D4 ⚪ Two fixes to Tyler's files are staged but not committed
- **Where:** `ios/AdaptiveRetirement/Components/Components.swift` (glass fix, [A5](#a5--glass-buttons-may-swallow-taps-on-ios-26)) and `ios/AdaptiveRetirement/Features/Sheets/ExplanationSheet.swift` ("Got it" now clears `store.sheet`).
- **Fix:** Both build and look correct. Confirm with Tyler, since these are frontend-owned files, then commit them in their own PR so they aren't lost or mixed into unrelated work.

---

## 8. Verified working (no action needed)

These were checked and are sound, so time doesn't need to go here:

- **Engine robustness:** 6,594 / 6,594 UI-reachable scenarios succeed. Engine time is 0.02–0.40 s per evaluation.
- **Wire contract:** Python ↔ Swift decoding and encoding agree for every payload type, including AI-sourced decisions, `Change` scalars and the saved bundle.
- **Saved bundle:** current with the engine (a re-export produced an identical manifest and hashes). `DemoRepository` hash checks match the exporter.
- **Error envelopes:** 413, 422 (`INVALID_REQUEST`, `INVALID_PROFILE`, `INFEASIBLE_SCENARIO`), 429 and 500 all return the documented envelope. A stale `previous_decision_id` returns 200 with `PREVIOUS_DECISION_NOT_FOUND`.
- **AI safety net:** timeouts, rate limits and malformed output all fall back and are labeled. A successful recommendation resets the circuit breaker, so explanation-only timeouts don't trip it.
- **Morgan's headline numbers:** $963.80 extra card payment, debt-free at month 16, full reserve at month 21. The engine output matches the README.

---

## 9. Recommended fix order

**Before the next demo (about an hour, mostly config):**
1. Pick one host and one domain; point the app and all docs at it (A2). Put the AI key and the chosen AI setting on that host (C1).
2. Copy the bundle into `ios/AdaptiveRetirement/Resources/Demo/` (A4).
3. Commit the staged glass/button fix, and test Compare, the preset chips and "Why this plan?" on an iOS 26 phone (A5, D4).
4. Make `serve_demo.sh` wait for `/health` and exit when uvicorn exits (D2).

**Next (small code changes):**

5. Map ngrok/non-envelope failures to "unreachable" with a specific message (A1), and fall back to saved presets after a live failure (A3).
6. Honest labels when nothing is calculated (B1), and a visible error state for any failure (B10).
7. Add `GZipMiddleware` (A6). Extend `smoke.py` with a real Compare check (D1).

**Then (product correctness):**

8. Render the decision rationale, fallback reason and changes in "Why this plan?" (B2). Drive copy from reason codes (B3).
9. Read display numbers from the response, not `DemoData` (B4, B5, B6).
10. Engine and API message fixes for blocked or over-cap scenarios (A8), per-projection warnings (C3), and the prose-filter tuning (C4).
