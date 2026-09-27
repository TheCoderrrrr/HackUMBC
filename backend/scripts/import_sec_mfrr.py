"""Stage a local SEC MFRR quarterly ZIP into an atomically replaced SQLite DB.

Usage: python scripts/import_sec_mfrr.py --zip PATH --db PATH
Only local files are read. SUB, NUM, and TXT values remain raw strings exactly
as filed; this does not publish a fund catalog or interpret any financial tags.
"""

from __future__ import annotations

import argparse
from contextlib import closing, contextmanager
import csv
import io
import os
import re
import sqlite3
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path


MAX_ARCHIVE_MEMBERS = 100
MAX_MEMBER_BYTES = 1_000_000_000
MAX_TOTAL_BYTES = 2_000_000_000
MAX_COMPRESSION_RATIO = 200
MAX_CELL_CHARS = 1_000_000
BATCH_SIZE = 1_000
SAFE_MEMBER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
SAFE_COLUMN = re.compile(r"^[a-z][a-z0-9_]*$")
ADSH = re.compile(r"^\d{10}-\d{2}-\d{6}$")
REQUIRED_COLUMNS = {
    "sub": {"adsh", "cik", "name", "form", "filed", "accepted", "instance"},
    "num": {"adsh", "tag", "version", "ddate", "uom", "series", "class",
            "measure", "document", "otherdims", "iprx", "value"},
    "txt": {"adsh", "tag", "version", "ddate", "lang", "series", "class",
            "measure", "document", "otherdims", "iprx", "value"},
}
FACT_KEYS = {
    "num": ("adsh", "tag", "version", "ddate", "uom", "series", "class",
            "measure", "document", "otherdims", "iprx"),
    "txt": ("adsh", "tag", "version", "ddate", "lang", "series", "class", "measure",
            "document", "otherdims", "iprx"),
}


class ImportFailure(ValueError):
    """Invalid or unsafe archive; the previously published DB remains intact."""


