# iOS backend integration: handoff for the Mac developer

From Kevin (Developer B). Branch: `ios-integration`.

The branch adds the data layer that connects the app to the FastAPI backend and to Eric's offline bundle. **It was written on Windows and has never been compiled.** Please build it first and fix anything Xcode reports. Screens are unchanged and still read `DemoData`.

## 1. Build it

```bash
git fetch origin
git checkout ios-integration
open ios/AdaptiveRetirement.xcodeproj
```

The project uses a synchronized root folder, so the new files are already in the target. Build for an iOS 17 simulator.

If the build fails, the most likely causes are:

- **Name clashes.** Contract types live under `API.` (for example `API.Debt`, `API.Explanation` and `API.FinancialProfile`) so they don't collide with `DemoData`. If something is still ambiguous, qualify it with `API.`.
- **Concurrency warnings** in `AppStore.refreshEvaluation()` or `FakeAPIClient`. `AppStore` is `@MainActor`, and the `Task` inherits that. Warnings are fine for the demo; errors need a fix.
- **Tuple assignment** to `lastLiveDecision`. If Xcode rejects `(profileID, id)`, write `(profileID: profileID, decisionID: id)`.

Tell Kevin about anything that looks like a contract mismatch rather than a Swift typo.

## 2. What was added

| File | Purpose |
|---|---|
| `Models/APIContract.swift` | Codable types for every request and response in `contracts/openapi.json`, with snake_case keys, `Int64` cents and an `API.schemaVersion` of `"1"` |
| `Services/APIClient.swift` | `LiveAPIClient` for `/health`, `/v1/demo-profiles` and `/v1/evaluate`, plus `APIError` and a debug-only `FakeAPIClient` |
| `Services/DemoRepository.swift` | Reads Eric's bundle: `manifest.json`, `profiles.json` and the `{profile}-{preset}.json` artifacts |
| `App/AppStore.swift` | Loading state, the server URL setting, cancellation of stale requests, and live and saved labels |

What the client does:

- It accepts HTTPS URLs only. Don't add ATS exceptions.
- Evaluations time out after 8 seconds; health and profile requests after 5.
- It never logs request bodies.
- Backend error responses become `APIError.server(status:body:)`. A non-2xx answer that isn't the JSON envelope — ngrok's HTML 404/502 pages for a dead tunnel or laptop, detected by the `ngrok-error-code` header or a 404/502/503/504 status — becomes `.unreachable`, so it is retryable and eligible for the saved-preset fallback instead of collapsing into a generic message. DEBUG builds log the status and first 200 bytes of any undecodable body (responses only; request bodies are never logged).

What the repository does:

- It checks the schema version, profile id, profile hash and input hash.
- It never interpolates between presets or calculates anything.
- It looks for files in `Resources/Demo/`, then `Demo/`, then the bundle root, because synchronized folders may flatten resources.

## 3. How loading works

Each call to `store.select(profile)` runs `refreshEvaluation()`:

1. Cancel the previous request and bump the selection counter.
2. Show the saved `original` artifact immediately, if the bundle exists.
3. If a server URL is set, request a live evaluation.
4. Apply the response only if the counter and profile id still match.
5. On failure, keep the previous result on screen: the last live result, relabeled `lastLive`, or else the saved one.

The store derives `store.dataMode` from the load state: `.saved`, `.live` or `.lastLive` when a calculation is on screen, and `.preview` ("Illustrative preview") when only the hand-typed fixtures are showing — including during the first load.

## 4. What screens should read

```swift
switch store.evaluationLoad {
case .idle:                         // no bundle and no server yet: keep DemoData
case .loading(let previous):        // show previous (if any) with a small spinner
case .loaded(let loaded):           // show loaded.evaluation
case .failed(let previous, let e):  // show previous plus store.evaluationFailure's message and a manual Retry
}
```

Or use `store.evaluationLoad.current`, which is the result to display in every state.

A `LoadedEvaluation` has:

- `evaluation: API.Evaluation`: plan, projections, decision summary, explanation, changes and assumptions.
- `mode: DataMode`: `.saved`, `.live` or `.lastLive`.
- `origin: DecisionOrigin`: `.ai`, `.rules` or `.savedAI`, for the badge.

Other store calls:

- `store.setServerBaseURL("https://…")` sets the server. It returns `false` for a URL that isn't HTTPS, and an empty string switches to saved data only. Changing the server resets live state.
- `try await store.evaluateScenario(API.Scenario(...))` runs a live custom scenario in Explore. Offline it throws `APIError.unreachable`; show "Reconnect for a custom scenario" and offer the saved presets.
- `store.savedEvaluation(for: id, preset: .retirePlusTwo)` returns an exact saved preset, or `nil`.

