# Fund shortlist: 401(k) and IRA

## Goal

Extend Adaptive Retirement from "how much and when to contribute" to an explainable shortlist of retirement funds. Keep the existing cash-flow plan unchanged. Rank only facts obtained from a validated catalog; language models may explain the ranking but may not create prices, fees, risk values, or returns.

## Two availability modes

- **401(k):** The user supplies or confirms their employer plan's investment menu. Recommend only exact fund/share-class identifiers on that menu. If the menu is unknown, show research candidates but do not say they can be purchased in the plan.
- **IRA:** Search the supported catalog. Label candidates "check availability at your brokerage" until brokerage eligibility, share-class minimums, transaction fees, and any restrictions are verified.

Never equate a fund's presence in a market-data catalog with its availability in a specific account.

## Required user inputs

Use the existing retirement age and financial profile. Add an explicit risk-tolerance answer (for example, willingness to stay invested through a significant temporary loss). Do not infer risk tolerance from age, debt, or cash balance. Age sets the horizon; debt and cash affect affordable contributions. The user may choose a different risk level after seeing the tradeoff.

## Catalog contract

Each fund must have a stable identifier including share class, name, type, target year if applicable, currency, expense ratio, stock/bond/other allocation, as-of date, original source, and source URL. Historical returns and volatility are optional, separately dated facts. Missing or stale required values exclude a fund from ranking rather than turning into zero. Fund minimums, brokerage/plan availability, and account fees are separately sourced facts.

Use an offline importer and a local, versioned SQLite catalog rather than calling a data provider for every user request. SQLite is included with Python and is sufficient for the normalized fund rows, source links, dates, and refresh metadata used by this prototype. The SEC ZIP archives remain import inputs outside the app bundle; the app reads only a compact validated snapshot. Validate source values and duplicates before publication. A failed refresh should retain the last valid catalog with its date visible, or return no shortlist if it is too old.

**API-call budget:** The selected SEC bulk-download and issuer-document path makes no EODHD Fundamentals calls. Opening the app, changing a scenario, changing risk tolerance, and reranking must read the local snapshot and make no data-provider calls. Optional EODHD Search discovery must have a small explicit call cap. If EODHD Fundamentals access is later enabled, its adapter needs allowance checks, deduplication, dated caching, bounded offline refreshes, and explicit percent-versus-fraction normalization before facts enter the catalog. Missing data must never be filled by model output.

## Ranking and presentation

1. Filter for account eligibility, valid data, suitable fund type/currency, and plausible retirement horizon.
2. Calculate a deterministic fit score from horizon alignment, explicit risk-tolerance alignment, and fees. Publish component scores and reason codes; do not use recent performance as a "winner" signal.
3. Return up to three candidates, including a meaningful tradeoff for each. Allow the user to inspect the full eligible set and change risk tolerance.
4. Show a defined risk band with its inputs (such as stock share and, when consistently available, historical volatility). A risk number is a model output, not a guarantee or a substitute for a suitability review.
5. Keep historical returns separate from low/base/high **hypothetical** future scenarios. Derive hypothetical returns from stated asset-class assumptions and the fund's allocation and fees. Display assumption date, time horizon, and limitations. Never present them as fund-specific forecasts or guaranteed rates.

## Product card

Show fund and share class; why shortlisted; account availability status; target year; current stock/bond/other mix; glide path when known; risk band and explanation; expense ratio and any known extra fees; historical returns labeled with period and date; hypothetical low/base/high scenario with assumptions; source and as-of date; and a link to the prospectus. Say "insufficient data" rather than filling gaps with AI.

## Integration order

1. Isolated typed ranking core and tests using synthetic catalog records.
2. Stage an SEC mutual-fund prospectus ZIP into local SQLite, preserving raw submission, fact, share-class, filing, and archive provenance. Then build a separate validated catalog adapter; review parsed fee tags against source filings before publishing ranked records.
3. Enrich current allocation, glide path, and prospectus URLs from issuer fact sheets; flag missing or stale fields. Build a server-owned catalog loader and separate shortlist API. Do not alter `/v1/evaluate` or its existing schema until the new contract is reviewed with the iOS owner.
4. Add the 401(k) plan-menu input and IRA brokerage availability checks. Then build the iOS shortlist screen and decode test.
5. Review the full user-facing advice and data-license obligations before use with real customers.

## Live EODHD coverage check (2026-09-26)

