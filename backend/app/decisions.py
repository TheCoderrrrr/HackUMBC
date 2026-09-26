"""In-memory prior-decision store for previous_decision_id replay (BACKEND.md section 4/9).

Bounded to 128 entries, oldest-out, two-hour expiry. Only possession of the opaque
decision ID plus a matching profile ID permits comparison. No persistence.
"""
from __future__ import annotations

import secrets
import threading
import time
from collections import OrderedDict
from dataclasses import dataclass, field

from app.schemas import Change, DecisionSummary, EvaluationCore, FinancialProfile, Scalar


@dataclass(frozen=True)
class DecisionSnapshot:
    profile_id: str
    profile_hash: str
    fields: dict[str, Scalar]
    stored_at: float = field(default=0.0)


def new_decision_id() -> str:
    return "dec_" + secrets.token_urlsafe(18)


def snapshot_fields(profile: FinancialProfile, core: EvaluationCore, decision: DecisionSummary) -> dict[str, Scalar]:
    """The facts the Explanation Agent may describe as having changed.

    Profile inputs use canonical profile paths; derived values are prefixed with
    financial_state., plan. or decision.
    """
    state = core.financial_state
    primary = next((a for a in core.plan.actions if a.id == core.plan.primary_action_id), None)
    return {
        "planning_preference": profile.planning_preference,
        "decision.ordered_priorities": ",".join(decision.ordered_priorities),
        "plan.primary_action_id": core.plan.primary_action_id,
        "plan.primary_action.monthly_cash_cost_cents": primary.monthly_cash_cost_cents if primary else None,
        "employee_contribution_rate": profile.employee_contribution_rate,
        "monthly_living_expenses_cents": profile.monthly_living_expenses_cents,
        "emergency_cash_cents": profile.emergency_cash_cents,
        "financial_state.emergency_months": state.emergency_months,
        "financial_state.high_interest_debt_cents": state.high_interest_debt_cents,
        "financial_state.current_monthly_surplus_cents": state.current_monthly_surplus_cents,
    }


def diff(before: dict[str, Scalar], after: dict[str, Scalar]) -> list[Change]:
    return [Change(field_path=k, before=before.get(k), after=v) for k, v in after.items() if before.get(k) != v]


class DecisionStore:
    def __init__(self, max_entries: int = 128, ttl_seconds: float = 7200, clock=time.monotonic):
        self.max_entries, self.ttl, self.clock = max_entries, ttl_seconds, clock
        self._items: OrderedDict[str, DecisionSnapshot] = OrderedDict()
        self._lock = threading.Lock()

    def put(self, decision_id: str, snapshot: DecisionSnapshot) -> None:
        with self._lock:
            self._items[decision_id] = DecisionSnapshot(
                snapshot.profile_id, snapshot.profile_hash, snapshot.fields, stored_at=self.clock()
            )
            while len(self._items) > self.max_entries:
                self._items.popitem(last=False)

    def get(self, decision_id: str, profile_id: str) -> DecisionSnapshot | None:
        with self._lock:
            snap = self._items.get(decision_id)
            if snap is None:
                return None
            if self.clock() - snap.stored_at > self.ttl:
                del self._items[decision_id]
                return None
            return snap if snap.profile_id == profile_id else None

    def __len__(self) -> int:
        return len(self._items)
