#!/usr/bin/env python3
"""Print `-only-testing` arguments for one shard of a test target's enabled tests.

Reads the JSON that `xcodebuild test-without-building -enumerate-tests
-test-enumeration-format json` writes, keeps the target's enabled tests,
sorts them, and deals them round-robin, so every enabled test lands in
exactly one shard without a hand-maintained list and each shard gets a share
of every test class. The target filter is applied here because Xcode 26.3
enumerates the whole plan even when given `-only-testing:<target>`.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def shard(enumeration: dict, target: str, index: int, count: int) -> list[str]:
    if enumeration.get("errors"):
        raise ValueError(f"test enumeration failed: {enumeration['errors']}")
    identifiers = sorted(
        test["identifier"].removesuffix("()")
        for value in enumeration["values"]
        for test in value["enabledTests"]
        if test["identifier"].startswith(f"{target}/")
    )
    selected = identifiers[index - 1 :: count]
    # An empty -only-testing list would run the whole plan instead of nothing.
    if not selected:
        raise ValueError(f"shard {index}/{count} of {len(identifiers)} tests is empty")
    return selected


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: app_test_shard.py ENUMERATION_JSON TEST_TARGET INDEX/COUNT",
            file=sys.stderr,
        )
        return 2
    index, count = (int(part) for part in sys.argv[3].split("/"))
    if not 1 <= index <= count:
        print(f"shard {sys.argv[3]} is out of range", file=sys.stderr)
        return 2
    enumeration = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    try:
        identifiers = shard(enumeration, sys.argv[2], index, count)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    for identifier in identifiers:
        print(f"-only-testing:{identifier}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
