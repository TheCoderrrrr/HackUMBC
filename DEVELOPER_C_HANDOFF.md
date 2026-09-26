# Current status (2026-09-26, third session)

Branch `Eric` is `main` (`4b041ce`: Neil's prompt v2, Kevin's PR #8) plus the
changes below. The suite passes 316 tests. SSH fetch fails on this machine; use
`git fetch https://github.com/TheCoderrrrr/HackUMBC.git`. What the team needs
from C, and what C needs from them, is in `ERIC_NEEDS.md`,
`DEVELOPER_A_NEEDS.md` and `backend/DEVELOPER_B_REQUESTS.md`.

Done this session (C-owned files only):

- `prepare_decisions.py` sends the same prompt as the live API: all three
  documented orders, default first, and `PROMPT_VERSION` from
  `app.ai.prompts`. Saved standard decisions must still be the preference
  default (keeps Morgan's $963.80); the Morgan variant must be
  starter -> debt -> full. After `AIRateLimited` it waits the provider's
  suggested time (30 s if none, at most 120 s) before retrying.
- `export_demo.py --draft` skips only the review marks and writes only to the
  git-ignored `fixtures/draft/`, for Kevin's pre-review audit and the
  frontend placeholder.

# Next steps

1. Get a Gemini key (aistudio.google.com/apikey) into `backend/.env` as
   `GEMINI_API_KEY=...`. Don't set `AI_PROMPT_VERSION`; the code owns it.
2. From `backend`: `python -m scripts.prepare_decisions`, then
   `python -m scripts.export_demo --draft`.
3. Send `fixtures/decisions.json` to Neil and Kevin, and `fixtures/draft/` to
   Kevin (audit) and the frontend developer (placeholder).
4. After both review marks: `python -m scripts.export_demo` twice, compare
   bytes, commit `fixtures/decisions.json` and `fixtures/generated/`, hand the
   twelve files to the frontend developer for `Resources/Demo/`.

# Developer C handoff

The notes below are from the first session and describe C's original
implementation. Current workspace: `/Users/ericwei/HackUMBC`, branch `Eric`. Preserve the user's existing uncommitted
`BACKEND_TEAM_SPLIT.md` marker (`IM FOCUSING ON THIS WORK VVVVVV`) when
continuing; it predates the implementation and was not added by C. The
approved implementation details and measured status are in
`DEVELOPER_C_PLAN.md`.

## Implemented here

- `backend/app/engine/monthly.py`: typed immutable monthly inputs, allocations,
  projections, and engine errors.
- `backend/app/engine/simulation.py`: deterministic Current, Adaptive, and
  Custom progression, with B's real allocator as the production policy source.
  It enforces cash/debt/contribution invariants, growth, returns, milestones,
  and distinct infeasibility behavior.
- `backend/app/engine/evaluate.py`: provider-free evaluation assembly. It
  verifies that B's displayed first-month plan equals the Adaptive opening
  allocation before returning the evaluation.
- `backend/app/engine/canonical.py`: shared canonical JSON, profile hash, and
  input hash helpers for A's API and C's exporter.
- `backend/scripts/export_demo.py`: saved decision replay, exact explanation
  binding, all ten artifact specs, manifest and profile bundle, full reload
  validation, locking, staged publication, rollback, and interrupted-swap
  recovery. An ambiguous valid output plus valid backup requires manual
  resolution. It refuses stale, missing, mislabeled, or unreviewed content.
- `backend/tests/`: numerical, hash, export, recovery, and real B integration
  tests. `FRONTEND.md` and `README.md` describe the tenth demonstration
  artifact and three standard picker profiles.

## Verified

From the workspace root:

```sh
python3 -m unittest discover -s backend/tests -q
python3 -m compileall -q backend
git diff --check
```

The local suite passes 26 tests, with five B integration tests skipped because
Kevin's modules are not in branch `Eric`. Those five tests pass when C's modules
are copied into a temporary checkout of published branch `Kevin`, including
real B policy for all three standard profiles, the Morgan exception, exact
Morgan first-month arithmetic, missing-match blocking, and deterministic
ten-artifact export with explicitly test-only synthetic saved text. No provider
call is involved. Measured provider-free evaluation medians on macOS 15.6.1
arm64/Python 3.12.1: Jordan 98.4 ms, Morgan 97.3 ms, Casey 19.1 ms (five runs
each), within the 250 ms demo fixture target.

The remote `Neil` and `main` branches were checked and both pointed to the
same docs-only commit (`8116b58`) at the time of this handoff. Kevin's B commit
was `cb07985`. Branch `Eric` was at `d92c0db` before these uncommitted C edits.

## Resume sequence

1. Obtain A's actual code and reviewed saved content from the answers above.
   Keep C's files and the user's document edit while integrating branches.
2. Reconcile A's public schema names and fields with `evaluate.py` and
   `export_demo.py`. A must provide `app.schemas.validate_saved_explanation`
   or an equivalent factual-evidence validation handoff; the final exporter
   deliberately fails without it. A should import C's canonical hash helper
   so API and export hashes are identical.
3. Run the full suite with A and B together. Add schema-level API/export
   equality checks and fix any response shape differences. The current local
   test environment lacks `pytest` and `pydantic`, so those checks could not
   run here.
4. Supply canonical profiles, four reviewed saved decision records, four
   explicit rules-fallback records, and ten reviewed explanation records.
   Run from `backend`:

   ```sh
   python -m scripts.export_demo --profiles fixtures/profiles.json \
     --decisions fixtures/decisions.json --output fixtures/generated
   ```

   The result must contain ten evaluation JSON files plus `profiles.json` and
   `manifest.json`. Run twice and compare bytes. Then copy the validated bundle
   to iOS and have the iOS owner decode all ten artifacts, check cold-launch
   offline behavior, saved labels, and corrupt-bundle handling.
5. Recheck performance and maximum supported horizon/debt count on the merged
   backend. Only then commit the reviewed bundle and report final acceptance.

No final reviewed bundle or iOS copy was produced here because A's schemas,
validator, and genuinely reviewed saved AI content were unavailable. Do not
replace them with the synthetic records from the tests.
