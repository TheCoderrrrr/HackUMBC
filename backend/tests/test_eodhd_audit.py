"""Offline tests for the bounded EODHD audit; no provider requests."""

from datetime import datetime, timezone
from urllib.error import HTTPError, URLError

import pytest

from scripts import audit_eodhd_funds as audit


def usage(*, used=4, limit=100, extra=0):
    return {
        "apiRequests": used, "apiRequestsDate": datetime.now(timezone.utc).date().isoformat(),
        "dailyRateLimit": limit, "extraLimit": extra,
        "name": "Private User", "email": "private@example.test", "apiToken": "secret",
    }


def test_search_parser_keeps_identifiers_without_inventing_facts():
    rows = audit.parse_search_results([
        {"Code": "ABC", "Name": "Synthetic Target Retirement 2045", "Exchange": "US", "Type": "FUND"},
        {"Code": "XYZ.US", "Name": "Synthetic Fund", "Type": "FUND"},
        {"Code": "", "Name": "Incomplete"},
        {"Name": "No code"},
    ])
    assert rows == [
        {"ticker": "ABC.US", "code": "ABC", "name": "Synthetic Target Retirement 2045",
         "exchange": "US", "type": "FUND"},
        {"ticker": "XYZ.US", "code": "XYZ.US", "name": "Synthetic Fund",
         "exchange": "US", "type": "FUND"},
    ]
    with pytest.raises(audit.AuditError):
        audit.parse_search_results({"error": "not a list"})


def test_fundamentals_summary_preserves_raw_units_and_only_key_paths():
    payload = {
        "MutualFund_Data": {
            "Update_Date": "2026-09-20",
            "Expense_Ratio": "0.0200",
            "Expense_Ratio_Date": "2025-12-31",
            "Asset_Allocation": {
                "Stocks": {"Net_%": "85.3"},
                "Bonds": {"Net_%": "12.5"},
            },
        },
        "Documents": {"ProspectusURL": "https://example.test/document"},
    }
    result = audit.summarize_fundamentals(payload, "ABC.US")
    assert all(result["fields_present"].values())
    assert result["expense_ratio_raw"] == "0.0200"
    assert result["asset_allocation_raw_sample"]["Stocks"]["Net_%"] == "85.3"
    assert result["prospectus_key_paths"] == ["Documents.ProspectusURL"]
    assert "https://example.test/document" not in str(result)
    assert result["update_date_raw"] == "2026-09-20"


def test_missing_mutual_fund_data_is_reported_not_filled():
    summary = audit.summarize_fundamentals({"General": {"Name": "Example"}}, "ABC.US")
    assert not summary["mutual_fund_data_present"]
    assert not any(summary["fields_present"].values())
    assert summary["expense_ratio_raw"] is None
    assert summary["asset_allocation_raw_sample"] is None


def test_run_audit_bounds_requests_deduplicates_and_counts_fields(monkeypatch):
    calls = []

    def fake_fetch(path, params, key, timeout):
        calls.append((path, dict(params), timeout))
        if path == "/api/user":
            return usage()
        if path.startswith("/api/search/"):
            return [
                {"Code": "ABC", "Name": "Target Retirement 2045", "Exchange": "US"},
                {"Code": "XYZ", "Name": "Generic Fund", "Exchange": "US"},
            ]
        assert path == "/api/v1.1/fundamentals/ABC.US"
        return {"MutualFund_Data": {"Update_Date": "2026-09-20", "Expense_Ratio": "0.02"}}

    monkeypatch.setattr(audit, "_fetch_json", fake_fetch)
    report = audit.run_audit(
        "secret", ["target retirement", "target date"],
        search_limit=2, max_fundamentals=1, max_calls=12, timeout=4,
    )
    assert len(calls) == 4  # free usage, two searches, one fundamentals call
    assert calls[0][0] == "/api/user"
    assert all(call[1].get("type") == "fund" for call in calls[1:3])
    assert report["unique_candidate_count"] == 2
    assert report["target_named_candidate_count"] == 1
    assert report["fundamentals_attempted"] == report["fundamentals_succeeded"] == 1
    assert report["field_present_counts"] == {
        "Update_Date": 1, "Expense_Ratio": 1,
        "Expense_Ratio_Date": 0, "Asset_Allocation": 0,
    }
    assert report["field_missing_counts"] == {
        "Update_Date": 0, "Expense_Ratio": 0,
        "Expense_Ratio_Date": 1, "Asset_Allocation": 1,
    }
    assert report["planned_call_cost"] == report["estimated_calls_used"] == 12
    assert report["estimated_calls_remaining_today"] == 84
    assert "secret" not in str(report)
    assert "Private User" not in str(report)
    assert "private@example.test" not in str(report)


