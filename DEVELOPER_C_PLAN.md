# Developer C implementation plan

Developer C owns deterministic monthly simulation, evaluation composition,
canonical hashes, saved-decision replay, and the ten-artifact offline bundle.
`BACKEND.md` and `BACKEND_TEAM_SPLIT.md` remain the financial and ownership
specifications. This file records the implementation order and the agreed
handoffs; the complete acceptance checklist is in Section 18 of `BACKEND.md`.

## Shared handoffs

Developer B supplies one pure monthly allocator for Current, Adaptive, and
Custom. It receives an original profile/state/decision and a month snapshot;
it computes debt interest and capped minimums, contributions, matching,
payments, and cash added. C passes the grown monthly resources, opening cash,
and updated debt balances without recalculating B's policy. B builds the
displayed plan from the same original inputs and supplies a deterministic
explanation. C compares that displayed plan with Adaptive's first simulated
allocation and fails if the numerical fields differ.
Developer A supplies the public Pydantic schemas, API error
mapping, live decision orchestration, and previous-decision comparison. C's
evaluator does not make model calls or look up prior decisions.
Developer B publishes the version constants with the assumptions.

Kevin's published implementation supplies `app.engine.policy.allocate_month`,
`build_plan`, and `validate_decision`; `app.engine.state.derive_state`;
`app.engine.money.equity_weight`; and `app.engine.assumptions.MODEL_ASSUMPTIONS`.
C adapts the mapping-based snapshot and allocation contract. A still needs to
supply `app.schemas.FinancialProfile`, `Scenario`, `AIExplanation`, and
`Evaluation`, plus `validate_saved_explanation` to check saved claims against
evaluation facts. Missing production handoffs raise `MissingHandoffError`;
tests inject explicit substitutes.

The real B contract was checked in a temporary checkout of Kevin's branch.
Test substitution remains available while the branches are separate. Before
final export, reconcile A's public model types and saved explanation validator.
C implements a shared canonical serializer for the API and exporter.

### Numerical handoff

Each month passes the month number and opening retirement horizon; grown gross
salary, reconstructed household resources, living expenses, and floored
employee cap; opening cash and retirement assets; and each debt's stable ID,
balance, APR, accrued interest, amount due, and capped minimum. The allocation
returns feasibility and shortfall, employee contribution and household cash
cost, employer match, per-debt minimum and extra payments, cash added, warnings,
and the facts needed to build display actions. All amounts are integer cents.
The allocation and per-debt payments are authoritative; prose is never parsed
to reconstruct amounts. C checks the original-month plan against the first
Adaptive allocation because Kevin's published `build_plan` recomputes it from
the same opening inputs.

### Strategy and monthly rules

- Current preserves the original election, subject to the modeled cap. After
  debt minimums, its remaining resources go to cash.
- Adaptive follows B's complete priority waterfall and the one validated
  decision order for the entire horizon.
- Custom with a null rate uses Adaptive policy at the selected retirement age.
  Custom with an explicit rate keeps that election, including when future cap
  growth lags salary growth. A shortfall raises `InfeasibleScenario` with the
  first failing month; it never silently lowers the rate.
- Current and Adaptive retain the profile retirement age. Adding Custom does
  not alter either baseline. Each strategy owns independent balances and
  includes month 0 before applying any returns or payments.

Before months 13, 25, and later anniversaries, salary, reconstructed resources,
living expenses, and the annual planning cap grow and round once. Debt interest
and capped minimums are calculated before allocation. Debt payments apply once;
the remaining payment on an almost-cleared debt is already available through
the capped minimum. Weighted illustrative returns apply to opening retirement
assets; employee contribution and employer match arrive at month end. Cash
interest applies to opening cash only, and new savings earn interest from the
following month. Equity weight uses the beginning-of-month retirement horizon.

For every feasible month, C enforces that resources before contributions equal
living expenses plus debt payments, employee contribution cash cost, and cash
added. It also checks the monthly contribution ceiling, debt identities and
payment caps, nonnegative balances, and every debt ID exactly once. Employer
match is not a household cash expense. An invariant failure raises an engine
error rather than becoming an ordinary scenario shortfall.

Debt-free and reserve milestones start at month 0 when already satisfied, then
record the first later month end that meets the target. Reserve targets use that
month's living expenses, and first hits remain recorded if the target later
rises. A blocked Current or Adaptive projection has empty points, null terminal
values and milestones, and a strategy/month warning; other strategies survive.
Missing employer-match information retains B's blocked-assessment warning.
Inflation uses each strategy's actual retirement horizon.

### Hash and replay rules

The canonical hash starts from validated models with defaults and nullable
fields populated. It sorts object keys recursively, preserves list order,
normalizes equivalent numbers and negative zero, rejects non-finite numbers,
and encodes compact UTF-8 JSON. The profile hash covers the full profile. The
evaluation input hash covers profile, scenario, assumptions, three versions,
decision source, ordered priorities, model ID, and prompt version. It excludes
decision IDs, generated text, timestamps, and previous-decision IDs. Duplicate
debt IDs are rejected before projection.

There are three standard profiles and one Morgan cash-security variant. The
variant retains Morgan's financial inputs and display identity, changing its
ID, planning preference, and saved decision provenance. Nine standard
artifacts cover Original, retirement +2 years, and contribution +1 percentage
point. The tenth is the variant's Original scenario. Each +1 preset uses the
actual opening Adaptive contribution rate and must stay affordable, within
the modeled employee cap, and at or below the 20% UI ceiling. The manifest
lists only the three standard IDs in `default_profile_ids` and links the
variant demonstration to Morgan.

