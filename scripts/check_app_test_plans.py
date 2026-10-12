#!/usr/bin/env python3
"""Fail when an App test runs in no Xcode test plan, or a plan names a missing test.

Each test plan includes its targets whole and lists what it skips, so a new
test class runs without anyone remembering to add it. This check keeps that
true: every XCTest method under the App test targets must run in at least
one plan, and every selected or skipped entry must still name a real test,
because xcodebuild silently ignores an entry that matches nothing.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
TEST_PLAN_DIRECTORY = REPOSITORY_ROOT / "Apps" / "KaidoRoutesApp" / "TestPlans"
TEST_TARGET_SOURCES = {
    "KaidoRoutesAppTests": REPOSITORY_ROOT / "Apps" / "KaidoRoutesApp" / "Tests",
    "KaidoRoutesAppUITests": REPOSITORY_ROOT / "Apps" / "KaidoRoutesApp" / "UITests",
}

CLASS_PATTERN = re.compile(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b")
METHOD_PATTERN = re.compile(r"(?<!static )\bfunc\s+(test\w*)\s*\(\s*\)")


def discover_tests(source_directory: Path) -> dict[str, set[str]]:
    """Map each XCTestCase subclass to its `test…()` methods."""
    tests: dict[str, set[str]] = {}
    for path in sorted(source_directory.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        classes = [(match.start(), match.group(1)) for match in CLASS_PATTERN.finditer(text)]
        for match in METHOD_PATTERN.finditer(text):
            owners = [name for start, name in classes if start < match.start()]
            if not owners:
                continue
            tests.setdefault(owners[-1], set()).add(match.group(1))
    return tests


def expand(
    entries: list[str],
    tests: dict[str, set[str]],
    plan: str,
    target: str,
    errors: list[str],
) -> set[tuple[str, str]]:
    """Resolve `Class` and `Class/method()` entries to (class, method) pairs."""
    resolved: set[tuple[str, str]] = set()
    for entry in entries:
        class_name, _, method = entry.partition("/")
        method = method.removesuffix("()")
        if class_name not in tests:
            errors.append(f"{plan}: {target} names missing test class {entry}")
        elif not method:
            resolved |= {(class_name, name) for name in tests[class_name]}
        elif method not in tests[class_name]:
            errors.append(f"{plan}: {target} names missing test {entry}")
        else:
            resolved.add((class_name, method))
    return resolved


def check(
    plan_paths: list[Path],
    target_sources: dict[str, Path],
) -> list[str]:
    errors: list[str] = []
    tests = {target: discover_tests(path) for target, path in target_sources.items()}
    covered: dict[str, set[tuple[str, str]]] = {target: set() for target in tests}
    for plan_path in plan_paths:
        plan = json.loads(plan_path.read_text(encoding="utf-8"))
        for entry in plan.get("testTargets", []):
            target = entry["target"]["name"]
            if target not in tests:
                errors.append(f"{plan_path.name}: unknown test target {target}")
                continue
            if entry.get("enabled", True) is False:
                continue
            every = {
                (class_name, method)
                for class_name, methods in tests[target].items()
                for method in methods
            }
            selected = (
                expand(entry["selectedTests"], tests[target], plan_path.name, target, errors)
                if "selectedTests" in entry
                else every
            )
            skipped = expand(
                entry.get("skippedTests", []), tests[target], plan_path.name, target, errors
            )
            covered[target] |= selected - skipped
    for target, classes in tests.items():
        for class_name, methods in sorted(classes.items()):
            for method in sorted(methods):
                if (class_name, method) not in covered[target]:
                    errors.append(
                        f"{target}/{class_name}/{method}() runs in no test plan"
                    )
    return errors


def main() -> int:
    plan_paths = sorted(TEST_PLAN_DIRECTORY.glob("*.xctestplan"))
    errors = check(plan_paths, TEST_TARGET_SOURCES)
    if errors:
        print("App test plan check failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1
    print(
        f"Every App test runs in at least one of {len(plan_paths)} test plans: "
        + ", ".join(path.name for path in plan_paths)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