@pytest.mark.parametrize("queries,limit,max_fundamentals,timeout", [
    (["a", "b", "c", "d"], 1, 1, 1),
    (["a"], 6, 1, 1),
    (["a"], 1, 6, 1),
    (["a"], 1, 1, 11),
])
def test_run_audit_rejects_unbounded_calls_before_network(
    monkeypatch, queries, limit, max_fundamentals, timeout,
):
    monkeypatch.setattr(audit, "_fetch_json", lambda *args: pytest.fail("network should not be called"))
    with pytest.raises(ValueError):
        audit.run_audit("key", queries, search_limit=limit,
                        max_fundamentals=max_fundamentals, timeout=timeout)


def test_fetch_errors_never_expose_credentialed_url(monkeypatch):
    secret_url = "https://eodhd.com/api/search/x?api_token=super-secret"

    def fail_http(*args, **kwargs):
        raise HTTPError(secret_url, 403, "Forbidden", None, None)

    monkeypatch.setattr(audit, "urlopen", fail_http)
    with pytest.raises(audit.AuditError, match="HTTP 403") as error:
        audit._fetch_json("/api/search/x", {}, "super-secret", 1)
    assert "super-secret" not in str(error.value)
    assert "https://" not in str(error.value)

    monkeypatch.setattr(audit, "urlopen", lambda *args, **kwargs: (_ for _ in ()).throw(URLError(secret_url)))
    with pytest.raises(audit.AuditError, match="Network error or timeout") as error:
        audit._fetch_json("/api/search/x", {}, "super-secret", 1)
    assert "super-secret" not in str(error.value)


def test_partial_provider_failure_is_counted_without_raw_error(monkeypatch):
    def fake_fetch(path, params, key, timeout):
        if path == "/api/user":
            return usage()
        if path.startswith("/api/search/"):
            return [{"Code": "ABC", "Name": "Target Retirement", "Exchange": "US"}]
        raise audit.AuditError("HTTP 429")

    monkeypatch.setattr(audit, "_fetch_json", fake_fetch)
    report = audit.run_audit("secret", ["target"], search_limit=1,
                             max_fundamentals=1, max_calls=11, timeout=2)
    assert report["fundamentals_attempted"] == 1
    assert report["fundamentals_succeeded"] == 0
    assert report["fundamentals_failed"] == 1
    assert report["fundamentals_errors"] == [{"ticker": "ABC.US", "error": "HTTP 429"}]
    assert "secret" not in str(report)


def test_default_budget_is_search_only(monkeypatch):
    calls = []

    def fake_fetch(path, params, key, timeout):
        calls.append(path)
        if path == "/api/user":
            return usage(used=1, limit=3)
        assert path.startswith("/api/search/")
        return [{"Code": "ABC", "Name": "Target Retirement", "Exchange": "US"}]

    monkeypatch.setattr(audit, "_fetch_json", fake_fetch)
    report = audit.run_audit("secret", ["target retirement", "target date"], search_limit=1)
    assert len(calls) == 3
    assert report["fundamentals_attempted"] == 0
    assert report["estimated_calls_used"] == 2
    assert report["estimated_calls_remaining_today"] == 0


