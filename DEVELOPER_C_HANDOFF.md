# Current status (2026-09-26, second session)

Branch `Eric` now contains C's work merged with `main` (`0ff66cb`: A's API,
schemas and Gemini pipeline; B's engine). Only C-owned files differ from
`main`. SSH fetch fails on this machine; use
`git fetch https://github.com/TheCoderrrrr/HackUMBC.git`.

Suite: 263 pass. The one failure, `test_demo_profiles_are_the_three_fixtures`,
also fails on `main`; Neil's proposed patch fixes it (265 pass with it).

Done this session:

- Removed `allow_morgan_exception`, which B's "update 2" deleted.
- `scripts/export_demo.py` checks saved explanations with A's existing rules
  (`AIExplanation`, `source == "ai"`, no changes, A's `valid_prose`) instead of
  waiting for `schemas.validate_saved_explanation`. Pending Neil's agreement.
- `scripts/prepare_decisions.py` generates `fixtures/decisions.json` with A's
  Gemini client, prompts and prose rules, B's validator, and C's evaluator. It
  writes records without review marks and refuses to overwrite without
  `--force`. `tests/test_prepare_decisions.py` runs it with a test-only model
  through the real exporter (12 files, byte-identical across runs).
- `proposals/` holds changes to A's and B's files for Neil and Kevin; nothing
  of theirs was edited. See `proposals/README.md`.

Ownership (from `BACKEND_TEAM_SPLIT.md`): C creates `decisions.json`; A reviews
model/prompt provenance and structure; B reviews orders, rationale and
constraint checks. The frontend developer copies the bundle into iOS
`Resources/Demo/` and decodes it in Swift (`FRONTEND.md` section 7).

# Next steps

1. Neil sends the Gemini API key. Put it in `backend/.env` as
   `GEMINI_API_KEY=...` (git-ignored), then from `backend`:
   `python -m scripts.prepare_decisions`.
2. Send `fixtures/decisions.json` to Neil and Kevin. After review, each record
   gets `"reviewers": ["A", "B"]`.
3. `python -m scripts.export_demo` twice; compare bytes; commit
   `fixtures/decisions.json` and `fixtures/generated/`.
4. Give the twelve files to the frontend developer for `Resources/Demo/`.
5. Neil and Kevin answer `proposals/README.md`. Until Neil applies the real
   engine patch, the live API still serves the stub.

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