def _quote(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def inspect_archive(archive: zipfile.ZipFile) -> dict[str, zipfile.ZipInfo]:
    """Select the three required root TSV members and reject unsafe ZIP metadata."""
    infos = archive.infolist()
    if not infos or len(infos) > MAX_ARCHIVE_MEMBERS:
        raise ImportFailure("Archive has an invalid number of members")
    selected: dict[str, zipfile.ZipInfo] = {}
    seen_names: set[str] = set()
    total = 0
    for info in infos:
        name = info.filename
        if (info.is_dir() or not SAFE_MEMBER.fullmatch(name) or ".." in name
                or name.lower() in seen_names or info.flag_bits & 0x1):
            raise ImportFailure("Archive contains an unsafe or duplicate member name")
        seen_names.add(name.lower())
        if info.file_size > MAX_MEMBER_BYTES:
            raise ImportFailure("Archive member exceeds size limit")
        total += info.file_size
        if total > MAX_TOTAL_BYTES:
            raise ImportFailure("Archive uncompressed size exceeds limit")
        if info.file_size and (info.compress_size == 0 or
                               info.file_size / info.compress_size > MAX_COMPRESSION_RATIO):
            raise ImportFailure("Archive member compression ratio exceeds limit")
        stem, dot, extension = name.lower().rpartition(".")
        if dot and extension in {"tsv", "txt"} and stem in REQUIRED_COLUMNS:
            if stem in selected:
                raise ImportFailure(f"Archive has duplicate {stem.upper()} members")
            selected[stem] = info
    missing = REQUIRED_COLUMNS.keys() - selected.keys()
    if missing:
        raise ImportFailure("Archive is missing required members: " + ", ".join(sorted(missing)))
    return selected


def _read_header(reader: csv.reader, kind: str) -> list[str]:
    try:
        header = next(reader)
    except StopIteration:
        raise ImportFailure(f"{kind.upper()} member is empty") from None
    if (not header or any(not SAFE_COLUMN.fullmatch(column) for column in header)
            or len(header) != len(set(header))):
        raise ImportFailure(f"{kind.upper()} header has unsafe or duplicate columns")
    missing = REQUIRED_COLUMNS[kind] - set(header)
    if missing:
        raise ImportFailure(f"{kind.upper()} header lacks required columns: {', '.join(sorted(missing))}")
    return header


def _validate_row(kind: str, row: list[str], header: list[str], line: int) -> None:
    if len(row) != len(header) or any(len(value) > MAX_CELL_CHARS for value in row):
        raise ImportFailure(f"{kind.upper()} row {line} has invalid width or oversized cell")
    fields = dict(zip(header, row))
    if not ADSH.fullmatch(fields["adsh"]):
        raise ImportFailure(f"{kind.upper()} row {line} has invalid adsh")
    if kind != "sub":
        if not all(fields[key] for key in ("tag", "version", "ddate", "iprx")):
            raise ImportFailure(f"{kind.upper()} row {line} has a missing fact key")
        if not re.fullmatch(r"\d{8}", fields["ddate"]):
            raise ImportFailure(f"{kind.upper()} row {line} has invalid ddate")
        if not re.fullmatch(r"[0-9]+", fields["iprx"]):
            raise ImportFailure(f"{kind.upper()} row {line} has invalid iprx")
    elif not fields["cik"].isdigit() or not fields["filed"].isdigit():
        raise ImportFailure(f"SUB row {line} has invalid cik or filed date")


def _create_table(conn: sqlite3.Connection, kind: str, header: list[str]) -> None:
    table = f"sec_{kind}"
    columns = ", ".join(f"{_quote(column)} TEXT NOT NULL" for column in header)
    conn.execute(
        f"CREATE TABLE {_quote(table)} ({columns}, "
        "_archive_name TEXT NOT NULL, _imported_at TEXT NOT NULL, "
        "_source_member TEXT NOT NULL, _row_number INTEGER NOT NULL)"
    )
    for ordinal, column in enumerate(header):
        conn.execute("INSERT INTO source_schema VALUES (?, ?, ?)", (kind, column, ordinal))
    if kind == "sub":
        conn.execute("CREATE UNIQUE INDEX idx_sub_unique ON sec_sub (adsh)")
    else:
        # The SEC archive can repeat a documented fact key, sometimes with a
        # different value. Source row number is the staging identity instead.
        conn.execute(
            f"CREATE UNIQUE INDEX {_quote(f'idx_{kind}_row_number')} "
            f"ON {_quote(table)} (_row_number)"
        )
        conn.execute(
            f"CREATE INDEX {_quote(f'idx_{kind}_fact_lookup')} ON {_quote(table)} "
            f"({', '.join(_quote(column) for column in FACT_KEYS[kind])})"
        )
        conn.execute(f"CREATE INDEX {_quote(f'idx_{kind}_adsh')} ON {_quote(table)} (adsh)")
        conn.execute(f"CREATE INDEX {_quote(f'idx_{kind}_series_class')} "
                     f"ON {_quote(table)} (series, {_quote('class')})")


@contextmanager
def _bounded_csv_fields():
    previous_limit = csv.field_size_limit(MAX_CELL_CHARS)
    try:
        yield
    finally:
        csv.field_size_limit(previous_limit)


def _stage_member(
    conn: sqlite3.Connection, archive: zipfile.ZipFile, info: zipfile.ZipInfo,
    kind: str, archive_name: str, imported_at: str,
) -> int:
    with _bounded_csv_fields(), archive.open(info) as raw, io.TextIOWrapper(
        raw, encoding="utf-8-sig", newline=""
    ) as text:
        reader = csv.reader(text, delimiter="\t", quoting=csv.QUOTE_NONE, strict=True)
        header = _read_header(reader, kind)
        _create_table(conn, kind, header)
        table = f"sec_{kind}"
        placeholders = ", ".join("?" for _ in range(len(header) + 4))
        insert = f"INSERT INTO {_quote(table)} VALUES ({placeholders})"
        batch: list[tuple[object, ...]] = []
        count = 0
        for line, row in enumerate(reader, start=2):
            _validate_row(kind, row, header, line)
            batch.append((*row, archive_name, imported_at, info.filename, line))
            if len(batch) >= BATCH_SIZE:
                conn.executemany(insert, batch)
                count += len(batch)
                batch.clear()
        if batch:
            conn.executemany(insert, batch)
            count += len(batch)
        return count


def import_archive(zip_path: Path | str, db_path: Path | str) -> dict[str, object]:
    """Stage one local archive, validate joins, then replace the destination DB."""
    source = Path(zip_path)
    destination = Path(db_path)
    if not source.is_file() or not zipfile.is_zipfile(source):
        raise ImportFailure("Input is not a readable ZIP file")
    if source.resolve() == destination.resolve():
        raise ImportFailure("ZIP input and SQLite destination must differ")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    imported_at = datetime.now(timezone.utc).isoformat()
    try:
        with tempfile.NamedTemporaryFile(
            prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent,
            delete=False,
        ) as handle:
            temporary = Path(handle.name)
        with zipfile.ZipFile(source) as archive:
            members = inspect_archive(archive)
            with closing(sqlite3.connect(temporary)) as conn, conn:
                conn.execute("PRAGMA foreign_keys = ON")
                conn.execute("CREATE TABLE source_schema (table_name TEXT NOT NULL, "
                             "column_name TEXT NOT NULL, ordinal INTEGER NOT NULL, "
                             "PRIMARY KEY (table_name, column_name))")
                conn.execute("CREATE TABLE import_meta (archive_name TEXT NOT NULL, "
                             "imported_at TEXT NOT NULL, sub_rows INTEGER NOT NULL, "
                             "num_rows INTEGER NOT NULL, txt_rows INTEGER NOT NULL)")
                counts = {}
                for kind in ("sub", "num", "txt"):
                    counts[kind] = _stage_member(
                        conn, archive, members[kind], kind, source.name, imported_at,
                    )
                for kind in ("num", "txt"):
                    missing = conn.execute(
                        f"SELECT COUNT(*) FROM sec_{kind} AS facts LEFT JOIN sec_sub AS sub "
                        "ON facts.adsh = sub.adsh WHERE sub.adsh IS NULL"
                    ).fetchone()[0]
                    if missing:
                        raise ImportFailure(f"{kind.upper()} contains {missing} unknown submission IDs")
                conn.execute("INSERT INTO import_meta VALUES (?, ?, ?, ?, ?)",
                             (source.name, imported_at, counts["sub"], counts["num"], counts["txt"]))
        os.replace(temporary, destination)
        temporary = None
        return {"archive_name": source.name, "imported_at": imported_at,
                "row_counts": counts, "database": str(destination)}
    except (sqlite3.Error, csv.Error, UnicodeError, zipfile.BadZipFile, OSError) as exc:
        raise ImportFailure(f"Archive import failed: {type(exc).__name__}") from exc
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", required=True, type=Path, help="Existing local SEC quarterly ZIP")
    parser.add_argument("--db", required=True, type=Path, help="SQLite staging output path")
    args = parser.parse_args(argv)
    try:
        result = import_archive(args.zip, args.db)
    except ImportFailure as exc:
        parser.exit(1, f"Import failed: {exc}\n")
    print(f"Staged {result['archive_name']}: "
          f"SUB={result['row_counts']['sub']} NUM={result['row_counts']['num']} "
          f"TXT={result['row_counts']['txt']} -> {result['database']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