def test_local_cap_blocks_fundamentals_before_any_paid_call(monkeypatch):
    calls = []

    def fake_fetch(path, params, key, timeout):
        calls.append(path)
        return usage()

    monkeypatch.setattr(audit, "_fetch_json", fake_fetch)
    with pytest.raises(audit.AuditError, match="Planned audit exceeds"):
        audit.run_audit("secret", ["target"], search_limit=1,
                        max_fundamentals=1, max_calls=2)
    assert calls == ["/api/user"]


def test_provider_remaining_blocks_audit_or_skips_whole_run(monkeypatch):
    calls = []

    def fake_fetch(path, params, key, timeout):
        calls.append(path)
        return usage(used=9, limit=10)

    monkeypatch.setattr(audit, "_fetch_json", fake_fetch)
    with pytest.raises(audit.AuditError, match="Planned audit exceeds"):
        audit.run_audit("secret", ["one", "two"], search_limit=1)
    skipped = audit.run_audit("secret", ["one", "two"], search_limit=1,
                              skip_if_insufficient=True)
    assert skipped["status"] == "skipped"
    assert skipped["estimated_calls_used"] == 0
    assert skipped["estimated_calls_remaining_today"] == 1
    assert calls == ["/api/user", "/api/user"]


def test_usage_failure_or_missing_fields_blocks_paid_calls(monkeypatch):
    calls = []

    def fake_fetch(path, params, key, timeout):
        calls.append(path)
        return {"name": "Private User", "email": "private@example.test"}

    monkeypatch.setattr(audit, "_fetch_json", fake_fetch)
    with pytest.raises(audit.AuditError, match="Account usage is unavailable"):
        audit.run_audit("secret", ["target"], search_limit=1)
    skipped = audit.run_audit("secret", ["target"], search_limit=1,
                              skip_if_insufficient=True)
    assert skipped["reason_code"] == "USAGE_UNAVAILABLE"
    assert "Private User" not in str(skipped)
    assert calls == ["/api/user", "/api/user"]


def test_usage_parser_reads_allowlist_and_rejects_stale_or_bad_values():
    today = datetime.now(timezone.utc).date()
    parsed = audit.parse_account_usage(usage(used="2", limit="10", extra="5"), today=today)
    assert parsed["remaining_calls"] == 13
    assert set(parsed) == {"usage_date", "api_requests_used", "daily_rate_limit",
                           "extra_limit", "remaining_calls"}
    bad = usage()
    bad["dailyRateLimit"] = None
    with pytest.raises(audit.AuditError):
        audit.parse_account_usage(bad, today=today)
    bad = usage()
    bad["apiRequestsDate"] = "2000-01-01"
    with pytest.raises(audit.AuditError):
        audit.parse_account_usage(bad, today=today)


def test_403_stops_without_retrying_next_search(monkeypatch):
    calls = []

    def fake_fetch(path, params, key, timeout):
        calls.append(path)
        if path == "/api/user":
            return usage()
        raise audit.AuditError("HTTP 403")

    monkeypatch.setattr(audit, "_fetch_json", fake_fetch)
    with pytest.raises(audit.AuditError, match="stopping without retry"):
        audit.run_audit("secret", ["one", "two"], search_limit=1)
    assert len(calls) == 2


def test_help_and_missing_key_require_no_network(monkeypatch, capsys):
    with pytest.raises(SystemExit) as result:
        audit.main(["--help"])
    assert result.value.code == 0
    assert "max-fundamentals" in capsys.readouterr().out
    monkeypatch.delenv("EODHD_API_KEY", raising=False)
    monkeypatch.setattr(audit, "load_dotenv", lambda *args, **kwargs: None)
    assert audit.main(["--query", "target retirement"]) == 2
    assert "not configured" in capsys.readouterr().err
