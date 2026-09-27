"""Synthetic SEC MFRR ZIP staging tests; no network or real filings."""

from __future__ import annotations

import csv
import sqlite3
import zipfile
from pathlib import Path

import pytest

from scripts import import_sec_mfrr as importer


ADSH = "0001234567-26-000001"
SUB_HEADER = "adsh\tcik\tname\tform\tfiled\taccepted\tinstance\tpdate"
SUB_ROW = (f"{ADSH}\t0001234567\tExample Funds Trust\t497\t20260630\t"
           "2026-06-30 12:00:00\texample.xml\t20260629")
NUM_HEADER = ("adsh\ttag\tversion\tddate\tuom\tseries\tclass\tmeasure\t"
              "document\totherdims\tiprx\tvalue\tfootnote\tdcml")
NUM_ROW = (f"{ADSH}\tExpenses\tinvest/2026\t20260630\tUSD\tS000000001\t"
           "C000000001\t\tprospectus\t\t1\t0.1500\t\t4")
TXT_HEADER = ("adsh\ttag\tversion\tddate\tlang\tseries\tclass\tmeasure\t"
              "document\totherdims\tiprx\tvalue\tcontext")
TXT_ROW = (f"{ADSH}\tRiskText\tinvest/2026\t20260630\ten-US\tS000000001\t"
           "C000000001\t\tprospectus\t\t1\tReturns can vary.\tctx_1")


def make_zip(path: Path, *, sub: str | None = None, num: str | None = None,
             txt: str | None = None, extra: dict[str, str] | None = None) -> Path:
    members = {
        "sub.tsv": sub if sub is not None else SUB_HEADER + "\n" + SUB_ROW + "\n",
        "num.tsv": num if num is not None else NUM_HEADER + "\n" + NUM_ROW + "\n",
        "txt.tsv": txt if txt is not None else TXT_HEADER + "\n" + TXT_ROW + "\n",
        "tag.tsv": "tag\tversion\nExpenses\tinvest/2026\n",
    }
    members.update(extra or {})
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, body in members.items():
            archive.writestr(name, body)
    return path


def test_import_preserves_raw_fields_provenance_joins_and_indexes(tmp_path):
    archive = make_zip(tmp_path / "2026q2_mfrr.zip")
    database = tmp_path / "staging.sqlite"
    result = importer.import_archive(archive, database)
    assert result["row_counts"] == {"sub": 1, "num": 1, "txt": 1}
    assert result["archive_name"] == archive.name
    with sqlite3.connect(database) as conn:
        joined = conn.execute(
            "SELECT sub.name, num.value, num.series, num.\"class\", txt.value, "
            "num._archive_name, num._source_member, num._row_number "
            "FROM sec_sub sub JOIN sec_num num USING (adsh) JOIN sec_txt txt USING (adsh)"
        ).fetchone()
        assert joined == (
            "Example Funds Trust", "0.1500", "S000000001", "C000000001",
            "Returns can vary.", archive.name, "num.tsv", 2,
        )
        assert conn.execute("SELECT pdate FROM sec_sub").fetchone()[0] == "20260629"
        assert conn.execute("SELECT dcml FROM sec_num").fetchone()[0] == "4"
        assert conn.execute("SELECT context FROM sec_txt").fetchone()[0] == "ctx_1"
        assert conn.execute("SELECT archive_name, sub_rows, num_rows, txt_rows FROM import_meta").fetchone() == (
            archive.name, 1, 1, 1,
        )
        assert conn.execute("SELECT imported_at FROM import_meta").fetchone()[0]
        assert {row[1] for row in conn.execute("PRAGMA index_list(sec_num)")} >= {
            "idx_num_row_number", "idx_num_fact_lookup", "idx_num_adsh", "idx_num_series_class",
        }
        assert {row[1] for row in conn.execute("PRAGMA index_list(sec_txt)")} >= {
            "idx_txt_row_number", "idx_txt_fact_lookup", "idx_txt_adsh", "idx_txt_series_class",
        }
        assert {row[0] for row in conn.execute("SELECT column_name FROM source_schema WHERE table_name='num'")} >= {
            "tag", "version", "ddate", "uom", "series", "class", "measure", "document", "otherdims", "iprx", "value",
        }


def test_failed_replace_leaves_prior_database_untouched(tmp_path):
    database = tmp_path / "staging.sqlite"
    importer.import_archive(make_zip(tmp_path / "good.zip"), database)
    before = database.read_bytes()
    malformed = NUM_HEADER + "\n" + NUM_ROW.rsplit("\t", 1)[0] + "\n"
    bad = make_zip(tmp_path / "malformed.zip", num=malformed)
    with pytest.raises(importer.ImportFailure, match="invalid width"):
        importer.import_archive(bad, database)
    assert database.read_bytes() == before
    assert sorted(tmp_path.glob(".staging.sqlite.*.tmp")) == []


