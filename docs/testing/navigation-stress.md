# Navigation stress comparison

A pull request that changes matcher, session, entry, join or routing behaviour
needs a main-versus-branch stress table over seeds 1–40 before the owner is
asked to merge it. The CI replay gate runs two seeds; this comparison runs
every selected drive at forty, through the same 1 Hz replay gate
(`LiveNavigationReplayGate`), on this Mac only. It never runs in CI.

```sh
git fetch origin
scripts/stress/compare.sh origin/main <branch-ref>
```

Both arguments are committed refs. The command builds each in release in its
own worktree, drives every selected unit that is not already cached, writes
`report.md`, `base.jsonl` and `branch.jsonl` (one `ZZR {json}` row per drive),
and prints the report path as its last line, so a background launch learns the
outcome when it exits. Exit status 0 means the branch passes, 1 a regression
beyond tolerance, 2 that the comparison could not run (the report says why).

| Option | Effect |
|---|---|
| `--select EXPR` | Which cells to drive (default `default`; see below) |
| `--routes FILE` | Add `via:` routes, one per line (first tab-separated column) |
| `--seeds 1-40` | Seeds, as ranges or a list (`1-10`, `3,7,21`) |
| `--all-stages` | Run seeds 11–40 even when seeds 1–10 already fail |
| `--jobs N` | Worker processes (default: every core) |
| `--out DIR` | Report directory (default: under the cache) |

`scripts/stress/stress.py list --select EXPR` prints the cells a selection
covers, with their tags, without building anything.

## What a comparison drives

A cell is one group, route, noise profile and variant; a unit is a cell at one
seed. The groups are the Phase A drives:

| Group | Drive |
|---|---|
| `planned` | the whole plan, entrance to completion |
| `missedFinal` | the last choice of road before the exit or PA taken wrong, 1.5 km |
| `wrongBranch` | a reviewed divergent junction (C1 283 and 487, C2 234, Bayshore 130) taken wrong, in the bundled release or in a lap of a runtime loop; and every plan fork whose untaken road runs beside the plan (`beside-fork`, listed in `scripts/stress/beside-forks.tsv`), 2.5 km past the fork |
| `stopBypass` | the Daikoku PA stop of a loop driven past |
| `paReentry` | the lap-1 PA stop driven again in lap 2 |
| `lapChange` | drop one lap or finish the current lap mid-drive |

Routes are the five bundled releases, the runtime loops `c1-inner`, `c1-outer`,
`c2`, `daikoku` and `stop` (the Daikoku loop with a PA stop), and the loops
entered from a radial route (`c1-inner-s1`, `c1-outer-s1`, `c2-s1` from
新郷, `c1-inner-r4`, `c1-outer-r4` from 代々木), each at one, two or three laps.
Profiles are `URBAN`, `MULTIPATH` and `UNDER2X`.

`--routes FILE` adds any planned circuit as
`via:<circuit>:<entry facility>:<exit facility or ->:<laps>`, with circuit
`c1i`, `c1o`, `c2`, `wangan`, `daikoku` or `scenic` and `-` for the circuit's
default destination. Each gets `planned` and `missedFinal` cells tagged `via`,
`sweep`, `via:<circuit>` and its lap count; none is in the default set.

### Selection

Every cell carries tags: its group, profile and route (`loop:c2:2`), its
family (`loop`, `radial`, `bundled`, `lapchange`, `c1-inner`, `bundled:c2`, …),
its lap count (`laps1`, `laps2`, `laps3`), `pa-end` when the drive ends inside
a PA rather than at an exit, and `default` when the default set includes it. A selection is comma-separated terms; `+` joins tags a cell must
all carry, a leading `-` removes cells, and `all` matches everything:

```sh
--select 'default,-radial'                 # the default set without radial entries
--select 'default,-pa-end'                 # only drives that end at an exit
--select 'wrongBranch+c2'                  # every C2 wrong-branch cell
--select 'default,planned+laps3'           # add three-lap planned drives
--select all                               # every cell the harness knows
```

