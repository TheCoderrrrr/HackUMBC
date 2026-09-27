# Fund shortlist: 401(k) and IRA

An explainable shortlist of target-date funds, next to the existing cash-flow plan (which it does not change). Only facts from a reviewed catalog are ranked; language models may explain a ranking but may never create prices, fees, risk values, or returns. Missing data is never filled by model output.

## Status

| Piece | Where | State |
|---|---|---|
| Ranking core: `FundFacts`, filtering, fit score, 1–5 risk band, hypothetical low/base/high scenarios | `backend/app/funds.py` | Done |
| Reviewed catalog, version `2026-09-26.1` | `backend/app/data/fund_catalog.json` | Six Class K funds |
| Catalog adapter: validation, waiver-aware fees, atomic publish, last-good snapshot | `backend/app/fund_catalog.py` | Done |
| API: `GET /v1/funds/catalog`, `POST /v1/funds/shortlist` | `backend/app/fund_api.py` | Done; `/v1/evaluate` unchanged |
| Desktop "Fund shortlist" tab | `desktop/src/views/Funds.tsx` | Done |
| iOS screen | none | Not started |
| Tests | `backend/tests/test_funds.py`, `test_fund_catalog.py`, `test_sec_*.py`, `test_eodhd_audit.py` | Passing |

The catalog holds BlackRock LifePath Index 2030/2035/2055/2060 and State Street Target Retirement 2030/2055. Every fee, allocation, glide-path, and return value cites its SEC filing, location, and date, and was checked against the rendered filing, not only staging rows. Scope is target-date funds only; index funds and ETFs would need a different "fit" model.

> [!WARNING]
> **Holdings expire on 2026-09-29.** Allocations are as of 2026-06-30 and `MAX_HOLDINGS_AGE_DAYS` is 90, so every fund is excluded as `STALE_FACTS` from that date. Refresh from the next N-PORT or shareholder report (newer data, not older), or deliberately change the policy.

## Two availability modes

- **401(k):** the user supplies their plan's menu. Recommend only exact share classes on it. With no menu, show clearly labeled research candidates, never "available in your plan".
- **IRA:** search the catalog and label candidates "check availability at your brokerage" until eligibility, minimums, and transaction fees are verified.

A fund's presence in a data catalog never means it is available in a specific account.

## Inputs and ranking

Use the existing retirement age and profile, plus an explicit risk-tolerance answer. Never infer risk tolerance from age, debt, or cash. Age sets the horizon; debt and cash affect affordable contributions.

1. Filter for account eligibility, valid and fresh data, fund type/currency, and plausible horizon.
2. Score deterministically from horizon alignment, risk alignment, and fees. Publish component scores and reason codes; recent performance is never a "winner" signal.
3. Return up to three candidates with a tradeoff each, and let the user see the full eligible set.
4. Show the risk band with its inputs. It is a model output, not a guarantee or a suitability review.
5. Keep historical returns separate from hypothetical scenarios derived from stated asset-class assumptions, allocation, and fees. Never call the latter forecasts.

The product card shows fund and share class, why it matched, availability status, target year, stock/bond/other mix, glide path, risk band, expense ratio (net while a waiver lasts, gross after), dated historical returns, the labeled hypothetical, source and as-of date, and a prospectus link. Gaps say "insufficient data".

## Catalog contract

Each record needs a stable share-class ID, name, type, target year, currency, expense ratio, allocation, as-of date, and source URL. Returns are optional, separately dated facts. Missing or stale required values exclude a fund instead of becoming zero. Freshness limits live in `funds.py`: holdings 90 days, fees 548 days, history 548 days.

`fund_catalog.py` rejects a record unless gross fee minus waiver equals net, every waiver has an end date, equity plus bond is at least 95% of the allocation, and every citation resolves. `publish_catalog` writes through a temp file and `os.replace`; `CatalogStore` keeps serving the last valid snapshot and records `last_error` when a refresh is bad.

## Adding or refreshing funds

1. For each candidate, confirm the SEC series/class ID, marketed class name, target year, fee meaning (gross vs. net, waivers, acquired-fund fees), filing date, and source URL against the original filing. Class IDs are in filing headers or in MFRR `otherdims` as `Class=C#########;` (the `class` columns are blank). Duplicate NUM keys can carry different values, so never pick a fee by tag name or first row.
2. Take current allocation from the issuer's N-CSR/N-CSRS or N-PORT holdings by category. Target-date funds of funds can't be classified by counting top-level holdings. `PortfolioCompanyNameTextBlock` may name an annuity option, not the fund's own filing.
3. Add the reviewed record to `fund_catalog.json`, bump its version, and run the tests.

### SEC staging (optional discovery)

`backend/scripts/import_sec_mfrr.py` stages a quarterly [MFRR archive](https://www.sec.gov/data-research/sec-markets-data/mutual-fund-prospectus-riskreturn-summary-data-sets) ([field definitions](https://www.sec.gov/files/rr1.pdf)) into ignored `.tools/sec/2026q2.sqlite` (about 985 MB; 2,313 SUB, 537,808 NUM, 638,111 TXT rows). SEC.gov blocks scripted downloads, so fetch the ZIP manually. `audit_sec_candidates.py` writes a bounded, unverified review list (136 series candidates in 2026 Q2). Its output is for review only and must never feed the ranking engine.

```powershell
.\.venv\Scripts\python.exe backend/scripts/import_sec_mfrr.py --zip C:\Users\kevin\Downloads\2026q2_rr1.zip --db .tools\sec\2026q2.sqlite
.\.venv\Scripts\python.exe backend/scripts/audit_sec_candidates.py --db .tools\sec\2026q2.sqlite --output .tools\sec\candidates-sample.json --limit 3
```

Never commit `backend/.env`, `.tools/`, the SEC ZIP, or generated SQLite/JSON data. Never send the raw staging database to Tiger Data.

### EODHD

The free key can search fund names but Fundamentals returns HTTP 403, so it can't supply fees or allocations. Do not spend EODHD calls on user requests or put its key in code. `backend/scripts/audit_eodhd_funds.py` rechecks access if the plan changes.

## Remaining work

- Refresh holdings before 2026-09-29.
- iOS shortlist screen and decode test against `contracts/openapi.json`.
- Add more issuers and target years as records pass review.
- Review user-facing advice wording and data-license obligations before any real-customer use.

## References

- [SEC target-date fund bulletin](https://www.investor.gov/introduction-investing/general-resources/news-alerts/alerts-bulletins/investor-bulletins/target-date-funds-investor-bulletin)
- [SEC risk tolerance guidance](https://www.investor.gov/introduction-investing/investing-basics/save-and-invest/gauge-your-risk-tolerance)
- [SEC past-performance guidance](https://www.investor.gov/introduction-investing/investing-basics/glossary/mutual-funds-past-performance)
- [Form N-PORT data sets](https://www.sec.gov/data-research/sec-markets-data/form-n-port-data-sets)
