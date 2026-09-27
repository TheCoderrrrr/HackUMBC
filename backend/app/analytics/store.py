"""Tiger Data (TimescaleDB) persistence for scenario history. All database SQL lives here.

Tables, in the schema from TIGER_SCHEMA (default "arm"):
- scenario_run: one row per saved run, with provenance. input_hash is unique, so saving
  the same result twice returns the first run.
- projection_point: every monthly point of every feasible strategy. A hypertable on the
  integer `month`, so projections of any length share one time dimension.
- projection_yearly: continuous aggregate, time_bucket(12, month) with first(value, month).
  It yields the points at months 0, 12, 24, ..., the samples the desktop chart draws.
  Real-time mode is on and each save refreshes its window, so new runs show up at once.
- Compression (columnstore): projection points never change after a save, so chunks are
  compressed, segmented by (run_id, strategy) and ordered by month, the shape every read uses.

Connections come from a small lazy pool (0-4, health-checked), so a request doesn't pay a new
TLS handshake to Tiger Cloud each time.
"""
from __future__ import annotations

import json
import logging
import os
import re
import threading
from typing import Protocol

from app.analytics.models import RunRecord, RunSummary, YearRow

log = logging.getLogger("adaptive_retirement")

_SCHEMA_NAME = re.compile(r"^[a-z_][a-z0-9_]{0,40}$")
_MONTH_NOW = 100_000  # integer "now" for the month dimension; beyond any projection
_CHUNK_MONTHS = 120


class HistoryUnavailable(Exception):
    """The database could not be reached or refused the operation."""


class HistoryStore(Protocol):
    def ping(self) -> bool: ...
    def save(self, record: RunRecord) -> tuple[RunSummary, bool]: ...
    def list_runs(self, profile_id: str, limit: int) -> list[RunSummary]: ...
    def get_runs(self, run_ids: list[str]) -> dict[str, RunSummary]: ...
    def yearly(self, pairs: list[tuple[str, str]]) -> dict[str, list[YearRow]]: ...
    def delete(self, run_id: str) -> bool: ...


def migrations(schema: str) -> list[str]:
    s = schema
    return [
        f"CREATE SCHEMA IF NOT EXISTS {s}",
        f"""CREATE TABLE IF NOT EXISTS {s}.scenario_run (
            run_id uuid PRIMARY KEY,
            input_hash text NOT NULL UNIQUE,
            profile_id text NOT NULL,
            label text NOT NULL,
            created_at timestamptz NOT NULL DEFAULT now(),
            as_of_date date NOT NULL,
            scenario jsonb,
            primary_strategy text NOT NULL CHECK (primary_strategy IN ('adaptive', 'custom')),
            retirement_age integer NOT NULL,
            final_retirement_balance_cents bigint,
            decision_source text NOT NULL CHECK (decision_source IN ('ai', 'rules_fallback')),
            model_id text,
            prompt_version text NOT NULL,
            ordered_priorities text[] NOT NULL,
            schema_version text NOT NULL,
            model_version text NOT NULL,
            policy_version text NOT NULL,
            assumptions jsonb NOT NULL
        )""",
        f"CREATE INDEX IF NOT EXISTS scenario_run_profile_idx ON {s}.scenario_run (profile_id, created_at DESC)",
        f"""CREATE TABLE IF NOT EXISTS {s}.projection_point (
            run_id uuid NOT NULL REFERENCES {s}.scenario_run (run_id) ON DELETE CASCADE,
            strategy text NOT NULL CHECK (strategy IN ('current', 'adaptive', 'custom')),
            month integer NOT NULL CHECK (month >= 0),
            projected_on date NOT NULL,
            retirement_balance_cents bigint NOT NULL,
            cash_cents bigint NOT NULL,
            debt_cents bigint NOT NULL,
            PRIMARY KEY (run_id, strategy, month)
        )""",
        f"SELECT create_hypertable('{s}.projection_point', 'month', "
        f"chunk_time_interval => {_CHUNK_MONTHS}, if_not_exists => TRUE)",
        f"CREATE OR REPLACE FUNCTION {s}.projection_month_now() RETURNS integer "
        f"LANGUAGE SQL STABLE AS $$ SELECT {_MONTH_NOW} $$",
        f"SELECT set_integer_now_func('{s}.projection_point', '{s}.projection_month_now', "
        f"replace_if_exists => TRUE)",
        f"""CREATE MATERIALIZED VIEW IF NOT EXISTS {s}.projection_yearly
            WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
            SELECT run_id, strategy, time_bucket(12, month) AS bucket,
                   first(month, month) AS month,
                   first(projected_on, month) AS projected_on,
                   first(retirement_balance_cents, month) AS retirement_balance_cents,
                   first(cash_cents, month) AS cash_cents,
                   first(debt_cents, month) AS debt_cents
            FROM {s}.projection_point
            GROUP BY run_id, strategy, bucket
            WITH NO DATA""",
        f"""DO $$ BEGIN
            IF NOT (SELECT compression_enabled FROM timescaledb_information.hypertables
                    WHERE hypertable_schema = '{s}' AND hypertable_name = 'projection_point') THEN
                ALTER TABLE {s}.projection_point SET (timescaledb.compress,
                    timescaledb.compress_segmentby = 'run_id, strategy', timescaledb.compress_orderby = 'month');
            END IF;
        END $$""",
        f"SELECT add_compression_policy('{s}.projection_point', compress_after => {_CHUNK_MONTHS}, if_not_exists => TRUE)",
    ]


