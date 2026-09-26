# What Eric (Developer C) needs from the team

Eric is building the offline demo bundle: the ten saved evaluations the iPhone
app uses when the server or AI is down. The code is done and tested on branch
`Eric`. What's left depends on the items below. Details and the patch are in
[`proposals/README.md`](proposals/README.md).

## Neil (Developer A)

| # | What | Blocks |
|---|---|---|
| 1 | **Gemini API key.** Send it privately, not in the repo or chat history. | Generating the saved AI decisions and explanations |
| 2 | **Decide on the saved-explanation check** (proposal item 2). The exporter reuses your `AIExplanation` model and `valid_prose` rules. Is that the right check? | Generating: if the rules change, the saved text must be regenerated |
| 3 | **Review the real-engine wiring** (proposal item 1): `engine_port.evaluate` now calls C's evaluator. | The live demo. If you change the prompts, tell Eric before he generates. |
| 4 | **Review `backend/fixtures/decisions.json`** once Eric sends it. Check model/prompt provenance and output structure, then add `"A"` to each record's `reviewers`. | Final export |

## Kevin (Developer B)

| # | What | Blocks |
|---|---|---|
| 1 | **Decide which priority orders are allowed** (proposal item 3). The spec allows a non-default order only for the Morgan cash-security variant; your latest code allows any documented order for any profile. | Generating: a policy change after generation makes the saved decisions stale |
| 2 | **Confirm the model may see every value in `recommendation_context`** (proposal item 4). | Generating |
| 3 | **Hold engine, assumption and version changes** between Eric generating and the final export, or tell Eric. Any change alters the hashes, and the exporter rejects stale files. | Final export |
| 4 | **Review `backend/fixtures/decisions.json`.** Check orders, rationale and constraint checks, then add `"B"` to each record's `reviewers`. | Final export |

## Neil and Kevin together

- **Agree on one pytest version** (proposal item 5): `requirements.txt` pins
  9.1.1 and `requirements-test.txt` pins 8.4.2.

## Frontend developer

| # | What | When |
|---|---|---|
| 1 | **Build Swift decoding against the placeholder bundle** Eric sends. Its structure is final; only the AI text will change. | As soon as Eric sends it |
| 2 | **Add the final twelve files to `Resources/Demo/`** and check decoding, offline launch, the saved-AI labels, and corrupt-file handling (`FRONTEND.md` section 7). | After the reviewed bundle is exported |

## Order of events

1. Neil answers item 2, Kevin answers items 1 and 2, and Neil sends the key.
2. Eric generates `decisions.json` and sends the placeholder bundle to the frontend developer.
3. Neil and Kevin review `decisions.json` and add their marks.
4. Eric exports the final bundle, commits it, and hands it to the frontend developer.
