"""Offline candidate-audit tests using a tiny synthetic staging database."""

from __future__ import annotations

import json
import os
import sqlite3
from contextlib import closing

import pytest

from scripts import audit_sec_candidates as audit


ACCESSION_A = "0000000001-26-000001"
ACCESSION_B = "0000000002-26-000001"
ACCESSION_C = "0000000003-26-000001"


def make_database(path):
    with closing(sqlite3.connect(path)) as conn, conn:
        conn.execute("CREATE TABLE sec_sub (adsh TEXT, cik TEXT, name TEXT, form TEXT, filed TEXT)")
        conn.execute(
            "CREATE TABLE sec_txt (adsh TEXT, series TEXT, document TEXT, ddate TEXT, "
            "tag TEXT, value TEXT, _archive_name TEXT, _source_member TEXT, _row_number INTEGER)"
        )
        conn.execute(
            "CREATE TABLE sec_num (adsh TEXT, series TEXT, document TEXT, ddate TEXT, "
            "tag TEXT, version TEXT, uom TEXT, otherdims TEXT, iprx TEXT, value TEXT, "
            "_archive_name TEXT, _source_member TEXT, _row_number INTEGER)"
        )
        conn.executemany("INSERT INTO sec_sub VALUES (?,?,?,?,?)", [
            (ACCESSION_A, "111", "Fidelity Trust", "485BPOS", "20260401"),
            (ACCESSION_B, "222", "Annuity Account", "485APOS", "20260402"),
            (ACCESSION_C, "333", "Another Trust", "485BPOS", "20260403"),
        ])
        conn.executemany("INSERT INTO sec_txt VALUES (?,?,?,?,?,?,?,?,?)", [
            (ACCESSION_A, "S000000001", "doc-a", "20260430", "RiskReturnHeading",
             "Fidelity Sustainable Target Date 2030 Fund", "quarter.zip", "txt.tsv", 10),
            (ACCESSION_B, "", "annuity", "20260430", "PortfolioCompanyNameTextBlock",
             "Vanguard Target Retirement 2050 Fund", "quarter.zip", "txt.tsv", 11),
            (ACCESSION_C, "S000000003", "doc-c", "20260430", "RiskReturnHeading",
             "Another Target Retirement 2040 Fund", "quarter.zip", "txt.tsv", 12),
        ])
        conn.executemany("INSERT INTO sec_num VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", [
            (ACCESSION_A, "S000000001", "doc-a", "20260430", "ExpensesOverAssets",
             "oef/2026", "pure", "Class=C000000001;", "0", "0.0045", "quarter.zip", "num.tsv", 20),
            (ACCESSION_A, "S000000001", "doc-a", "20260430", "ExpensesOverAssets",
             "oef/2026", "pure", "Class=C000000002;", "0", "0.0070", "quarter.zip", "num.tsv", 21),
        ])
    return path


def test_audit_preserves_raw_class_facts_and_excludes_annuity_option_name(tmp_path):
    db = make_database(tmp_path / "stage.sqlite")
    before = db.read_bytes()
    result = audit.audit_database(db)
    assert db.read_bytes() == before
    assert result["status"] == "unverified_candidate_audit"
    assert result["candidate_series_total"] == 2
    first = result["candidates"][0]
    assert first["accession"] == ACCESSION_A
    assert first["headings"][0]["target_year_in_text"] == 2030
    assert first["headings"][0]["provenance"] == {
        "archive": "quarter.zip", "member": "txt.tsv", "row_number": 10,
    }
    assert [(fact["class_id_from_otherdims"], fact["raw_value"]) for fact in first["fee_facts"]] == [
        ("C000000001", "0.0045"), ("C000000002", "0.0070"),
    ]
    assert first["fee_facts"][0]["provenance"]["row_number"] == 20
    assert "CLASS_NAME_UNVERIFIED" in first["issues"]
    assert result["candidates"][1]["issues"] == ["NO_FEE_TAG_FACTS"]


def test_conflicts_bad_class_tokens_and_unmapped_documents_flagged(tmp_path):
    db = make_database(tmp_path / "stage.sqlite")
    with closing(sqlite3.connect(db)) as conn, conn:
        conn.executemany("INSERT INTO sec_num VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", [
            (ACCESSION_A, "S000000001", "doc-a", "20260430", "ExpensesOverAssets",
             "oef/2026", "pure", "Class=C000000001;", "0", "0.0099", "quarter.zip", "num.tsv", 22),
            (ACCESSION_A, "S000000001", "other-doc", "20260430", "NetExpensesOverAssets",
             "oef/2026", "pure", "Class=C00000000X;", "0", "0.0030", "quarter.zip", "num.tsv", 23),
        ])
    first = audit.audit_database(db)["candidates"][0]
    assert first["fee_fact_count"] == 4
    assert first["issues"] == [
        "CLASS_NAME_UNVERIFIED", "CLASS_TOKEN_MISSING_OR_AMBIGUOUS",
        "CONFLICTING_FEE_VALUES", "FEE_DOCUMENT_WITHOUT_HEADING",
    ]
    assert any(fact["class_id_from_otherdims"] is None for fact in first["fee_facts"])