_SUMMARY_COLUMNS = ("run_id::text, profile_id, label, created_at, as_of_date, scenario, primary_strategy, "
                    "retirement_age, final_retirement_balance_cents, decision_source, model_id, prompt_version, "
                    "model_version, policy_version, input_hash")


def _summary(row) -> RunSummary:
    keys = [c.strip().removesuffix("::text") for c in _SUMMARY_COLUMNS.split(",")]
    return RunSummary.model_validate(dict(zip(keys, row)))


class TigerHistoryStore:
    def __init__(self, url: str, schema: str = "arm", connect_timeout: int = 5):
        if not _SCHEMA_NAME.match(schema):
            raise ValueError("TIGER_SCHEMA must be a lower-case SQL identifier")
        self.url, self.schema, self.connect_timeout = url, schema, connect_timeout
        self._ready = False
        self._lock = threading.Lock()
        self._pool = None

    # --- connections ---------------------------------------------------------------

    def _get_pool(self):
        """Created on first use; opens no connection until one is needed."""
        if self._pool is None:
            with self._lock:
                if self._pool is None:
                    from psycopg_pool import ConnectionPool

                    self._pool = ConnectionPool(
                        self.url, min_size=0, max_size=4, max_idle=300, timeout=self.connect_timeout,
                        kwargs={"autocommit": True, "connect_timeout": self.connect_timeout},
                        configure=lambda conn: conn.execute("SET statement_timeout = '15s'"),
                        check=ConnectionPool.check_connection, name="arm-history", open=True,
                    )
        return self._pool

    def close(self) -> None:
        if self._pool is not None:
            self._pool.close()
            self._pool = None

    def _with_connection(self, fn):
        import psycopg
        from psycopg_pool import PoolTimeout

        try:
            with self._get_pool().connection() as conn:
                return fn(conn)
        except (psycopg.Error, PoolTimeout) as exc:  # never log the URL or server text: it may name the host or user
            log.warning("history database unavailable: %s", type(exc).__name__)
            raise HistoryUnavailable() from exc

    def _run(self, fn):
        self._ensure_schema()
        return self._with_connection(fn)

    def _ensure_schema(self) -> None:
        if self._ready:
            return
        pool = self._get_pool()  # outside the lock: _get_pool takes it too
        with self._lock:
            if self._ready:
                return

            def migrate(conn):
                for statement in migrations(self.schema):
                    conn.execute(statement)

            self._with_connection(migrate)
            self._ready = True

    # --- operations ------------------------------------------------------------------

    def ping(self) -> bool:
        try:
            self._run(lambda conn: conn.execute("SELECT 1").fetchone())
            return True
        except HistoryUnavailable:
            return False

    def save(self, record: RunRecord) -> tuple[RunSummary, bool]:
        s = self.schema

        def write(conn):
            with conn.transaction():
                inserted = conn.execute(
                    f"""INSERT INTO {s}.scenario_run (run_id, input_hash, profile_id, label, as_of_date, scenario,
                            primary_strategy, retirement_age, final_retirement_balance_cents, decision_source,
                            model_id, prompt_version, ordered_priorities, schema_version, model_version,
                            policy_version, assumptions)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                        ON CONFLICT (input_hash) DO NOTHING
                        RETURNING run_id""",
                    (record.run_id, record.input_hash, record.profile_id, record.label, record.as_of_date,
                     json.dumps(record.scenario.model_dump(mode="json")) if record.scenario else None,
                     record.primary_strategy, record.retirement_age, record.final_retirement_balance_cents,
                     record.decision_source, record.model_id, record.prompt_version, record.ordered_priorities,
                     record.schema_version, record.model_version, record.policy_version,
                     json.dumps(record.assumptions)),
                ).fetchone()
                created = inserted is not None
                if created:
                    with conn.cursor().copy(
                        f"COPY {s}.projection_point (run_id, strategy, month, projected_on, "
                        f"retirement_balance_cents, cash_cents, debt_cents) FROM STDIN"
                    ) as copy:
                        for p in record.points:
                            copy.write_row((record.run_id, p.strategy, p.month, p.projected_on,
                                            p.retirement_balance_cents, p.cash_cents, p.debt_cents))
            # Outside the transaction: refresh_continuous_aggregate cannot run inside one.
            # Also runs for a repeated save, so a refresh that failed earlier is retried.
            last = max((p.month for p in record.points), default=0)
            conn.execute(f"CALL refresh_continuous_aggregate('{s}.projection_yearly', 0, %s)", (last + 12,))
            row = conn.execute(f"SELECT {_SUMMARY_COLUMNS} FROM {s}.scenario_run WHERE input_hash = %s",
                               (record.input_hash,)).fetchone()
            return _summary(row), created

        return self._run(write)

    def list_runs(self, profile_id: str, limit: int) -> list[RunSummary]:
        s = self.schema
        return self._run(lambda conn: [_summary(r) for r in conn.execute(
            f"SELECT {_SUMMARY_COLUMNS} FROM {s}.scenario_run WHERE profile_id = %s "
            f"ORDER BY created_at DESC, run_id LIMIT %s", (profile_id, limit)).fetchall()])

    def get_runs(self, run_ids: list[str]) -> dict[str, RunSummary]:
        s = self.schema
        rows = self._run(lambda conn: conn.execute(
            f"SELECT {_SUMMARY_COLUMNS} FROM {s}.scenario_run WHERE run_id = ANY(%s::uuid[])",
            (run_ids,)).fetchall())
        return {r.run_id: r for r in map(_summary, rows)}

    def yearly(self, pairs: list[tuple[str, str]]) -> dict[str, list[YearRow]]:
        """Roll-up rows for each (run_id, strategy), ordered by month."""
        s = self.schema

        def read(conn):
            out: dict[str, list[YearRow]] = {run_id: [] for run_id, _ in pairs}
            rows = conn.execute(
                f"SELECT y.run_id::text, y.strategy, y.month, y.projected_on, y.retirement_balance_cents, "
                f"y.cash_cents, y.debt_cents FROM {s}.projection_yearly y "
                f"JOIN unnest(%s::uuid[], %s::text[]) AS want(run_id, strategy) USING (run_id, strategy) "
                f"ORDER BY y.run_id, y.strategy, y.bucket",
                ([r for r, _ in pairs], [st for _, st in pairs]),
            ).fetchall()
            for r in rows:
                out[r[0]].append(YearRow(*r))
            return out

        return self._run(read)

    def delete(self, run_id: str) -> bool:
        """Removes a run and its points (ON DELETE CASCADE), then refreshes the yearly roll-up."""
        s = self.schema

        def remove(conn):
            with conn.transaction():
                last = conn.execute(f"SELECT max(month) FROM {s}.projection_point WHERE run_id = %s", (run_id,)).fetchone()[0]
                gone = conn.execute(f"DELETE FROM {s}.scenario_run WHERE run_id = %s RETURNING run_id", (run_id,)).fetchone()
            if gone and last is not None:
                conn.execute(f"CALL refresh_continuous_aggregate('{s}.projection_yearly', 0, %s)", (last + 12,))
            return gone is not None

        return self._run(remove)


def build_history_store() -> TigerHistoryStore | None:
    """None when TIGER_DATABASE_URL is unset: history is disabled and nothing else changes."""
    url = os.getenv("TIGER_DATABASE_URL", "").strip()
    if not url:
        return None
    schema = os.getenv("TIGER_SCHEMA", "").strip() or "arm"
    if not _SCHEMA_NAME.match(schema):
        from app.config import ConfigError

        raise ConfigError(f"TIGER_SCHEMA={schema!r} must be a lower-case SQL identifier")
    return TigerHistoryStore(url, schema)
