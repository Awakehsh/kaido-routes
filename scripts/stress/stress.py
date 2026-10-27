#!/usr/bin/env python3
"""Main-versus-branch navigation stress comparison.

    scripts/stress/compare.sh <base-ref> <branch-ref> [--select EXPR] [--seeds 1-40]
    scripts/stress/stress.py list [--select EXPR]

See docs/testing/navigation-stress.md. Exit status: 0 when the branch passes,
1 on a regression beyond tolerance, 2 when the comparison could not run.
The last line printed is the report path.
"""

import argparse
import datetime
import fcntl
import hashlib
import itertools
import json
import os
import re
import resource
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

import catalog
import report

REPO = Path(__file__).resolve().parents[2]
HARNESS = "Tests/KaidoScenarioTests/NavigationStressTests.swift"
# Everything a stress row can depend on, besides the harness and toolchain.
INPUTS = ("Package.swift", "Package.resolved", "Sources", "Tests/KaidoScenarioTests", "data")
CACHE = Path(os.environ.get("KAIDO_STRESS_CACHE", "~/Library/Caches/kaido-stress")).expanduser()
STAGE_ONE_SEEDS = 10
# Units one worker process drives before a fresh one takes over: about 0.4 MB
# a unit stays resident, so a process ends near 0.4 GB however long the list.
UNITS_PER_PROCESS = 400


class Failure(Exception):
    """The comparison could not run."""


def log(message):
    print(f"[{datetime.datetime.now():%H:%M:%S}] {message}", flush=True)


