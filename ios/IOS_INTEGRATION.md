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
- Backend error responses become `APIError.server(status:body:)`. `error.isRetryable` tells the UI whether to show Retry.

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

The store also sets the existing `store.dataMode` to `.saved`, `.live` or `.lastLive`.

## 4. What screens should read

```swift
switch store.evaluationLoad {
case .idle:                         // no bundle and no server yet: keep DemoData
case .loading(let previous):        // show previous (if any) with a small spinner
case .loaded(let loaded):           // show loaded.evaluation
case .failed(let previous, let e):  // show previous plus a retry banner if (e as? APIError)?.isRetryable == true
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

# second terminal (brew install cloudflared)
cloudflared tunnel --url http://localhost:8000
# prints https://<name>.trycloudflare.com
python scripts/smoke.py https://<name>.trycloudflare.com
```

Then give the app the tunnel URL in either of these ways:

- In Xcode, open Scheme > Run > Arguments and add `-serverBaseURL https://<name>.trycloudflare.com`.
- Use the settings field from step 2.

`http://localhost` is deliberately rejected, so always use the tunnel.

To check it worked, select Morgan and confirm `store.dataMode == .live` and that `evaluationLoad` becomes `.loaded`. Then stop `uvicorn` and switch profiles: the app should stay usable and show the saved or last live result.

## 7. Still waiting on others

- **Eric (Developer C):** the offline bundle for `Resources/Demo/`. Until it's added, `DemoRepository` reports `bundleMissing` and the app falls back to `DemoData`.
- **Gemini key:** goes only in the git-ignored `backend/.env`. No iOS changes are needed; decisions just switch from `rules` to `ai`.

Questions about the contract or engine: ask Kevin. Questions about the bundle: ask Eric.