@pytest.mark.parametrize("name", ["../num.tsv", "/num.tsv", "folder/num.tsv", "folder\\num.tsv"])
def test_unsafe_archive_member_name_rejected(tmp_path, name):
    archive = make_zip(tmp_path / "unsafe.zip", extra={name: "unsafe"})
    with pytest.raises(importer.ImportFailure, match="unsafe"):
        importer.import_archive(archive, tmp_path / "out.sqlite")
    assert not (tmp_path / "out.sqlite").exists()


def test_missing_member_or_required_column_rejected(tmp_path):
    missing_member = tmp_path / "missing.zip"
    with zipfile.ZipFile(missing_member, "w") as archive:
        archive.writestr("sub.tsv", SUB_HEADER + "\n" + SUB_ROW + "\n")
        archive.writestr("num.tsv", NUM_HEADER + "\n" + NUM_ROW + "\n")
    with pytest.raises(importer.ImportFailure, match="missing required members"):
        importer.import_archive(missing_member, tmp_path / "out.sqlite")
    bad_header = make_zip(tmp_path / "bad-header.zip", txt="adsh\ttag\tvalue\n")
    with pytest.raises(importer.ImportFailure, match="lacks required columns"):
        importer.import_archive(bad_header, tmp_path / "out.sqlite")
    missing_instance = make_zip(
        tmp_path / "no-instance.zip",
        sub=SUB_HEADER.replace("\tinstance", "") + "\n"
            + SUB_ROW.replace("\texample.xml", "") + "\n",
    )
    with pytest.raises(importer.ImportFailure, match="instance"):
        importer.import_archive(missing_instance, tmp_path / "out.sqlite")
    missing_lang = make_zip(
        tmp_path / "no-lang.zip",
        txt=TXT_HEADER.replace("\tlang", "") + "\n"
            + TXT_ROW.replace("\ten-US", "") + "\n",
    )
    with pytest.raises(importer.ImportFailure, match="lang"):
        importer.import_archive(missing_lang, tmp_path / "out.sqlite")


def test_malformed_row_or_orphan_adsh_rejected(tmp_path):
    truncated = make_zip(tmp_path / "truncated.zip", num=NUM_HEADER + "\n" + NUM_ROW.rsplit("\t", 1)[0] + "\n")
    with pytest.raises(importer.ImportFailure, match="invalid width"):
        importer.import_archive(truncated, tmp_path / "out.sqlite")
    orphan = make_zip(tmp_path / "orphan.zip", txt=TXT_HEADER + "\n" + TXT_ROW.replace(ADSH, "0001234567-26-000002") + "\n")
    with pytest.raises(importer.ImportFailure, match="unknown submission IDs"):
        importer.import_archive(orphan, tmp_path / "out.sqlite")


def test_declared_oversized_member_and_high_ratio_rejected(tmp_path, monkeypatch):
    archive = make_zip(tmp_path / "large.zip")
    monkeypatch.setattr(importer, "MAX_MEMBER_BYTES", 10)
    with pytest.raises(importer.ImportFailure, match="size limit"):
        importer.import_archive(archive, tmp_path / "out.sqlite")
    monkeypatch.setattr(importer, "MAX_MEMBER_BYTES", 1_000_000)
    monkeypatch.setattr(importer, "MAX_COMPRESSION_RATIO", 1)
    with pytest.raises(importer.ImportFailure, match="compression ratio"):
        importer.import_archive(archive, tmp_path / "out.sqlite")


def test_duplicate_fact_keys_preserve_distinct_and_identical_raw_rows(tmp_path):
    changed_value = NUM_ROW.replace("\t0.1500\t", "\t0.2500\t")
    archive = make_zip(
        tmp_path / "dup-fact.zip",
        num=NUM_HEADER + "\n" + NUM_ROW + "\n" + changed_value + "\n" + NUM_ROW + "\n",
    )
    database = tmp_path / "out.sqlite"
    assert importer.import_archive(archive, database)["row_counts"]["num"] == 3
    with sqlite3.connect(database) as conn:
        assert conn.execute(
            "SELECT _row_number, value FROM sec_num ORDER BY _row_number"
        ).fetchall() == [(2, "0.1500"), (3, "0.2500"), (4, "0.1500")]


def test_duplicate_member_rejected(tmp_path):
    duplicate_member = tmp_path / "duplicate-member.zip"
    with zipfile.ZipFile(duplicate_member, "w") as archive_zip:
        archive_zip.writestr("sub.tsv", SUB_HEADER + "\n" + SUB_ROW)
        archive_zip.writestr("num.tsv", NUM_HEADER + "\n" + NUM_ROW)
        archive_zip.writestr("txt.tsv", TXT_HEADER + "\n" + TXT_ROW)
        archive_zip.writestr("NUM.TSV", NUM_HEADER + "\n" + NUM_ROW)
    with pytest.raises(importer.ImportFailure, match="duplicate member"):
        importer.import_archive(duplicate_member, tmp_path / "out.sqlite")


