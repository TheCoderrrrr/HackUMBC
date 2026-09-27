"""Compose one complete, provider-free Evaluation from the shared engine."""

from __future__ import annotations

from importlib import import_module
from typing import Any, Callable

from .canonical import input_hash
from .monthly import EngineInvariantError, MissingHandoffError
from .simulation import get, optional, projection_dict, run_simulation


def _handoff(module_name: str, attribute: str) -> Any:
    try:
        return getattr(import_module(module_name), attribute)
    except (ImportError, AttributeError) as exc:
        raise MissingHandoffError(f"Required A/B handoff: {module_name}.{attribute}") from exc


def _json(value: Any) -> Any:
    """Convert dataclasses/Pydantic values to JSON-compatible response values."""
    from .canonical import _plain

    return _plain(value)


def _check_opening_plan(plan: dict[str, Any], opening: dict[str, Any]) -> None:
    """B's display actions must equal the allocation C actually simulates."""
    actions = {action["id"]: action for action in plan["actions"]}
    employee = actions.get("employee-contribution")
    if employee is None or (
        employee["employee_contribution_cents"] != opening["employee_contribution_cents"]
        or employee["monthly_cash_cost_cents"] != opening["employee_cash_cost_cents"]
    ):
        raise EngineInvariantError("displayed employee contribution differs from simulation")
    for debt in opening["debts"]:
        displayed = actions.get(f"debt-{debt['id']}")
        if debt["total_payment_cents"] == 0 and displayed is None:
            continue
        if displayed is None or displayed["monthly_cash_cost_cents"] != debt["total_payment_cents"]:
            raise EngineInvariantError(f"displayed payment differs for debt {debt['id']}")
        matching_reason = next((
            reason for reason in plan["reasons"]
            if reason["facts"].get("debt_id") == debt["id"]
        ), None)
        if matching_reason is None or matching_reason["facts"]["extra_payment_cents"] != debt["extra_payment_cents"]:
            raise EngineInvariantError(f"displayed extra payment differs for debt {debt['id']}")
    for action_id, key in (
        ("critical-reserve", "cash_to_critical_reserve_cents"),
        ("starter-reserve", "cash_to_starter_reserve_cents"),
        ("full-reserve", "cash_to_full_reserve_cents"),
        ("residual-cash", "residual_cash_cents"),
    ):
        displayed = actions.get(action_id)
        amount = displayed["monthly_cash_cost_cents"] if displayed else 0
        if amount != opening[key]:
            raise EngineInvariantError(f"displayed {action_id} differs from simulation")
    spent = sum(action["monthly_cash_cost_cents"] for action in plan["actions"])
    if spent != opening["resources_cents"] - opening["living_expenses_cents"]:
        raise EngineInvariantError("displayed household cash differs from simulation")