## 5. Suggested order of work

1. Build and fix compile errors.
2. Add a server URL field in settings or on the Assumptions sheet that calls `setServerBaseURL`.
3. Test against a live backend (section 6).
4. Move screens from `DemoData` to `store.evaluationLoad.current`, one screen at a time. Keep `DemoData` as the fallback while `evaluationLoad` is `.idle`.
5. When Eric's bundle is ready, copy it into `ios/AdaptiveRetirement/Resources/Demo/`. No code changes are needed.

## 6. Testing against the backend

The backend works without the Gemini key. It returns rules-based decisions, so the badge shows `rules`, with template explanations and full projections.

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 127.0.0.1 --port 8000

# second terminal (brew install ngrok; one fixed free domain per event)
ngrok http --url=your-team.ngrok-free.dev 8000
python scripts/smoke.py https://your-team.ngrok-free.dev
```

Then give the app the tunnel URL in either of these ways:

- At build time: `SERVER_BASE_URL = https:/$()/your-team.ngrok-free.dev` in `ios/Config/Signing.local.xcconfig` (git-ignored).
- At run time: the settings field from step 2, or Scheme > Run > Arguments `-serverBaseURL https://your-team.ngrok-free.dev`.

`http://localhost` is deliberately rejected, so always use the tunnel.

To check it worked, select Morgan and confirm `store.dataMode == .live` and that `evaluationLoad` becomes `.loaded`. Then stop `uvicorn` and switch profiles: the app should stay usable and show the saved or last live result.

## 7. Still waiting on others

- ~~**Eric (Developer C):** the offline bundle~~ — done: `Resources/Demo/` is committed and kept in sync by `test_ios_bundle_matches_the_generated_export`.
- **Gemini key:** goes only in the git-ignored `backend/.env`. No iOS changes are needed; decisions just switch from `rules` to `ai`.
- **Demo key (optional):** if the server sets `DEMO_KEY`, put the same value in `Signing.local.xcconfig` as `DEMO_KEY`; the app sends it as `X-Demo-Key`.

Questions about the contract or engine: ask Kevin. Questions about the bundle: ask Eric.

## 8. Status on the Mac (2026-09-26)

- **Build:** compiles clean for the iOS simulator with no warnings; no Swift fixes were needed in the data layer.
- **Contract:** every file in `contracts/examples` decodes with `API.*`. Against a local backend, Swift-encoded `EvaluateRequest`s (base, retire +2, fixed 11%, `previous_decision_id` chaining) all return 200 and decode; a bad scenario returns a 422 envelope. No mismatches found.
- **Screens:** `AppStore.displayProfile` is the `DemoData` fixture with the current evaluation applied (`Models/EvaluationDisplay.swift`). Overview, Plan, Explore, onboarding and the sheets read it, so they show `DemoData` while `evaluationLoad` is `.idle`, and engine values otherwise:
  - Overview chart and scrub values use `projections.adaptive`.
  - Explore's comparison chart uses the Current and Adaptive projections; Morgan's milestones use `debt_free_month` and `full_reserve_month`; "Compare scenario" calls `evaluateScenario` (or an exact saved preset offline); the outcome rows show projection values.
  - `LiveStatusRow` shows a spinner while loading and Retry after a retryable failure.
- **Server URL:** built-in default `AppStore.defaultServerBaseURL` (the team's fixed ngrok domain; see [RUNBOOK.md](RUNBOOK.md) and `backend/scripts/serve_demo.sh`). Override in Explore › Modeling assumptions › Live calculation, or with `-serverBaseURL https://…`. Requests send `ngrok-skip-browser-warning`.
- **Preview without a bundle (DEBUG):** `-evaluationFixtures /path/to/contracts/examples` loads `evaluate-<profile>.response.json` as the saved result.
- **End to end:** verified through the team's fixed ngrok domain (`smoke.py` RESULT: OK). Start it with `backend/scripts/serve_demo.sh your-team.ngrok-free.dev` and set the same domain in `Signing.local.xcconfig`. The offline bundle is committed in `Resources/Demo/`; `backend/tests/test_export.py::test_ios_bundle_matches_the_generated_export` fails if it drifts from `backend/fixtures/generated/`.
- `test_openapi_is_current` fails on newer Starlette only because the 413/422 reason phrases were renamed. That is not a contract change.
