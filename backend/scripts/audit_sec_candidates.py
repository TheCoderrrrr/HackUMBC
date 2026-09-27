"""Export an unverified, read-only audit of target-year SEC MFRR candidates.

Example: python scripts/audit_sec_candidates.py --db .tools/sec/2026q2.sqlite
    --output .tools/sec/candidates.json --limit 20

This does not normalize fees, identify purchasable shares, or publish FundFacts.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import tempfile
from collections import defaultdict
from contextlib import closing
from pathlib import Path


TARGET_YEAR = re.compile(
    r"\b(?:target[\s-]*(?:date|retirement)|freedom|lifepath)"
    r"[^\n]{0,100}?\b(20[2-7]\d)\b"
    r"|\b(20[2-7]\d)\b[^\n]{0,60}?"
    r"\b(?:target(?:[\s-]+(?:date|retirement))?|retirement[\s-]+target)\b",
    re.IGNORECASE,
)
CLASS_TOKEN = re.compile(r"Class=(C[0-9]{9});")
FEE_TAGS = (
    "ExpensesOverAssets",
    "NetExpensesOverAssets",
    "CurrentExpensesPercent",
    "ManagementFeesOverAssets",
    "DistributionAndService12b1FeesOverAssets",
    "AcquiredFundFeesAndExpensesOverAssets",
    "FeeWaiverOrReimbursementOverAssets",
)
MAX_CANDIDATES = 200
MAX_FACTS = 200
MAX_HEADINGS = 50
MAX_FIELD_CHARS = 2_000


class AuditFailure(ValueError):
    """The audit cannot safely represent the requested staging rows."""


def _bounded(value: str, field: str) -> str:
    if len(value) > MAX_FIELD_CHARS:
        raise AuditFailure(f"{field} exceeds audit output field limit")
    return value


def _candidate_headings(conn: sqlite3.Connection) -> dict[tuple[str, str], dict]:
    candidates: dict[tuple[str, str], dict] = {}
    rows = conn.execute(
        "SELECT t.adsh, s.cik, s.name, s.form, s.filed, t.series, "
        "t.document, t.ddate, t.value, t._archive_name, t._source_member, "
        "t._row_number FROM sec_txt AS t JOIN sec_sub AS s ON s.adsh=t.adsh "
        "WHERE t.tag='RiskReturnHeading' AND t.series<>'' "
        "ORDER BY t.adsh, t.series, t.document, t._row_number"
    )
    for (adsh, cik, registrant, form, filed, series, document, ddate,
         value, archive, member, row_number) in rows:
        match = TARGET_YEAR.search(value)
        if not match:
            continue
        year = next(group for group in match.groups() if group is not None)
        adsh = _bounded(adsh, "Accession")
        series = _bounded(series, "Series")
        key = (adsh, series)
        candidate = candidates.setdefault(key, {
            "accession": adsh,
            "series_id": series,
            "registrant_cik": _bounded(cik, "Registrant CIK"),
            "registrant_name": _bounded(registrant, "Registrant name"),
            "form": _bounded(form, "Form"),
            "filed": _bounded(filed, "Filed date"),
            "headings": [],
        })
        if len(candidate["headings"]) >= MAX_HEADINGS:
            raise AuditFailure(f"Too many candidate headings for {adsh}/{series}")
        candidate["headings"].append({
            "raw_text": _bounded(value, "Heading"),
            "target_year_in_text": int(year),
            "document": _bounded(document, "Document"),
            "ddate": _bounded(ddate, "Heading date"),
            "provenance": {"archive": _bounded(archive, "Archive"),
                           "member": _bounded(member, "Member"), "row_number": row_number},
        })
    return candidates


def _fee_facts(conn: sqlite3.Connection, candidate: dict, max_facts: int) -> None:
    placeholders = ",".join("?" for _ in FEE_TAGS)
    rows = conn.execute(
        "SELECT tag, version, ddate, uom, document, otherdims, iprx, value, "
        "_archive_name, _source_member, _row_number FROM sec_num "
        "WHERE adsh=? AND series=? AND tag IN (" + placeholders + ") "
        "ORDER BY document, ddate, otherdims, tag, _row_number",
        (candidate["accession"], candidate["series_id"], *FEE_TAGS),
    )
    facts = []
    issue_codes: set[str] = set()
    values_by_key: dict[tuple[str | None, str, str, str], set[str]] = defaultdict(set)
    heading_documents = {heading["document"] for heading in candidate["headings"]}
    heading_years = {heading["target_year_in_text"] for heading in candidate["headings"]}
    if len(heading_years) > 1:
        issue_codes.add("TARGET_YEAR_CONFLICT")
    if len({heading["raw_text"] for heading in candidate["headings"]}) > 1:
        issue_codes.add("MULTIPLE_HEADING_TEXTS")
    total = 0
    has_class_id = False
    for (tag, version, ddate, uom, document, otherdims, iprx, value,
         archive, member, row_number) in rows:
        total += 1
        match = CLASS_TOKEN.fullmatch(otherdims)
        class_id = match.group(1) if match else None
        has_class_id |= class_id is not None
        if class_id is None:
            issue_codes.add("CLASS_TOKEN_MISSING_OR_AMBIGUOUS")
        if document not in heading_documents:
            issue_codes.add("FEE_DOCUMENT_WITHOUT_HEADING")
        values_by_key[(class_id, document, ddate, tag)].add(value)
        if total <= max_facts:
            facts.append({
                "class_id_from_otherdims": class_id,
                "raw_otherdims": _bounded(otherdims, "Other dimensions"),
                "document": _bounded(document, "Document"),
                "ddate": _bounded(ddate, "Fee date"),
                "tag": _bounded(tag, "Fee tag"),
                "version": _bounded(version, "Taxonomy version"),
                "uom": _bounded(uom, "Unit"),
                "iprx": _bounded(iprx, "Priority"),
                "raw_value": _bounded(value, "Fee value"),
                "provenance": {"archive": _bounded(archive, "Archive"),
                               "member": _bounded(member, "Member"), "row_number": row_number},
            })
    if total == 0:
        issue_codes.add("NO_FEE_TAG_FACTS")
    if total > max_facts:
        issue_codes.add("FEE_FACTS_TRUNCATED")
    if any(len(values) > 1 for values in values_by_key.values()):
        issue_codes.add("CONFLICTING_FEE_VALUES")
    if has_class_id:
        issue_codes.add("CLASS_NAME_UNVERIFIED")
    candidate["fee_fact_count"] = total
    candidate["fee_facts"] = facts
    candidate["issues"] = sorted(issue_codes)


def audit_database(db_path: Path | str, *, limit: int = 20, max_facts: int = 100) -> dict:
    """Read a staging DB without modifying it; return bounded raw evidence only."""
    if not 1 <= limit <= MAX_CANDIDATES or not 1 <= max_facts <= MAX_FACTS:
        raise AuditFailure("limit or max_facts is outside the supported range")
    source = Path(db_path)
    if not source.is_file():
        raise AuditFailure("Staging database does not exist")
    try:
        with closing(sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True)) as conn:
            candidates = _candidate_headings(conn)
            keys = sorted(candidates)
            selected = []
            for key in keys[:limit]:
                candidate = candidates[key]
                _fee_facts(conn, candidate, max_facts)
                selected.append(candidate)
    except sqlite3.Error as exc:
        raise AuditFailure(f"Could not read SEC staging schema: {type(exc).__name__}") from exc
    return {
        "status": "unverified_candidate_audit",
        "source_database": _bounded(str(source.resolve()), "Database path"),
        "candidate_series_total": len(keys),
        "candidate_series_emitted": len(selected),
        "candidate_limit_applied": len(keys) > limit,
        "max_fee_facts_per_candidate": max_facts,
        "candidates": selected,
    }


def _write_audit(output: Path, audit: dict) -> None:
    """Publish only a complete JSON file, retaining prior output on failure."""
    rendered = json.dumps(audit, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", prefix=f".{output.name}.",
            suffix=".tmp", dir=output.parent, delete=False,
        ) as handle:
            temporary = Path(handle.name)
            handle.write(rendered)
        os.replace(temporary, output)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, required=True, help="Existing SEC staging SQLite database")
    parser.add_argument("--output", type=Path, required=True, help="JSON audit output path")
    parser.add_argument("--limit", type=int, default=20, help="Candidate series to emit (1-200)")
    parser.add_argument("--max-facts", type=int, default=100,
                        help="Fee rows per candidate to emit (1-200)")
    args = parser.parse_args(argv)
    if (args.db.resolve() == args.output.resolve()
            or (args.db.exists() and args.output.exists()
                and args.db.samefile(args.output))):
        parser.exit(1, "Audit failed: output path must differ from staging database\n")
    try:
        audit = audit_database(args.db, limit=args.limit, max_facts=args.max_facts)
        _write_audit(args.output, audit)
    except (AuditFailure, OSError) as exc:
        parser.exit(1, f"Audit failed: {exc}\n")
    print(f"Wrote {audit['candidate_series_emitted']} of "
          f"{audit['candidate_series_total']} unverified candidate series to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
