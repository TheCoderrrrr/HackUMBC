# Fund feature handoff — fund developer

Read this alongside [FUND_SHORTLIST_PLAN.md](FUND_SHORTLIST_PLAN.md), [BACKEND.md](BACKEND.md), and [BACKEND_TEAM_SPLIT.md](BACKEND_TEAM_SPLIT.md). This work adds an explainable target-date fund shortlist for both IRA and 401(k) users. It does not replace the existing retirement cash-flow plan.

## Status when switching to Cursor

- **Implemented locally:** `backend/app/funds.py` contains typed `FundFacts`, shortlist request/response models, deterministic filtering/scoring, a 1–5 equity-weight risk proxy, and clearly hypothetical low/base/high return scenarios. Its tests use synthetic fund facts. It is **not connected to an API or screen**.
- **Real SEC staging works:** `backend/scripts/import_sec_mfrr.py` imported the official 2026 Q2 MFRR ZIP into ignored `.tools/sec/2026q2.sqlite` (about 985 MB). Import counts: 2,313 SUB, 537,808 NUM, 638,111 TXT. SQLite integrity check passed. Original ZIP: `C:\Users\kevin\Downloads\2026q2_rr1.zip`. These local data files are not shared through Git.
- **Discovery only:** `backend/scripts/audit_sec_candidates.py` produces a bounded, unverified JSON review list. The latest run found 136 accession/series candidates. Sample output: ignored `.tools/sec/candidates-sample.json`. No real fund has been promoted to `FundFacts` yet.
- **EODHD free-plan limit:** Search worked, but Fundamentals returned HTTP 403. The selected path is SEC filings plus issuer documents. Do not spend EODHD calls on each user request or put its key in code.
- **Verification:** 65 focused tests passed across `test_funds.py`, `test_sec_mfrr.py`, `test_sec_candidate_audit.py`, and `test_eodhd_audit.py`. This is not a claim that the new feature is end-to-end complete.

All files named above, their tests, and `FUND_SHORTLIST_PLAN.md` are currently **untracked**. They exist in this workspace but will not appear in a fresh clone until committed and pushed. Check `git status --short` first. Never commit `backend/.env`, `.tools/`, the SEC ZIP, or generated SQLite/JSON data.

## Your next tasks, in order

1. **Validate a small issuer/share-class set.** Start with a few target-date years and more than one issuer. For every candidate, confirm the exact SEC series/class ID, marketed class name, target year, fee meaning (gross versus net, waivers, acquired-fund fees), filing/effective date, and source URL against its original prospectus. The raw SEC `class` columns are blank in this archive; class IDs often appear in `otherdims` as `Class=C#########;`. Duplicate NUM composite keys can have different values. Do not pick a fee merely by tag name or first row.
2. **Add current allocation from issuer material.** Record stock/bond/other weights, their as-of date and source URL, and any known glide path. Target-date funds of funds are not reliably classified by simply counting their top-level SEC/N-PORT holdings. Reject ambiguous or stale records. Fund names inside `PortfolioCompanyNameTextBlock` may be annuity options, not filings by the named fund issuer.
3. **Create a compact, reviewed catalog adapter.** Convert only validated evidence to `FundFacts` in `backend/app/funds.py`. Store each datum's provenance and date; keep raw staging separate. Missing fee or allocation must exclude a fund from ranking. Preserve exact share-class identity, and make catalog publication versioned/atomic so a failed refresh retains the previous valid snapshot.
4. **Expose a separate shortlist API and integrate the UI.** Add explicit risk-tolerance and account-type inputs. A 401(k) user with a confirmed menu can receive only matching share classes; an unknown menu gets clearly labeled research candidates. IRA discoveries remain unconfirmed until brokerage availability, minimums, and transaction fees are checked. Do not change `/v1/evaluate` or its existing response contract without coordinating with the iOS owner.
5. **Show the tradeoffs honestly.** Display expense ratio, allocation, source/as-of date, prospectus link, eligibility status, why a fund matched, and risk-band inputs. Keep historical returns separate from hypothetical future scenarios; never label the latter as predicted returns.

The immediate deliverable is a small **verified** catalog and an end-to-end shortlist using it. A broad unreviewed SEC name list is not a usable recommendation catalog; expand coverage after the first records pass review.

## Commands from the repository root (PowerShell)

```powershell
git status --short
.\.venv\Scripts\python.exe -m pytest backend/tests/test_funds.py backend/tests/test_sec_mfrr.py backend/tests/test_sec_candidate_audit.py backend/tests/test_eodhd_audit.py -q
.\.venv\Scripts\python.exe backend/scripts/import_sec_mfrr.py --zip C:\Users\kevin\Downloads\2026q2_rr1.zip --db .tools\sec\2026q2.sqlite
.\.venv\Scripts\python.exe backend/scripts/audit_sec_candidates.py --db .tools\sec\2026q2.sqlite --output .tools\sec\candidates-sample.json --limit 3
```

The importer replaces the staging DB after a successful read; rerun it only when needed. The audit output is for review, not a live app catalog. The SEC publishes the [MFRR archives](https://www.sec.gov/data-research/sec-markets-data/mutual-fund-prospectus-riskreturn-summary-data-sets) and [field definitions](https://www.sec.gov/files/rr1.pdf).

## Boundary with the Tiger Data developer

You own `backend/app/funds.py`, the SEC scripts/tests, the validated catalog, shortlist API, and fund UI contract. Your partner owns a separate time-series scenario-history path. Neither feature needs the other's database to proceed. Coordinate only on a later optional, compact dated-fund-fact export; never send the raw SEC staging database to Tiger Data as a prerequisite.