The locally configured key successfully searched for target-date funds: two bounded queries returned six distinct share-class tickers, including American Funds and Vanguard examples. Two Fundamentals requests returned HTTP 403. The key can therefore discover names but currently cannot supply the fee, allocation, or dated facts required for a ranked shortlist. A later zero-call `/api/user` check reported a 20-call daily allowance, 500 extra calls, and 518 calls remaining at that moment. Extra calls extend the budget; they do not establish Fundamentals entitlement. The EODHD documentation lists Fundamentals under its All-In-One and Fundamentals Data Feed plans; verify the account entitlement with EODHD before investing in the adapter. No key or raw provider payload is stored in this repository. The read-only audit can be rerun with `backend/scripts/audit_eodhd_funds.py` after access changes.

## External references

- SEC target-date fund bulletin: https://www.investor.gov/introduction-investing/general-resources/news-alerts/alerts-bulletins/investor-bulletins/target-date-funds-investor-bulletin
- SEC risk tolerance guidance: https://www.investor.gov/introduction-investing/investing-basics/save-and-invest/gauge-your-risk-tolerance
- SEC past-performance guidance: https://www.investor.gov/introduction-investing/investing-basics/glossary/mutual-funds-past-performance
- EODHD fund-data coverage and API: https://eodhd.com/financial-apis/stock-etfs-fundamental-data-feeds
- EODHD licensing: https://eodhd.com/financial-apis/commercial-vs-personal-license-use

## Selected primary-source path

The SEC publishes quarterly [Mutual Fund Prospectus Risk/Return Summary Data Sets](https://www.sec.gov/data-research/sec-markets-data/mutual-fund-prospectus-riskreturn-summary-data-sets). These provide structured text and numeric facts from prospectuses, including the risk/return summary that contains fund costs and historical performance. The [Form N-PORT data sets](https://www.sec.gov/data-research/sec-markets-data/form-n-port-data-sets) provide public portfolio holdings. Both are broad, free bulk downloads, but they are large and require careful parsing, share-class joins, date handling, and checking against the underlying filing. N-PORT holdings for a target-date fund of funds do not automatically give a clean stock/bond look-through allocation.

The selected no-paid-provider path is to build a versioned local target-date catalog from SEC prospectus data, then supplement current asset mix, glide path, and prospectus links from each issuer's public fact sheets. Start with a reviewed set spanning multiple issuers and retirement years, and expand only as records pass source and freshness checks. This uses no EODHD Fundamentals calls and can use the free EODHD Search endpoint only as an optional discovery aid. It still cannot assert that any candidate is available in a user's particular 401(k) without their plan menu.

The SEC 2026 Q2 ZIP could not be fetched programmatically from this environment because SEC.gov returned its automated-access policy page. After a manual download, `backend/scripts/import_sec_mfrr.py` successfully staged the official archive locally: 2,313 SUB, 537,808 NUM, and 638,111 TXT rows. SQLite integrity check passed. The staging database is `.tools/sec/2026q2.sqlite` (ignored by Git, about 985 MB); the original ZIP remains in the user's Downloads folder. Synthetic archive tests cover malformed-file rollback and raw-row preservation. The real archive contains repeated NUM composite keys, often with different values, so staging retains every row with its source row number instead of deduplicating it. This is raw staging, not a validated fund catalog: SEC tags still need fee normalization and source-filing review, and current allocation and glide-path facts need issuer enrichment before real funds can be ranked.

An initial target-date audit found that `PortfolioCompanyNameTextBlock` can name an underlying fund inside a variable-annuity filing and must not be treated as that fund's own filing. A bounded `RiskReturnHeading` audit with a nonempty series identified 136 accession-series candidates in this quarter; an earlier, narrower heading scan identified 507 associated series-class pairs with raw fee-tag facts, so that pair count is not a complete total for the 136 candidates. The dedicated SEC `class` columns were blank, while class identifiers appeared in `otherdims` as `Class=C#########;`. These are discovery counts, not a validated product catalog. One quarter is incomplete, and class labels, fee semantics, current allocation, prospectus links, and availability still need review.

`backend/scripts/audit_sec_candidates.py` exports a bounded, read-only JSON review list from the staging database. It records the original heading, target year, exact class token when present, raw fee-tag values, document, filing, and source row; conflicts and missing mappings remain explicit flags. Its output is for source review only and must not be passed directly into the ranking engine. A sample of three candidates was written locally to ignored `.tools/sec/candidates-sample.json`.
