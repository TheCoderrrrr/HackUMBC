"""One canonical JSON and hash implementation for A's API and C's exporter."""

from __future__ import annotations

from dataclasses import asdict, is_dataclass
from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from hashlib import sha256
import json
import math
from typing import Any

from .simulation import get, optional


def _plain(value: Any) -> Any:
    if hasattr(value, "model_dump"):
        return _plain(value.model_dump(mode="json", exclude_unset=False))
    if is_dataclass(value) and not isinstance(value, type):
        return _plain(asdict(value))
    if isinstance(value, dict):
        return {str(key): _plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_plain(item) for item in value]
    if isinstance(value, Enum):
        return _plain(value.value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, bool) or value is None or isinstance(value, (int, str)):
        return value
    if isinstance(value, (float, Decimal)):
        number = Decimal(str(value))
        if not number.is_finite():
            raise ValueError("non-finite numeric input cannot be hashed")
        if number == 0:
            return 0
        if number == number.to_integral_value():
            return int(number)
        normalized = float(number.normalize())
        if not math.isfinite(normalized):
            raise ValueError("numeric input cannot be represented in JSON")
        return normalized
    raise TypeError(f"unsupported canonical value: {type(value).__name__}")


def canonical_json(value: Any) -> bytes:
    """Serialize validated/default-populated models with stable logical numbers."""
    return json.dumps(
        _plain(value), sort_keys=True, separators=(",", ":"),
        ensure_ascii=False, allow_nan=False,
    ).encode("utf-8")


def digest(value: Any) -> str:
    return sha256(canonical_json(value)).hexdigest()


def profile_hash(profile: Any) -> str:
    return digest(profile)


def input_hash(
    profile: Any,
    scenario: Any,
    assumptions: Any,
    decision: Any,
    *,
    schema_version: str,
    model_version: str,
    policy_version: str,
) -> str:
    """Exclude generated text, opaque IDs, timestamps and prior decision IDs."""
    return digest({
        "profile": profile,
        "scenario": scenario,
        "assumptions": assumptions,
        "schema_version": schema_version,
        "model_version": model_version,
        "policy_version": policy_version,
        "decision": {
            "source": get(decision, "source"),
            "ordered_priorities": get(decision, "ordered_priorities"),
            "model_id": optional(decision, "model_id"),
            "prompt_version": get(decision, "prompt_version"),
        },
    })