def test_utf8_and_raw_empty_values_survive(tmp_path):
    unicode_sub = SUB_ROW.replace("Example Funds Trust", "Café Funds Trust")
    archive = make_zip(tmp_path / "utf8.zip", sub=SUB_HEADER + "\n" + unicode_sub + "\n")
    database = tmp_path / "out.sqlite"
    importer.import_archive(archive, database)
    with sqlite3.connect(database) as conn:
        assert conn.execute("SELECT name FROM sec_sub").fetchone()[0] == "Café Funds Trust"
        assert conn.execute("SELECT measure, otherdims, footnote FROM sec_num").fetchone() == ("", "", "")


def test_txt_language_is_part_of_key_and_literal_quotes_survive(tmp_path):
    quoted = TXT_ROW.replace("Returns can vary.", '"Returns can vary."')
    french = quoted.replace("\ten-US\t", "\tfr-FR\t")
    archive = make_zip(
        tmp_path / "multilingual.zip",
        txt=TXT_HEADER + "\n" + quoted + "\n" + french + "\n",
    )
    database = tmp_path / "out.sqlite"
    assert importer.import_archive(archive, database)["row_counts"]["txt"] == 2
    with sqlite3.connect(database) as conn:
        assert conn.execute(
            "SELECT lang, value FROM sec_txt ORDER BY lang"
        ).fetchall() == [
            ("en-US", '"Returns can vary."'),
            ("fr-FR", '"Returns can vary."'),
        ]


def test_zero_iprx_is_valid_in_num_and_txt(tmp_path):
    archive = make_zip(
        tmp_path / "zero-iprx.zip",
        num=NUM_HEADER + "\n" + NUM_ROW.replace("\t1\t0.1500", "\t0\t0.1500") + "\n",
        txt=TXT_HEADER + "\n" + TXT_ROW.replace("\t1\tReturns", "\t0\tReturns") + "\n",
    )
    database = tmp_path / "out.sqlite"
    importer.import_archive(archive, database)
    with sqlite3.connect(database) as conn:
        assert conn.execute("SELECT iprx FROM sec_num").fetchone()[0] == "0"
        assert conn.execute("SELECT iprx FROM sec_txt").fetchone()[0] == "0"


def test_large_txt_field_within_limit_imports_and_parser_limit_is_restored(tmp_path):
    large_value = "".join(f"{number:08x}" for number in range(20_000))
    assert 131_072 < len(large_value) < importer.MAX_CELL_CHARS
    archive = make_zip(
        tmp_path / "large-text.zip",
        txt=TXT_HEADER + "\n" + TXT_ROW.replace("Returns can vary.", large_value) + "\n",
    )
    previous_limit = csv.field_size_limit()
    database = tmp_path / "out.sqlite"
    importer.import_archive(archive, database)
    assert csv.field_size_limit() == previous_limit
    with sqlite3.connect(database) as conn:
        assert conn.execute("SELECT value FROM sec_txt").fetchone()[0] == large_value


def test_txt_field_over_limit_rejected_without_replacing_database(tmp_path):
    database = tmp_path / "out.sqlite"
    importer.import_archive(make_zip(tmp_path / "good.zip"), database)
    before = database.read_bytes()
    oversized_value = "".join(f"{number:08x}" for number in range(125_001))
    assert len(oversized_value) > importer.MAX_CELL_CHARS
    archive = make_zip(
        tmp_path / "oversized-text.zip",
        txt=TXT_HEADER + "\n" + TXT_ROW.replace("Returns can vary.", oversized_value) + "\n",
    )
    previous_limit = csv.field_size_limit()
    with pytest.raises(importer.ImportFailure):
        importer.import_archive(archive, database)
    assert csv.field_size_limit() == previous_limit
    assert database.read_bytes() == before


@pytest.mark.parametrize("invalid", ["-1", "1.5", "one"])
def test_invalid_iprx_is_rejected(tmp_path, invalid):
    archive = make_zip(
        tmp_path / f"invalid-{invalid}.zip",
        num=NUM_HEADER + "\n" + NUM_ROW.replace("\t1\t0.1500", f"\t{invalid}\t0.1500") + "\n",
    )
    with pytest.raises(importer.ImportFailure, match="invalid iprx"):
        importer.import_archive(archive, tmp_path / "out.sqlite")


def test_cli_help(capsys):
    with pytest.raises(SystemExit) as result:
        importer.main(["--help"])
    assert result.value.code == 0
    assert "--zip" in capsys.readouterr().out