Saved decisions bind to exact profile hashes and carry model/prompt provenance.
Explanations bind to exact evaluation input hashes. B revalidates each saved
proposal, including the documented Morgan exception order; A's validator must
check each saved explanation's schema and factual evidence before attachment.
Missing, stale, mislabeled, or unreviewed saved content rejects final export.
Explicit rules-fallback records exercise offline/provider-outage behavior.

### Publication and verification

The exporter generates a sibling staging directory, reloads all ten
evaluations plus `profiles.json` and `manifest.json`, verifies versions, hashes,
profile links, scenarios, provenance, filenames, and the complete twelve-file
set, and only then publishes. A lock refuses concurrent exports. The previous
bundle moves to a backup before staged publication. A caught publication error
restores the backup; a following run restores an interrupted swap when only
the backup exists. If both output and backup are valid, export stops for manual
resolution. Bundle JSON has deterministic ordering and no generation time.
The iOS copy occurs only after successful publication and Swift decoding.

Required checks cover contribution matching and tax cash cost, cap flooring,
anniversary boundaries, zero or partial debt payoff, negative amortization,
reserve milestones, returns timing, inflation, independent strategy balances,
early and late infeasibility, exact Morgan opening arithmetic, plan/allocation
agreement, defaulted-value hashes, scenario and provenance hash changes,
ten-artifact replay, deterministic byte equality, stale saved text, invalid presets,
and write/rename recovery. API and exporter must use the same evaluator and
produce equal numerical fields. The iOS owner checks cold launch offline,
three standard profile presets, the Morgan demonstration, saved labels, and
corrupt-bundle handling. Performance is measured without provider latency.

## Build sequence

1. Model immutable monthly inputs and allocations. Apply integer-cent money
   arithmetic, `ROUND_HALF_UP` for ordinary amounts, and floor the monthly
   employee cap with `annual_limit_cents // 12`.
2. Simulate the three strategies independently. Grow annual inputs before
   months 13, 25, etc.; call B's allocator once per month to obtain interest
   and payments; apply debt payments and returns; then append cash and retirement
   contributions. Cash interest applies to opening cash and credits at month
   end. Include month 0 and first-hit milestones.
3. Enforce cash conservation, debt, matching, cap, and balance invariants on
   every feasible month. Stop Current or Adaptive on a shortfall and return a
   blocked projection; raise a typed error for infeasible Custom.
4. Compose `Evaluation` from independent Current, Adaptive, and optional
   Custom runs. Check B's first-month plan against Adaptive's opening allocation;
   include B's template explanation. A may replace it with validated live AI
   text after evaluation.
5. Hash fully validated, default-populated input models through one canonical
   serializer. Exclude decision IDs, timestamps, generated prose, and prior
   decision IDs from the numeric input hash.
6. Replay reviewed saved decisions through B's validator. Bind each of the ten
   reviewed explanations to its exact input hash. Include an explicit Morgan
   cash-security variant profile and manifest entry linked to Morgan, while
   leaving three standard customer choices.
7. Generate every artifact in a sibling staging directory, reload and validate
   the complete bundle, then publish it with a recoverable backup. Never
   silently substitute stale explanations or partial artifact output.
8. Integrate A/B implementations and copy the successful bundle to iOS.

The exporter accepts a `decisions.json` object with `decisions` keyed by the
four profile IDs, `explanations` keyed by the ten exact input hashes, and a
`fallback_cases` list covering the four profiles. Each saved decision record
has `profile_hash`, `proposal` (only `ordered_priorities` and `rationale`),
`model_id`, `prompt_version`, stable `decision_id`, `expected_source: "ai"`,
and A/B review marks. Each explanation record has an `AIExplanation` with
`source: "ai"` and A/B review marks. Outage records use `proposal: null`,
`expected_source: "rules_fallback"`, and no model ID. The exporter validates
the records and does not invent a saved AI claim. Its command is:

```sh
cd backend
python -m scripts.export_demo --profiles fixtures/profiles.json \
  --decisions fixtures/decisions.json --output fixtures/generated
```

## Acceptance

Behavior tests cover Morgan's $963.80 opening extra debt payment, current versus
adaptive independence, all Custom modes, cap rounding, anniversary growth,
debt payoff and negative amortization, asset returns, cash interest,
inflation, milestones, every infeasibility path, deterministic hashes,
ten-artifact manifest and replay, stale saved content, and interrupted export
recovery. API and exporter must agree on numerical results for the same
validated inputs. Measure pure evaluation against the documented 250 ms
fixture target and perform the offline device handoff after A/B integration.

Plaid, provider orchestration, a decision store, Monte Carlo, and retirement
drawdown remain with other owners or outside the MVP.

## Implementation status and measurement

C's local suite passes 26 tests; five policy integration tests are skipped in
this branch because B's modules have not been merged. The same five tests pass
in a temporary checkout of Kevin's published branch with C's modules copied
in, including a ten-artifact export using clearly marked test-only saved text.
The checked-in reviewed bundle remains pending A's public schemas, explanation
evidence validator, and genuinely reviewed decision and explanation records.

On macOS 15.6.1 arm64 with Python 3.12.1, five provider-free evaluations per
canonical fixture using B's real policy had median runtimes of 98.4 ms for
Jordan, 97.3 ms for Morgan, and 19.1 ms for Casey. These meet the 250 ms demo
fixture target on this machine. iOS decoding and offline device checks remain
part of the final bundle handoff.
