# Integration status (2026-09-26, second session)

`main` (`0ff66cb`) now contains A's API/schemas/Gemini pipeline (PR #2) and B's
engine (PRs #1, #3). Question 1 below is resolved except for
`validate_saved_explanation`, which A has not shipped. SSH fetch fails on this
machine; `git fetch https://github.com/TheCoderrrrr/HackUMBC.git` works.

C's work was integrated onto `main` in a scratch worktree, not on this branch
yet. The full suite passes 265 tests with real A+B+C and no skips:

- B's "update 2" removed `allow_morgan_exception`; C no longer passes it.
- New `app/engine_real.py` adapts B/C dict functions to A's Pydantic
  `engine_port` signatures; `engine_port` imports it instead of the stub.
  Maps `ProfileValidationError` to 422 `INVALID_PROFILE` and
  `InfeasibleScenario` to 422 `INFEASIBLE_SCENARIO`. Fixes main's failing
  demo-profiles test (B's fixtures are a bare list).
- Recommendation evidence paths are B's `recommendation_context` keys
  (`financial_state.*`, `emergency_cash_cents`, ...). A's `situation_flags`,
  test rationale paths, and the canonical `profile_hash` were aligned.
- The Explanation prompt no longer receives `primary_action_id`; B's action IDs
  embed debt IDs.
- Orders: the adapter permits only the preference default plus the
  `morgan-cash-security` exception, per `BACKEND_TEAM_SPLIT.md` and A's tests.
  B's update 2 accepts any documented order for any profile; B should confirm
  and own this check.
- `tests/test_engine_integration.py` checks the real Morgan plan, API vs
  exporter equality (including `input_hash`), infeasible custom 422, and order
  enforcement. API medians without AI: Jordan 101 ms, Morgan 100 ms, Casey 21 ms.
- `requirements.txt` pins pytest 9.1.1; `requirements-test.txt` pins 8.4.2.

# Questions to resolve first

1. A still needs to provide `app.schemas.validate_saved_explanation`
   (saved-explanation schema and factual-evidence check).
2. Where are the genuinely reviewed saved decisions and ten artifact-specific
   AI explanations? The exporter requires exact profile/input hash bindings,
   model and prompt provenance, stable decision IDs, and A/B review marks. Test
   fixtures with synthetic text cannot be shipped as the final bundle.
3. Who will merge Kevin's B branch with Eric's C branch, and what is the iOS
   bundle destination and Swift owner for the final decoding/device handoff?

# Developer C handoff

Current workspace: `/Users/ericwei/HackUMBC`, branch `Eric`. This work is in
uncommitted files. Preserve the user's existing uncommitted
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
