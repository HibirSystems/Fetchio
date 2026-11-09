"""Normalization helpers for values returned by media extractors."""
from __future__ import annotations

from decimal import Decimal, InvalidOperation, ROUND_FLOOR
from typing import Any


def normalize_duration(value: Any) -> int | None:
    """Floor finite nonnegative seconds; omit unknown/nonfinite values.

    Negative values and malformed numeric strings are rejected.
    """
    if value is None:
        return None
    if isinstance(value, bool):
        raise ValueError("duration must be a non-negative number")
    if isinstance(value, str) and not value.strip():
        return None

    try:
        duration = Decimal(str(value))
    except (InvalidOperation, ValueError):
        raise ValueError("duration must be numeric") from None

    if not duration.is_finite():
        return None
    if duration < 0:
        raise ValueError("duration must be non-negative")
    return int(duration.to_integral_value(rounding=ROUND_FLOOR))