The default set is every group and route at one and two laps, plus the bundled
releases, the lap changes (three-lap drives by construction), and the
`later-lap` wrong branches: lap 2 of a three-lap loop, the only lap that is
neither the first nor the last. Final-lap logic needs one and two laps; a third
lap repeats them. On two laps `lap=2` and `lap=last` are the same drives, so
the default keeps `lap=last` only. That is 207 of 990 cells. The beside-road
forks are a selection of their own, `beside-fork` (699 cells, about 42 M fixes
over 40 seeds against the default's 25 M), so a comparison where they do not
matter does not pay for them.

## Stages

Seeds 1–10 run first, for both trees, and `interim.md` compares them on counts
alone: one more run over a contract line, one more wrong commit, incomplete
drive or undetected deviation is an early red. Seeds 11–40 run only when
stage 1 is clean, or with `--all-stages`; the final report always covers every
requested seed.

## Report and verdict

A row is one group, route and profile over every seed and drive variant in it.
Timing metrics (unadmitted median/p95/max, false-recovery median/p95/max,
detection latency median/max) are worse at +5 s or more. Counts are worse at
+1: runs over the 75 s unadmitted and 300 s false-recovery contract lines,
#73 wrong commits, entry failures, handovers, incomplete or early completions,
undetected deviations, off-plan advances, false arrivals, completions on a
missed exit, unskipped stops and wrong lap landings. The branch passes when:

1. no URBAN or MULTIPATH row is worse;
2. UNDER2X wrong-branch runs with off-plan progress do not increase;
3. #73 wrong-commit runs and fixes do not increase;
4. every run pairs with a run in the other tree (a branch that moves the final
   divergence or its alternatives leaves runs unpaired; the report counts them).

UNDER2X rows that are worse are listed for information. The report also lists,
per worse row, the seeds that move it, and headline counts per group and
profile for both trees.

## Cache

Rows are cached per unit under `~/Library/Caches/kaido-stress/results/<key>/`
(`KAIDO_STRESS_CACHE` moves the whole cache). The key hashes the git blob
listing of `Package.swift`, `Package.resolved`, `Sources/`,
`Tests/KaidoScenarioTests/` and `data/` at the ref, the harness file the
command copies in, and the `swift --version` and SDK build. Any change to those
inputs gives a new key, so nothing is invalidated by hand; a key never runs a
unit twice. A branch with the same key as the base (a docs-, App- or
script-only change) reuses the base's rows and costs nothing. Delete the
directory to reclaim space.

`~/Library/Caches/kaido-stress/trees/slot-N` are the worktrees, reused so
builds stay incremental, each locked while a comparison uses it; concurrent
comparisons take different slots. Reports default to
`~/Library/Caches/kaido-stress/reports/`.

## Workers

Each tree runs one single-threaded worker process per core over a shared,
longest-first unit list, each claiming the next unit from a counter file.
Drives in one process do not scale across threads: they share the fixture's
route-plan storage, and retain/release on it becomes contended atomics. Separate
processes share nothing.

A process keeps about 0.4 MB per unit it drives, because XCTest holds state for
every throw until the test ends. So a worker stops after 400 units
(`KAIDO_STRESS_UNITS_PER_PROCESS`), and its slot starts a fresh process while
units remain. Without that, a worker grows with its share of the list: about
2.5 GB each for a full comparison on 16 cores. A measuring probe that also kept
per-fix data took eight workers to 9 GB each, and this 48 GB Mac to a kernel
panic.

## The harness

`Tests/KaidoScenarioTests/NavigationStressTests.swift` drives the units. It is
an XCTest that skips unless `KAIDO_STRESS_UNITS` names a unit list, so
`swift test` and CI never run it. To drive units by hand from a built tree:

```sh
printf 'planned\tloop:c2:2\tURBAN\t\t7\n' > /tmp/units.tsv
KAIDO_STRESS_UNITS=/tmp/units.tsv KAIDO_STRESS_CLAIMS=/tmp/claims \
KAIDO_STRESS_OUT=/tmp/rows.jsonl KAIDO_STRESS_TRACE=/tmp/trace.txt \
  xcrun xctest -XCTest NavigationStressTests/testDriveUnits \
  .build/release/KaidoRoutesPackageTests.xctest
```

`KAIDO_STRESS_TRACE` appends a per-fix trace of every drive. Remove the claims
file before reusing it. A new route needs its fixture in the harness, its cells
in `scripts/stress/catalog.py`, and its approximate fixes in `FIXES`.
