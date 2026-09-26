from __future__ import annotations

from app.schemas import Evaluation

from .conftest import FakeModel, make_client


def test_health_reports_versions():
    body = make_client().get("/health").json()
    assert body == {"status": "ok", "schema_version": "1", "model_version": "1.0.0",
                    "policy_version": "1.0.0", "plaid_enabled": False}


def test_demo_profiles_are_the_three_fixtures():
    body = make_client().get("/v1/demo-profiles").json()
    assert [p["id"] for p in body["profiles"]] == ["jordan", "morgan", "casey"]
    morgan = body["profiles"][1]
    assert morgan["annual_gross_salary_cents"] == 8400000
    assert morgan["debts"][0]["apr"] == 0.25


def test_evaluate_returns_full_contract(morgan):
    res = make_client(FakeModel()).post("/v1/evaluate", json={"profile": morgan, "scenario": None})
    assert res.status_code == 200
    ev = Evaluation.model_validate(res.json())
    assert ev.profile_id == "morgan"
    assert ev.decision_summary.source == "ai"
    assert ev.explanation.source == "ai"


def test_invalid_debt_minimum_uses_error_envelope(morgan):
    morgan["debts"][0]["minimum_payment_cents"] = 0
    res = make_client().post("/v1/evaluate", json={"profile": morgan})
    assert res.status_code == 422
    err = res.json()["error"]
    assert err["code"] == "INVALID_PROFILE"
    assert err["message"] == "Confirm the minimum payment for this debt."
    assert err["field_paths"] == ["debts.0.minimum_payment_cents"]
    assert err["retryable"] is False


def test_unknown_field_is_rejected(morgan):
    morgan["surprise"] = 1
    res = make_client().post("/v1/evaluate", json={"profile": morgan})
    assert res.status_code == 422
    assert res.json()["error"]["field_paths"] == ["surprise"]


def test_profile_retirement_age_must_follow_age(morgan):
    morgan["retirement_age"] = 35
    res = make_client().post("/v1/evaluate", json={"profile": morgan})
    assert res.status_code == 422
    assert res.json()["error"]["field_paths"] == ["retirement_age"]


def test_retirement_age_must_follow_age(morgan):
    res = make_client().post("/v1/evaluate", json={"profile": morgan, "scenario": {"retirement_age": 30}})
    assert res.status_code == 422
    err = res.json()["error"]
    assert err["code"] == "INVALID_REQUEST"
    assert err["field_paths"] == ["scenario.retirement_age"]


def test_election_above_contribution_cap_rejected(morgan):
    morgan["annual_gross_salary_cents"] = 40000000  # 8% of $400k = $32k, above the $24.5k cap
    res = make_client().post("/v1/evaluate", json={"profile": morgan})
    assert res.status_code == 422
    assert res.json()["error"]["field_paths"] == ["employee_contribution_rate"]


def test_all_fixtures_are_accepted(profiles):
    client = make_client()
    for p in profiles.values():
        assert client.post("/v1/evaluate", json={"profile": p}).status_code == 200


def test_money_ceiling_prevents_int64_overflow(morgan):
    morgan["emergency_cash_cents"] = 10**19
    res = make_client().post("/v1/evaluate", json={"profile": morgan})
    assert res.status_code == 422
    assert res.json()["error"]["field_paths"] == ["emergency_cash_cents"]


def test_malformed_json_has_no_offset_path():
    res = make_client().post("/v1/evaluate", content=b'{"profile": ', headers={"content-type": "application/json"})
    assert res.status_code == 422
    err = res.json()["error"]
    assert err["code"] == "INVALID_REQUEST" and err["field_paths"] == []


def test_undecodable_body_stays_in_contract():
    res = make_client().post("/v1/evaluate", content=b"\xff\xfe", headers={"content-type": "application/json"})
    assert res.status_code == 422
    assert res.json()["error"]["code"] == "INVALID_REQUEST"


def test_unexpected_error_is_sanitized(morgan, caplog):
    client = make_client()

    def boom(_):
        raise RuntimeError("secret balance 1800000")

    client.app.state.pipeline.run = boom
    res = client.post("/v1/evaluate", json={"profile": morgan})
    assert res.status_code == 500
    err = res.json()["error"]
    assert err["code"] == "INTERNAL_ERROR" and err["retryable"] is True
    assert "1800000" not in res.text
    assert "1800000" not in caplog.text
    assert "POST /v1/evaluate 500" in caplog.text


def test_non_contiguous_match_tiers_rejected(morgan):
    morgan["employer_match"]["tiers"].append(
        {"employee_rate_from": 0.06, "employee_rate_to": 0.08, "match_per_employee_dollar": 0.5})
    res = make_client().post("/v1/evaluate", json={"profile": morgan})
    assert res.status_code == 422


def test_body_over_128_kib_rejected():
    res = make_client().post("/v1/evaluate", content=b"x" * (128 * 1024 + 1),
                             headers={"content-type": "application/json"})
    assert res.status_code == 413
    assert res.json()["error"]["code"] == "PAYLOAD_TOO_LARGE"


def test_rate_limit_returns_429(morgan):
    client = make_client(evaluations_per_minute=2)
    codes = [client.post("/v1/evaluate", json={"profile": morgan}).status_code for _ in range(3)]
    assert codes == [200, 200, 429]


def test_plaid_routes_are_disabled():
    res = make_client().post("/v1/plaid/link-token", json={})
    assert res.status_code == 503
    assert res.json()["error"]["code"] == "PLAID_DISABLED"


def test_unknown_route_uses_envelope():
    res = make_client().get("/v1/nope")
    assert res.status_code == 404
    assert res.json()["error"]["code"] == "NOT_FOUND"