def git(*args, cwd=REPO):
    result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise Failure(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def output(*command):
    return subprocess.run(command, capture_output=True, text=True, check=True).stdout


def parse_seeds(text):
    seeds = []
    for part in text.split(","):
        low, _, high = part.partition("-")
        seeds += range(int(low), int(high or low) + 1)
    return seeds


def tree_key(commit, harness, toolchain):
    """Content hash of what determines every row a tree produces."""
    listing = [line for line in git("ls-tree", "-r", commit, "--", *INPUTS).splitlines()
               if not line.endswith("\t" + HARNESS)]
    digest = hashlib.sha256()
    for part in (harness, toolchain.encode(), "\n".join(listing).encode()):
        digest.update(hashlib.sha256(part).digest())
    return digest.hexdigest()[:24]


class Results:
    """Cached rows of one tree key: one jsonl line per unit, written by workers."""

    def __init__(self, key):
        self.directory = CACHE / "results" / key
        self.units = {}

    def load(self):
        self.units = {}
        for path in sorted(self.directory.glob("*.jsonl")):
            for line in path.read_text().splitlines():
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue  # a worker killed mid-write; that unit runs again
                self.units.setdefault(tuple(entry["unit"]), entry["rows"])
        return self


class Tree:
    """A worktree slot under the cache, locked for one comparison."""

    def __init__(self, side, commit):
        self.side, self.commit = side, commit
        root = CACHE / "trees"
        root.mkdir(parents=True, exist_ok=True)
        # A free slot already at the commit builds nothing; any free slot builds incrementally.
        existing = sorted(root.glob("slot-*.lock"), key=lambda p: int(p.stem.split("-")[1]))
        at_commit = [p for p in existing if self._head(p.with_suffix("")) == commit]
        others = [p for p in existing if p not in at_commit]
        fresh = (root / f"slot-{n}.lock" for n in itertools.count(len(existing)))
        for lock_path in itertools.chain(at_commit, others, fresh):
            self.lock = open(lock_path, "w")
            try:
                fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                self.lock.close()
        self.path = lock_path.with_suffix("")
        if (self.path / ".git").exists():
            git("checkout", "--force", "--quiet", "--detach", commit, cwd=self.path)
            git("clean", "-fdq", "-e", HARNESS, cwd=self.path)
        else:
            git("worktree", "prune")
            git("worktree", "add", "--detach", "--quiet", str(self.path), commit)
        # An unchanged harness keeps its timestamp, so an unchanged tree builds nothing.
        target = self.path / HARNESS
        if not target.exists() or target.read_bytes() != (REPO / HARNESS).read_bytes():
            shutil.copyfile(REPO / HARNESS, target)

    @staticmethod
    def _head(path):
        if not path.exists():
            return None
        result = subprocess.run(["git", "rev-parse", "HEAD"], cwd=path, capture_output=True, text=True)
        return result.stdout.strip() if result.returncode == 0 else None

    def build(self, log_path):
        with open(log_path, "w") as stream:
            code = subprocess.run(["swift", "build", "-c", "release", "--build-tests"],
                                  cwd=self.path, stdout=stream, stderr=subprocess.STDOUT).returncode
        if code != 0:
            raise Failure(f"{self.side} build failed ({self.commit[:9]}); see {log_path}")
        bin_path = subprocess.run(["swift", "build", "-c", "release", "--show-bin-path"], cwd=self.path,
                                  capture_output=True, text=True, check=True).stdout.strip()
        self.bundle = Path(bin_path) / "KaidoRoutesPackageTests.xctest"


def run_units(tree, units, results, run_dir, jobs):
    """Drives `units` on one worker process per job; returns (wall, cpu) seconds."""
    run_dir.mkdir(parents=True)
    (run_dir / "units.tsv").write_text("".join("\t".join(map(str, u)) + "\n" for u in units))
    results.directory.mkdir(parents=True, exist_ok=True)
    stamp = run_dir.name
    workers = min(jobs, len(units))
    claims = run_dir / "claims"

    def unclaimed():
        if not claims.exists():
            return True
        with open(claims) as stream:
            fcntl.flock(stream, fcntl.LOCK_SH)
            return int(stream.read() or 0) < len(units)

    def start(i):
        env = dict(os.environ, KAIDO_STRESS_UNITS=str(run_dir / "units.tsv"),
                   KAIDO_STRESS_CLAIMS=str(claims),
                   KAIDO_STRESS_UNITS_PER_PROCESS=str(UNITS_PER_PROCESS),
                   KAIDO_STRESS_OUT=str(results.directory / f"{stamp}-{i}.jsonl"))
        return subprocess.Popen(
            ["xcrun", "xctest", "-XCTest", "NavigationStressTests/testDriveUnits", str(tree.bundle)],
            cwd=tree.path, env=env, stdout=open(run_dir / f"worker-{i}.log", "a"), stderr=subprocess.STDOUT)

    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.monotonic()
    # A worker process stops after UNITS_PER_PROCESS units, so each slot
    # starts another while the list has units left.
    running = {i: start(i) for i in range(workers)}
    codes = []
    while running:
        for i, process in list(running.items()):
            code = process.poll()
            if code is None:
                continue
            del running[i]
            codes.append(code)
            if code == 0 and unclaimed():
                running[i] = start(i)
        time.sleep(0.2)
    wall = time.monotonic() - started
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu = (after.ru_utime - before.ru_utime) + (after.ru_stime - before.ru_stime)
    if any(codes):
        raise Failure(f"{tree.side} worker exit codes {codes}; see {run_dir}/worker-*.log")
    return wall, cpu


def unit_rows(units, results, side):
    rows, errors = [], []
    for u in units:
        if u not in results.units:
            raise Failure(f"{side} has no result for unit {u}")
        for row in results.units[u]:
            (errors if "error" in row else rows).append(row)
    return rows, errors


def write_rows(path, rows):
    path.write_text("".join("ZZR " + json.dumps(r, sort_keys=True) + "\n" for r in rows))


def compare(args):
    started = time.monotonic()
    base_commit = git("rev-parse", "--verify", f"{args.base}^{{commit}}").strip()
    branch_commit = git("rev-parse", "--verify", f"{args.branch}^{{commit}}").strip()
    harness = (REPO / HARNESS).read_bytes()
    toolchain = output("swift", "--version") + output("xcrun", "--sdk", "macosx", "--show-sdk-build-version")
    keys = {"base": tree_key(base_commit, harness, toolchain), "branch": tree_key(branch_commit, harness, toolchain)}
    commits = {"base": base_commit, "branch": branch_commit}
    refs = {"base": args.base, "branch": args.branch}
    results = {side: Results(keys[side]).load() for side in keys}
    cells = catalog.select(args.select, args.routes)
    seeds = parse_seeds(args.seeds)
    stages = [seeds[:STAGE_ONE_SEEDS], seeds[STAGE_ONE_SEEDS:]] if len(seeds) > STAGE_ONE_SEEDS else [seeds]

    def units(stage_seeds):
        listed = [(c["group"], c["route"], c["profile"], c["extra"], s) for c in cells for s in stage_seeds]
        return sorted(listed, key=lambda u: -catalog.cost(u))

    # One run per distinct key: a branch whose inputs equal the base's shares its rows.
    sides = ["base"] + (["branch"] if keys["branch"] != keys["base"] else [])
    needed = [s for s in sides if any(u not in results[s].units for stage in stages for u in units(stage))]
    log(f"base {refs['base']} {base_commit[:9]} key {keys['base']}; branch {refs['branch']} {branch_commit[:9]} "
        f"key {keys['branch']}; {len(cells)} cells x {len(seeds)} seeds; to run: {', '.join(needed) or 'nothing'}")

    timings = []
    trees = {}
    if needed:
        build_started = time.monotonic()
        trees = {s: Tree(s, commits[s]) for s in needed}
        failures = []

        def build(side):
            try:
                trees[side].build(args.out / f"build-{side}.log")
            except Failure as error:
                failures.append(str(error))

        threads = [threading.Thread(target=build, args=(s,)) for s in needed]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        if failures:
            raise Failure("; ".join(failures))
        timings.append(f"build {', '.join(needed)} in parallel: {time.monotonic() - build_started:.0f} s")
        log(timings[-1])

    def rows_for(stage_seeds):
        listed = units(stage_seeds)
        base_rows, base_errors = unit_rows(listed, results["base"], "base")
        branch_rows, branch_errors = unit_rows(listed, results[sides[-1]], "branch")
        if base_errors or branch_errors:
            raise Failure(f"harness errors: {(base_errors + branch_errors)[:3]}")
        return report.index(base_rows), report.index(branch_rows)

    def header(stage_seeds):
        lines = [f"- Base: `{refs['base']}` {base_commit[:12]}, inputs key `{keys['base']}`",
                 f"- Branch: `{refs['branch']}` {branch_commit[:12]}, inputs key `{keys['branch']}`"
                 + (" (same inputs as base: rows identical by construction)" if len(sides) == 1 else ""),
                 f"- Selection: `{args.select}`{f' with routes from {args.routes}' if args.routes else ''}: {len(cells)} cells, seeds {stage_seeds[0]}–{stage_seeds[-1]} "
                 f"({len(stage_seeds)} seeds)"]
        return lines + [f"- {t}" for t in timings]

    passed = True
    for number, stage_seeds in enumerate(stages, 1):
        listed = units(stage_seeds)
        for side in needed:
            missing = [u for u in listed if u not in results[side].units]
            if not missing:
                continue
            load = os.getloadavg()[0]
            stamp = f"{datetime.datetime.now():%Y%m%d-%H%M%S}-{side}-stage{number}"
            wall, cpu = run_units(trees[side], missing, results[side], args.out / "runs" / stamp, args.jobs)
            results[side].load()
            timings.append(f"stage {number} {side}: {len(missing)} units ({len(listed) - len(missing)} cached) in "
                           f"{wall:.0f} s, {cpu / wall:.1f} cores busy of {args.jobs} workers "
                           f"(machine load average {load:.0f} at start)")
            log(timings[-1])
        cached = [f"{s} {len(listed)} cached" for s in sides if s not in needed]
        if cached:
            timings.append(f"stage {number}: " + ", ".join(cached))
        if number == 1 and len(stages) > 1:
            base, branch = rows_for(stage_seeds)
            title = f"Navigation stress, stage 1: {refs['branch']} vs {refs['base']}"
            body, passed = report.markdown(title, header(stage_seeds), base, branch, counts_only=True)
            (args.out / "interim.md").write_text(body)
            log(f"stage 1 {'passes' if passed else 'FAILS'}: {args.out / 'interim.md'}")
            if not passed and not args.all_stages:
                timings.append(f"total {time.monotonic() - started:.0f} s")
                note = (f"Stopped after stage 1 (seeds {stage_seeds[0]}–{stage_seeds[-1]}): a count regression or "
                        "contract-line crossing. Pass `--all-stages` to run every seed anyway.")
                body, _ = report.markdown(title, header(stage_seeds), base, branch, counts_only=True, note=note)
                (args.out / "report.md").write_text(body)
                write_rows(args.out / "base.jsonl", base.values())
                write_rows(args.out / "branch.jsonl", branch.values())
                return 1
    timings.append(f"total {time.monotonic() - started:.0f} s")
    base, branch = rows_for(seeds)
    body, passed = report.markdown(f"Navigation stress: {refs['branch']} vs {refs['base']}", header(seeds), base, branch)
    (args.out / "report.md").write_text(body)
    write_rows(args.out / "base.jsonl", base.values())
    write_rows(args.out / "branch.jsonl", branch.values())
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("compare", help="compare two refs")
    run.add_argument("base")
    run.add_argument("branch")
    listing = sub.add_parser("list", help="list the selected cells")
    for p in (run, listing):
        p.add_argument("--select", default="default", help="tag selection (default: %(default)s)")
        p.add_argument("--routes", type=Path, help="extra via: routes, one per line, tagged via and sweep")
    run.add_argument("--seeds", default="1-40", help="seeds, e.g. 1-40 or 1,5,9 (default: %(default)s)")
    run.add_argument("--all-stages", action="store_true", help="run every seed even when seeds 1-10 already fail")
    run.add_argument("--jobs", type=int, default=os.cpu_count(), help="worker processes (default: %(default)s)")
    run.add_argument("--out", type=Path, help="report directory (default: under the cache)")
    args = parser.parse_args()

    if args.command == "list":
        try:
            cells = catalog.select(args.select, args.routes)
        except ValueError as error:
            sys.exit(f"error: {error}")
        for c in cells:
            print(f"{c['group']:12} {c['route']:70} {c['profile']:9} {c['extra']:18} {' '.join(sorted(c['tags']))}")
        print(f"{len(cells)} cells; {sum(catalog.cost((c['group'], c['route'], c['profile'], c['extra'])) for c in cells) * 40:,} fixes over 40 seeds")
        return 0

    safe = lambda ref: re.sub(r"[^A-Za-z0-9._-]+", "_", ref)
    # Workers run inside the tree slots, so every path handed to them is absolute.
    args.out = (args.out or CACHE / "reports" / f"{datetime.datetime.now():%Y%m%d-%H%M%S}-{safe(args.branch)}-vs-{safe(args.base)}").resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    try:
        code = compare(args)
    except (Failure, ValueError) as error:
        (args.out / "report.md").write_text(f"# Navigation stress: could not run\n\n{error}\n")
        log(f"error: {error}")
        code = 2
    log(f"exit {code}")
    print(args.out / "report.md")
    return code


if __name__ == "__main__":
    sys.exit(main())