def evaluate(
    profile: Any,
    scenario: Any,
    validated_decision: Any,
    *,
    assumptions: Any = None,
    state_fn: Callable[..., Any] | None = None,
    allocator: Callable[..., Any] | None = None,
    equity_weight_fn: Callable[[float], float] | None = None,
    plan_fn: Callable[..., Any] | None = None,
    template_fn: Callable[..., Any] | None = None,
    evaluation_model: Any = None,
    schema_version: str = "1",
    model_version: str = "2.0.0",
    policy_version: str = "2.0.0",
) -> Any:
    """Return a complete Evaluation without provider, clock, storage, or IO.

    A/B-owned functions are injectable for development; production imports the
    agreed module handoffs. A's Pydantic Evaluation validates the final shape.
    """
    if assumptions is None:
        if optional(profile, "fund_id"):
            from app.fund_model import resolve
            from app.schemas import FinancialProfile
            assumptions = resolve(profile if isinstance(profile, FinancialProfile) else FinancialProfile.model_validate(profile))
        else:
            assumptions = _handoff("app.engine.assumptions", "MODEL_ASSUMPTIONS")
    state_fn = state_fn or _handoff("app.engine.state", "derive_state")
    use_b_plan = plan_fn is None
    use_b_template = template_fn is None
    if use_b_plan:
        plan_fn = _handoff("app.engine.policy", "build_plan")
    if use_b_template:
        template_fn = _handoff("app.engine.explanations", "template_explanation")
    if evaluation_model is None:
        try:
            evaluation_model = _handoff("app.schemas", "Evaluation")
        except MissingHandoffError:
            evaluation_model = dict

    state = state_fn(_json(profile)) if use_b_plan else state_fn(profile)
    display_state = state
    fund_model = optional(assumptions, "fund_model")
    if fund_model and isinstance(state, dict):
        from app.fund_model import weight
        from app.schemas import FundModel
        model = fund_model if isinstance(fund_model, FundModel) else FundModel.model_validate(fund_model)
        as_of = get(profile, "as_of_date")
        from datetime import date
        if isinstance(as_of, str):
            as_of = date.fromisoformat(as_of)
        display_state = {**state, "baseline_equity_weight": weight(model, as_of, 1, state["months_until_retirement"])}
    current = run_simulation(
        profile, "current", None, assumptions, validated_decision,
        allocator=allocator, equity_weight_fn=equity_weight_fn,
    )
    adaptive = run_simulation(
        profile, "adaptive", None, assumptions, validated_decision,
        allocator=allocator, equity_weight_fn=equity_weight_fn,
    )
    custom = (
        run_simulation(
            profile, "custom", scenario, assumptions, validated_decision,
            allocator=allocator, equity_weight_fn=equity_weight_fn,
        )
        if scenario is not None else None
    )

    if use_b_plan:
        plan = plan_fn(
            _json(profile), _json(state), _json(validated_decision),
        )
        if adaptive.opening_allocation and adaptive.opening_allocation.feasible:
            _check_opening_plan(plan, adaptive.opening_allocation.facts["raw_allocation"])
    else:
        plan = plan_fn(profile, state, validated_decision, allocation=adaptive.opening_allocation)
    # Per-projection warnings: each projection carries its own months' allocator warnings
    # instead of merging every month of every projection into the top level (REPORT C3).
    projections = {
        "current": projection_dict(current.projection) | {"warnings": list(current.warnings)},
        "adaptive": projection_dict(adaptive.projection) | {"warnings": list(adaptive.warnings)},
        "custom": (
            projection_dict(custom.projection) | {"warnings": list(custom.warnings)}
            if custom is not None else None
        ),
    }
    if use_b_template:
        explanation = template_fn(
            _json(profile), _json(state), _json(validated_decision), _json(plan), changes=[],
        )
    else:
        explanation = template_fn(state, plan, projections, validated_decision, changes=[])
    # Top-level warnings cover the financial state and the opening-month plan only —
    # a client can tell what they belong to. Later months stay on their projection.
    opening = adaptive.opening_allocation
    warnings = [
        *optional(state, "warnings", []),
        *list(optional(opening, "warnings", None) or []),
    ]
    if opening is not None and optional(opening, "block_code"):
        warnings.append(optional(opening, "block_code"))
    result = {
        "schema_version": schema_version,
        "model_version": model_version,
        "policy_version": policy_version,
        "profile_id": str(get(profile, "id")),
        "input_hash": input_hash(
            profile, scenario, assumptions, validated_decision,
            schema_version=schema_version,
            model_version=model_version,
            policy_version=policy_version,
        ),
        "financial_state": _json(display_state),
        "plan": _json(plan),
        "assumptions": _json(assumptions),
        "projections": projections,
        "decision_summary": _json(validated_decision),
        "explanation": _json(explanation),
        "warnings": list(dict.fromkeys(warnings)),
    }
    if hasattr(evaluation_model, "model_validate"):
        return evaluation_model.model_validate(result)
    return evaluation_model(**result)
