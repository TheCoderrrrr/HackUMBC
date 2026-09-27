"""Small read-only EODHD target-date fund coverage audit.

Run from backend/: python scripts/audit_eodhd_funds.py --help
The key is read from EODHD_API_KEY or backend/.env. No provider values are
normalized into FundFacts; this script reports raw labels and samples only.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

from dotenv import load_dotenv


BASE_URL = "https://eodhd.com"
MAX_QUERIES = 3
MAX_SEARCH_LIMIT = 5
MAX_FUNDAMENTALS = 5
SEARCH_CALL_COST = 1
FUNDAMENTALS_CALL_COST = 10
MAX_PLANNED_CALLS = MAX_QUERIES * SEARCH_CALL_COST + MAX_FUNDAMENTALS * FUNDAMENTALS_CALL_COST
MAX_RESPONSE_BYTES = 2_000_000
DEFAULT_TIMEOUT_SECONDS = 6.0
MUTUAL_FUND_FIELDS = ("Update_Date", "Expense_Ratio", "Expense_Ratio_Date", "Asset_Allocation")
TARGET_NAME_PATTERN = re.compile(r"target|retirement", re.IGNORECASE)


class AuditError(RuntimeError):
    """A safe error message that never includes a credentialed URL or body."""


def parse_account_usage(payload: object, *, today: date | None = None) -> dict[str, object]:
    """Read only the four documented /api/user budget fields; fail closed."""
    if not isinstance(payload, dict):
        raise AuditError("Account usage response was not an object")
    expected_date = today or datetime.now(timezone.utc).date()
    raw_date = payload.get("apiRequestsDate")
    if not isinstance(raw_date, str) or not re.match(r"^\d{4}-\d{2}-\d{2}(?:$|[ T])", raw_date):
        raise AuditError("Account usage date is unavailable")
    try:
        usage_date = date.fromisoformat(raw_date[:10])
    except ValueError:
        raise AuditError("Account usage date is invalid") from None
    if usage_date != expected_date:
        raise AuditError("Account usage date is not current UTC date")
    values: dict[str, int] = {}
    for field in ("apiRequests", "dailyRateLimit", "extraLimit"):
        raw = payload.get(field)
        if isinstance(raw, bool) or not isinstance(raw, (int, str)) or not str(raw).isdigit():
            raise AuditError(f"Account {field} is unavailable")
        values[field] = int(raw)
    total_limit = values["dailyRateLimit"] + values["extraLimit"]
    return {
        "usage_date": usage_date.isoformat(),
        "api_requests_used": values["apiRequests"],
        "daily_rate_limit": values["dailyRateLimit"],
        "extra_limit": values["extraLimit"],
        "remaining_calls": max(0, total_limit - values["apiRequests"]),
    }


def parse_search_results(payload: object) -> list[dict[str, str]]:
    """Keep only identifying fields from the bounded search response."""
    if not isinstance(payload, list):
        raise AuditError("Search response was not a list")
    results: list[dict[str, str]] = []
    for item in payload:
        if not isinstance(item, dict):
            continue
        code = item.get("Code")
        name = item.get("Name")
        exchange = item.get("Exchange") or "US"
        if not isinstance(code, str) or not code.strip() or not isinstance(name, str):
            continue
        if not isinstance(exchange, str) or not exchange.strip():
            exchange = "US"
        code, exchange = code.strip(), exchange.strip()
        ticker = code if "." in code else f"{code}.{exchange}"
        results.append({
            "ticker": ticker, "code": code, "name": name.strip(),
            "exchange": exchange, "type": str(item.get("Type") or ""),
        })
    return results


def _small_raw(value: object, *, depth: int = 2) -> object:
    """Preserve provider labels and scalar units without dumping entire records."""
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return value[:100]
    if depth <= 0:
        return "[nested value omitted]"
    if isinstance(value, dict):
        return {str(key)[:80]: _small_raw(item, depth=depth - 1)
                for key, item in list(value.items())[:6]}
    if isinstance(value, list):
        return [_small_raw(item, depth=depth - 1) for item in value[:6]]
    return f"[unsupported {type(value).__name__}]"


def _prospectus_paths(payload: object, *, depth: int = 4, prefix: str = "") -> list[str]:
    if depth <= 0:
        return []
    paths: list[str] = []
    if isinstance(payload, dict):
        for key, value in list(payload.items())[:100]:
            if not isinstance(key, str):
                continue
            path = f"{prefix}.{key}" if prefix else key
            if "prospectus" in key.lower():
                paths.append(path)
            paths.extend(_prospectus_paths(value, depth=depth - 1, prefix=path))
    elif isinstance(payload, list):
        for value in payload[:5]:
            paths.extend(_prospectus_paths(value, depth=depth - 1, prefix=prefix))
    return sorted(set(paths))[:10]


def summarize_fundamentals(payload: object, ticker: str) -> dict[str, object]:
    """Report raw mutual-fund fields and whether prospectus-like keys exist."""
    if not isinstance(payload, dict):
        raise AuditError("Fundamentals response was not an object")
    mutual = payload.get("MutualFund_Data")
    if not isinstance(mutual, dict):
        mutual = {}
    presence = {field: field in mutual and mutual[field] is not None
                for field in MUTUAL_FUND_FIELDS}
    return {
        "ticker": ticker,
        "mutual_fund_data_present": isinstance(payload.get("MutualFund_Data"), dict),
        "fields_present": presence,
        "update_date_raw": _small_raw(mutual.get("Update_Date")),
        "expense_ratio_raw": _small_raw(mutual.get("Expense_Ratio")),
        "expense_ratio_date_raw": _small_raw(mutual.get("Expense_Ratio_Date")),
        "asset_allocation_raw_sample": _small_raw(mutual.get("Asset_Allocation")),
        "prospectus_key_paths": _prospectus_paths(payload),
    }


def _fetch_json(path: str, params: dict[str, object], key: str, timeout: float) -> object:
    """One bounded GET; exception text never contains the request URL or key."""
    query = urlencode({**params, "api_token": key})
    request = Request(f"{BASE_URL}{path}?{query}", headers={"Accept": "application/json"})
    try:
        with urlopen(request, timeout=timeout) as response:
            data = response.read(MAX_RESPONSE_BYTES + 1)
    except HTTPError as exc:
        raise AuditError(f"HTTP {exc.code}") from None
    except (URLError, TimeoutError):
        raise AuditError("Network error or timeout") from None
    if len(data) > MAX_RESPONSE_BYTES:
        raise AuditError("Response exceeded audit size limit")
    try:
        return json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise AuditError("Response was not valid JSON") from None


def run_audit(
    key: str, queries: list[str], *, search_limit: int,
    max_fundamentals: int = 0, max_calls: int = 2,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    skip_if_insufficient: bool = False,
) -> dict[str, object]:
    """Check free account usage, then stay within both paid-call budgets."""
    if not key or not 1 <= len(queries) <= MAX_QUERIES or any(not query.strip() for query in queries):
        raise ValueError("A key and one to three nonempty queries are required")
    if not 1 <= search_limit <= MAX_SEARCH_LIMIT or not 0 <= max_fundamentals <= MAX_FUNDAMENTALS:
        raise ValueError("Audit call limits are outside the allowed range")
    if isinstance(max_calls, bool) or not 0 <= max_calls <= MAX_PLANNED_CALLS:
        raise ValueError("Maximum calls are outside the allowed range")
    if not 1 <= timeout <= 10:
        raise ValueError("Timeout must be between 1 and 10 seconds")
    planned_calls = len(queries) * SEARCH_CALL_COST + max_fundamentals * FUNDAMENTALS_CALL_COST
    try:
        usage = parse_account_usage(_fetch_json("/api/user", {}, key, timeout))
    except AuditError:
        if skip_if_insufficient:
            return {"status": "skipped", "reason_code": "USAGE_UNAVAILABLE",
                    "planned_call_cost": planned_calls, "estimated_calls_used": 0,
                    "estimated_calls_remaining_today": None}
        raise AuditError("Account usage is unavailable; no paid audit requests were made") from None
    remaining = usage["remaining_calls"]
    if planned_calls > max_calls or planned_calls > remaining:
        if skip_if_insufficient:
            return {"status": "skipped", "reason_code": "INSUFFICIENT_CALL_BUDGET",
                    "planned_call_cost": planned_calls, "estimated_calls_used": 0,
                    "estimated_calls_remaining_today": remaining,
                    "account_usage": usage}
        raise AuditError("Planned audit exceeds the local cap or account remaining calls; no paid requests were made")

    spent_calls = 0

    def charge(cost: int) -> None:
        nonlocal spent_calls
        if spent_calls + cost > max_calls or spent_calls + cost > remaining:
            raise AuditError("Call budget exhausted; stopping before the next paid request")
        # Charge before the request: a failed HTTP response may still count.
        spent_calls += cost

    found: dict[str, dict[str, str]] = {}
    search_errors: list[dict[str, str]] = []
    search_counts: dict[str, int] = {}
    for query in queries:
        charge(SEARCH_CALL_COST)
        try:
            payload = _fetch_json(
                f"/api/search/{quote(query.strip(), safe='')}",
                {"limit": search_limit, "type": "fund", "exchange": "US"},
                key, timeout,
            )
            rows = parse_search_results(payload)[:search_limit]
        except AuditError as exc:
            if str(exc) in {"HTTP 402", "HTTP 403"}:
                raise AuditError(f"{exc}; stopping without retry") from None
            search_errors.append({"query": query, "error": str(exc)})
            continue
        search_counts[query] = len(rows)
        for row in rows:
            found.setdefault(row["ticker"], row)

    candidates = list(found.values())
    target_named = [item for item in candidates if TARGET_NAME_PATTERN.search(item["name"])]
    sample = (target_named or candidates)[:max_fundamentals]
    summaries: list[dict[str, object]] = []
    fundamentals_errors: list[dict[str, str]] = []
    for item in sample:
        charge(FUNDAMENTALS_CALL_COST)
        try:
            payload = _fetch_json(
                f"/api/v1.1/fundamentals/{quote(item['ticker'], safe='')}",
                {"fmt": "json"}, key, timeout,
            )
            summaries.append(summarize_fundamentals(payload, item["ticker"]))
        except AuditError as exc:
            if str(exc) in {"HTTP 402", "HTTP 403"}:
                raise AuditError(f"{exc}; stopping without retry") from None
            fundamentals_errors.append({"ticker": item["ticker"], "error": str(exc)})
    field_counts = Counter()
    for summary in summaries:
        field_counts.update({key: present for key, present in summary["fields_present"].items()
                             if present})
    return {
        "status": "complete",
        "account_usage": usage,
        "planned_call_cost": planned_calls,
        "estimated_calls_used": spent_calls,
        "estimated_calls_remaining_today": remaining - spent_calls,
        "local_call_budget_remaining": max_calls - spent_calls,
        "queries": queries,
        "search_result_counts": search_counts,
        "search_errors": search_errors,
        "unique_candidate_count": len(candidates),
        "target_named_candidate_count": len(target_named),
        "candidate_identifiers_and_names": candidates[:MAX_QUERIES * MAX_SEARCH_LIMIT],
        "fundamentals_attempted": len(sample),
        "fundamentals_succeeded": len(summaries),
        "fundamentals_failed": len(fundamentals_errors),
        "fundamentals_errors": fundamentals_errors,
        "field_present_counts": {field: field_counts[field] for field in MUTUAL_FUND_FIELDS},
        "field_missing_counts": {field: len(summaries) - field_counts[field]
                                 for field in MUTUAL_FUND_FIELDS},
        "fundamentals_samples": summaries,
        "note": "Raw provider values are not normalized, ranked, or inferred as a prospectus URL.",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--query", action="append", dest="queries", help="Search phrase; repeat up to three times")
    parser.add_argument("--limit", type=int, default=5, help="Search results per phrase (1-5)")
    parser.add_argument("--max-fundamentals", type=int, default=0,
                        help="Fundamentals records to inspect (0-5; 10 calls each, default 0)")
    parser.add_argument("--max-calls", type=int, default=2,
                        help="Hard maximum paid EODHD call units for this run (default 2)")
    parser.add_argument("--skip-if-insufficient", action="store_true",
                        help="Report a skipped audit instead of failing when usage/cap is insufficient")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS,
                        help="Timeout per request in seconds (1-10)")
    args = parser.parse_args(argv)
    load_dotenv(Path(__file__).resolve().parents[1] / ".env", override=False)
    key = os.environ.get("EODHD_API_KEY", "").strip()
    if not key:
        print("EODHD_API_KEY is not configured in the environment or backend/.env", file=sys.stderr)
        return 2
    queries = args.queries or ["target retirement", "target date"]
    try:
        report = run_audit(
            key, queries, search_limit=args.limit,
            max_fundamentals=args.max_fundamentals, max_calls=args.max_calls,
            timeout=args.timeout, skip_if_insufficient=args.skip_if_insufficient,
        )
    except (AuditError, ValueError) as exc:
        print(f"Audit failed: {str(exc).replace(key, '[REDACTED]')}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2, ensure_ascii=False).replace(key, "[REDACTED]"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