def test_limits_are_deterministic_and_explicit(tmp_path):
    db = make_database(tmp_path / "stage.sqlite")
    first = audit.audit_database(db, limit=1, max_facts=1)
    second = audit.audit_database(db, limit=1, max_facts=1)
    assert first == second
    assert first["candidate_series_total"] == 2
    assert first["candidate_series_emitted"] == 1
    assert first["candidate_limit_applied"] is True
    assert first["candidates"][0]["fee_fact_count"] == 2
    assert len(first["candidates"][0]["fee_facts"]) == 1
    assert "FEE_FACTS_TRUNCATED" in first["candidates"][0]["issues"]
    with pytest.raises(audit.AuditFailure):
        audit.audit_database(db, limit=0)
    with pytest.raises(audit.AuditFailure):
        audit.audit_database(db, max_facts=201)


def test_cli_writes_json_and_help(tmp_path, capsys):
    db = make_database(tmp_path / "stage.sqlite")
    output = tmp_path / "audit.json"
    assert audit.main(["--db", str(db), "--output", str(output), "--limit", "1"]) == 0
    assert json.loads(output.read_text(encoding="utf-8"))["candidate_series_emitted"] == 1
    with pytest.raises(SystemExit) as result:
        audit.main(["--help"])
    assert result.value.code == 0
    assert "--max-facts" in capsys.readouterr().out


def test_cli_never_overwrites_staging_database(tmp_path):
    db = make_database(tmp_path / "stage.sqlite")
    before = db.read_bytes()
    with pytest.raises(SystemExit) as result:
        audit.main(["--db", str(db), "--output", str(db)])
    assert result.value.code == 1
    assert db.read_bytes() == before


def test_cli_rejects_hard_link_alias_of_staging_database(tmp_path):
    db = make_database(tmp_path / "stage.sqlite")
    alias = tmp_path / "audit.json"
    try:
        os.link(db, alias)
    except OSError as exc:
        pytest.skip(f"Hard links unavailable: {exc}")
    before = db.read_bytes()
    with pytest.raises(SystemExit) as result:
        audit.main(["--db", str(db), "--output", str(alias)])
    assert result.value.code == 1
    assert db.read_bytes() == before
    assert alias.read_bytes() == before


def test_failed_output_replace_keeps_old_file_and_cleans_temp(tmp_path, monkeypatch):
    db = make_database(tmp_path / "stage.sqlite")
    output = tmp_path / "audit.json"
    output.write_text("prior output\n", encoding="utf-8")
    before_db = db.read_bytes()

    def fail_replace(source, target):
        raise OSError("simulated replacement failure")

    monkeypatch.setattr(audit.os, "replace", fail_replace)
    with pytest.raises(SystemExit) as result:
        audit.main(["--db", str(db), "--output", str(output)])
    assert result.value.code == 1
    assert output.read_text(encoding="utf-8") == "prior output\n"
    assert db.read_bytes() == before_db
    assert list(tmp_path.glob(".audit.json.*.tmp")) == []


def test_year_before_target_phrase_is_discovered_without_portfolio_name_inference(tmp_path):
    db = make_database(tmp_path / "stage.sqlite")
    with closing(sqlite3.connect(db)) as conn, conn:
        conn.executemany("INSERT INTO sec_sub VALUES (?,?,?,?,?)", [
            ("0000000004-26-000001", "444", "American Funds", "485BPOS", "20260404"),
            ("0000000005-26-000001", "555", "Franklin Trust", "485BPOS", "20260405"),
        ])
        conn.executemany("INSERT INTO sec_txt VALUES (?,?,?,?,?,?,?,?,?)", [
            ("0000000004-26-000001", "S000000004", "doc-d", "20260430", "RiskReturnHeading",
             "American Funds IS 2065 Target Date Retirement Fund", "quarter.zip", "txt.tsv", 40),
            ("0000000005-26-000001", "S000000005", "doc-e", "20260430", "RiskReturnHeading",
             "Franklin LifeSmart 2040 Retirement Target Fund", "quarter.zip", "txt.tsv", 41),
        ])
    result = audit.audit_database(db)
    years = {candidate["series_id"]: candidate["headings"][0]["target_year_in_text"]
             for candidate in result["candidates"]}
    assert years["S000000004"] == 2065
    assert years["S000000005"] == 2040
    assert result["candidate_series_total"] == 4


def test_oversized_registrant_metadata_fails_closed(tmp_path):
    db = make_database(tmp_path / "stage.sqlite")
    with closing(sqlite3.connect(db)) as conn, conn:
        conn.execute("UPDATE sec_sub SET name=? WHERE adsh=?",
                     ("X" * (audit.MAX_FIELD_CHARS + 1), ACCESSION_A))
    output = tmp_path / "audit.json"
    output.write_text("prior output\n", encoding="utf-8")
    with pytest.raises(SystemExit) as result:
        audit.main(["--db", str(db), "--output", str(output)])
    assert result.value.code == 1
    assert output.read_text(encoding="utf-8") == "prior output\n"
