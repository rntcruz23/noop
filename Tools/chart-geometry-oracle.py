#!/usr/bin/env python3
from datetime import date


def positions(keys: list[str], start: str, end: str) -> list[float] | None:
    try:
        start_day = date.fromisoformat(start)
        end_day = date.fromisoformat(end)
        days = [date.fromisoformat(key) for key in keys]
    except ValueError:
        return None
    span = (end_day - start_day).days
    if span <= 0:
        return None
    result = [(day - start_day).days / span for day in days]
    if any(value < 0 or value > 1 for value in result):
        return None
    if any(right < left for left, right in zip(result, result[1:])):
        return None
    return result


def segments(keys: list[str], source_ids: list[str] | None = None) -> list[str] | None:
    try:
        days = [date.fromisoformat(key) for key in keys]
    except ValueError:
        return None
    sources = source_ids if source_ids is not None and len(source_ids) == len(days) else None
    run = 0
    result: list[str] = []
    for index, day in enumerate(days):
        if index and ((day - days[index - 1]).days != 1 or (sources and sources[index] != sources[index - 1])):
            run += 1
        result.append(f"{run}:{sources[index] if sources else 'default'}")
    return result


cases = [
    ("calendar", positions(["2026-01-01", "2026-01-02", "2026-01-11"], "2026-01-01", "2026-01-11")),
    ("leap", positions(["2024-02-28", "2024-02-29", "2024-03-01"], "2024-02-28", "2024-03-01")),
    ("gaps", segments(["2026-01-01", "2026-01-02", "2026-01-04", "2026-01-05", "2026-01-06"], ["a", "a", "a", "b", "a"])),
    ("invalid", positions(["not-a-day"], "2026-01-01", "2026-01-11")),
]
for name, value in cases:
    print(f"{name}={value}")
