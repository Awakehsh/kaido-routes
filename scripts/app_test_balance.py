#!/usr/bin/env python3
"""Split one App test target into shards of about equal measured duration.

`record` reads xcodebuild test logs and prints each passed test's median
duration as JSON. `select` deals the recorded tests longest first, each onto
the shard with the least time so far, and prints xcodebuild arguments for
one shard. Every shard but the last runs its tests by name; the last runs
the whole target and skips the tests the others run. A test the durations do
not name, such as a new one, therefore runs in the last shard, so every
enabled test runs exactly once without a hand-kept list. Stale durations
only unbalance the shards.

Refresh the durations from a run's test logs with:

    python3 scripts/app_test_balance.py record LOG... \
      > Apps/KaidoRoutesApp/TestPlans/verify-unit-test-durations.json
"""

from __future__ import annotations

import json
import re
import statistics
import sys
from pathlib import Path

PASSED_TEST = re.compile(
    r"Test Case '-\[(\w+)\.(\w+) (\w+)\]' passed \((\d+(?:\.\d+)?) seconds\)"
)


def record(logs: list[str]) -> dict[str, float]:
    samples: dict[str, list[float]] = {}
    for log in logs:
        for target, test_class, method, seconds in PASSED_TEST.findall(log):
            samples.setdefault(f"{target}/{test_class}/{method}", []).append(float(seconds))
    return {test: round(statistics.median(times), 3) for test, times in sorted(samples.items())}


def shards(durations: dict[str, float], target: str, count: int) -> list[list[str]]:
    tests = sorted(
        (test for test in durations if test.startswith(f"{target}/")),
        key=lambda test: (-durations[test], test),
    )
    loads = [0.0] * count
    assigned: list[list[str]] = [[] for _ in range(count)]
    for test in tests:
        lightest = loads.index(min(loads))
        loads[lightest] += durations[test]
        assigned[lightest].append(test)
    return [sorted(names) for names in assigned]


def select(durations: dict[str, float], target: str, index: int, count: int) -> list[str]:
    assigned = shards(durations, target, count)
    if index < count:
        # An empty -only-testing list would run the whole plan instead of nothing.
        if not assigned[index - 1]:
            raise ValueError(f"shard {index}/{count} has no recorded tests")
        return [f"-only-testing:{test}" for test in assigned[index - 1]]
    return [f"-only-testing:{target}"] + [
        f"-skip-testing:{test}" for names in assigned[:-1] for test in names
    ]


def main() -> int:
    arguments = sys.argv[1:]
    if len(arguments) >= 2 and arguments[0] == "record":
        logs = [Path(path).read_text(encoding="utf-8", errors="replace") for path in arguments[1:]]
        print(json.dumps(record(logs), indent=2))
        return 0
    if len(arguments) == 4 and arguments[0] == "select":
        index, count = (int(part) for part in arguments[3].split("/"))
        if not 1 <= index <= count:
            print(f"shard {arguments[3]} is out of range", file=sys.stderr)
            return 2
        durations = json.loads(Path(arguments[1]).read_text(encoding="utf-8"))
        try:
            selection = select(durations, arguments[2], index, count)
        except ValueError as error:
            print(error, file=sys.stderr)
            return 1
        print("\n".join(selection))
        return 0
    print(
        "usage: app_test_balance.py record LOG...\n"
        "       app_test_balance.py select DURATIONS_JSON TEST_TARGET INDEX/COUNT",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
