"""Base-versus-branch stress verdict and Markdown report.

A row is one (group, route, profile) over every seed and drive variant in it.
Timing metrics regress at +5 s or more; counts, including the 75 s unadmitted
and 300 s false-recovery contract lines, have zero tolerance.
"""

import collections
import math

DEVIATION_GROUPS = ("missedFinal", "wrongBranch", "paReentry")
GATED_PROFILES = ("URBAN", "MULTIPATH")
TIMING_TOLERANCE_S = 5
UNADMITTED_LINE_S = 75
FALSE_RECOVERY_LINE_S = 300


def run_key(row):
    return (row["group"], row["route"], row["profile"], row.get("extra", ""),
            row.get("movement", -1), row.get("alternative", ""), row["seed"])


def detected(row):
    if row["group"] == "missedFinal" and row.get("isPAEnding"):
        return row["finalTrigger"] == "DESTINATION_PARKING_AREA_NOT_ENTERED"
    return row.get("detectPhase") == "ROUTE_RECOVERY" and row.get("detectSeconds", -1) >= 1


def percentile(values, q):
    values = sorted(values)
    return values[max(0, math.ceil(q * len(values)) - 1)] if values else 0


def row_metrics(runs, group):
    """Timing metrics (seconds, +5 s tolerance) and counts (zero tolerance)."""
    unadmitted = [r["unadmitted"] for r in runs]
    false_recovery = [r["falseRecovery"] for r in runs]
    latency = [r["detectSeconds"] for r in runs
               if group in DEVIATION_GROUPS and detected(r) and r.get("detectSeconds", -1) >= 0]
    timing = {
        "unadmitted median": percentile(unadmitted, .5),
        "unadmitted p95": percentile(unadmitted, .95),
        "unadmitted max": max(unadmitted),
        "false-recovery median s": percentile(false_recovery, .5),
        "false-recovery p95 s": percentile(false_recovery, .95),
        "false-recovery max s": max(false_recovery),
    }
    if latency:
        timing["detection latency median"] = percentile(latency, .5)
        timing["detection latency max"] = max(latency)
    counts = {
        f"runs >{UNADMITTED_LINE_S} s unadmitted": sum(1 for x in unadmitted if x > UNADMITTED_LINE_S),
        f"runs >{FALSE_RECOVERY_LINE_S} s false recovery": sum(1 for x in false_recovery if x > FALSE_RECOVERY_LINE_S),
        "wrong (#73) runs": sum(1 for r in runs if r["wrong73"] > 0),
        "entry failures": sum(1 for r in runs if not r["entered"]),
        "handed over": sum(1 for r in runs if r.get("handover")),
    }
    if group in DEVIATION_GROUPS:
        counts["undetected"] = sum(1 for r in runs if not detected(r))
        counts["off-plan advance runs"] = sum(1 for r in runs if r.get("offPlanCommits", 0) > 0)
        if group == "missedFinal" and runs[0].get("isPAEnding"):
            counts["false arrival"] = sum(1 for r in runs if r["finalTrigger"] == "PARKING_AREA_DESTINATION_REACHED")
        elif group != "paReentry":
            counts["completed on missed exit/branch"] = sum(1 for r in runs if r["completed"])
        else:
            counts["incomplete"] = sum(1 for r in runs if not r["completed"])
    else:
        counts["incomplete"] = sum(1 for r in runs if not r["completed"])
        counts["early"] = sum(1 for r in runs if r["early"])
    if group == "stopBypass":
        counts["stop not skipped"] = sum(1 for r in runs if not r.get("stopSkipped"))
    if group == "lapChange":
        counts["lap landed wrong"] = sum(1 for r in runs if not r.get("landedCorrect"))
    return timing, counts


RUN_FLAGS = {
    f"runs >{UNADMITTED_LINE_S} s unadmitted": lambda r: r["unadmitted"] > UNADMITTED_LINE_S,
    f"runs >{FALSE_RECOVERY_LINE_S} s false recovery": lambda r: r["falseRecovery"] > FALSE_RECOVERY_LINE_S,
    "wrong (#73) runs": lambda r: r["wrong73"] > 0,
    "entry failures": lambda r: not r["entered"],
    "handed over": lambda r: r.get("handover"),
    "undetected": lambda r: not detected(r),
    "off-plan advance runs": lambda r: r.get("offPlanCommits", 0) > 0,
    "false arrival": lambda r: r["finalTrigger"] == "PARKING_AREA_DESTINATION_REACHED",
    "completed on missed exit/branch": lambda r: r["completed"],
    "incomplete": lambda r: not r["completed"],
    "early": lambda r: r["early"],
    "stop not skipped": lambda r: not r.get("stopSkipped"),
    "lap landed wrong": lambda r: not r.get("landedCorrect"),
}


def run_contributes(metric, a, b):
    """Whether one run, base `a` to branch `b`, moves a worse row metric."""
    if metric.startswith("unadmitted"):
        return b["unadmitted"] - a["unadmitted"] >= TIMING_TOLERANCE_S, f"{a['unadmitted']}->{b['unadmitted']}"
    if metric.startswith("false-recovery"):
        return b["falseRecovery"] - a["falseRecovery"] >= TIMING_TOLERANCE_S, f"{a['falseRecovery']}->{b['falseRecovery']}"
    if metric.startswith("detection latency"):
        moved = detected(a) and detected(b) and b["detectSeconds"] - a["detectSeconds"] >= TIMING_TOLERANCE_S
        return moved, f"{a['detectSeconds']}->{b['detectSeconds']}"
    flag = RUN_FLAGS[metric]
    return bool(flag(b)) and not flag(a), ""


def index(rows):
    return {run_key(r): r for r in rows}


def worse_rows(base, branch, counts_only=False):
    """[(row key, [(metric, 'a->b', [(run key, detail)])])] where the branch is worse."""
    rows = collections.defaultdict(list)
    for k in base:
        rows[k[:3]].append(k)
    result = []
    for row, keys in sorted(rows.items()):
        timing_a, counts_a = row_metrics([base[k] for k in keys], row[0])
        timing_b, counts_b = row_metrics([branch[k] for k in keys], row[0])
        worse = [] if counts_only else [
            (m, f"{timing_a[m]}->{timing_b[m]}") for m in timing_a
            if m in timing_b and timing_b[m] - timing_a[m] >= TIMING_TOLERANCE_S
        ]
        worse += [(m, f"{counts_a[m]}->{counts_b[m]}") for m in counts_a if counts_b[m] > counts_a[m]]
        if worse:
            detail = []
            for metric, change in worse:
                runs = [(k, s) for k in keys for moved, s in [run_contributes(metric, base[k], branch[k])] if moved]
                detail.append((metric, change, runs))
            result.append((row, detail))
    return result


def off_plan_advance_under2x(runs, keys):
    return sum(1 for k in keys if k[0] == "wrongBranch" and k[2] == "UNDER2X" and runs[k].get("offPlanCommits", 0) > 0)


def wrong73(runs, keys):
    return sum(1 for k in keys if runs[k]["wrong73"] > 0), sum(runs[k]["wrong73"] for k in keys)


def verdict(base, branch, counts_only=False):
    """The merge criteria over the runs both trees drove: (passed, [criterion lines], worse rows).

    A run is paired by group, route, profile, extra, movement, alternative and
    seed; a branch that moves the final divergence or changes its alternatives
    leaves runs unpaired, which fails criterion 4 until someone looks.
    """
    keys = [k for k in base if k in branch]
    unpaired = len(base) - len(keys), len(branch) - len(keys)
    base, branch = {k: base[k] for k in keys}, {k: branch[k] for k in keys}
    worse = worse_rows(base, branch, counts_only)
    gated = [w for w in worse if w[0][2] in GATED_PROFILES]
    r1 = off_plan_advance_under2x(base, keys), off_plan_advance_under2x(branch, keys)
    w73 = wrong73(base, keys), wrong73(branch, keys)
    criteria = [
        (not gated, f"URBAN/MULTIPATH rows worse than base: {len(gated)}"),
        (r1[1] <= r1[0], f"UNDER2X wrongBranch runs with off-plan progress: base {r1[0]} / branch {r1[1]}"),
        (w73[1][0] <= w73[0][0] and w73[1][1] <= w73[0][1],
         f"#73 wrong-commit runs, fixes: base {w73[0]} / branch {w73[1]}"),
        (unpaired == (0, 0), f"Runs without a counterpart: base {unpaired[0]} / branch {unpaired[1]}"),
    ]
    return all(ok for ok, _ in criteria), criteria, worse


def short(route):
    return route.replace("bundled:", "B:").replace("-product-release.json", "")


def run_label(k):
    extra = f"{k[3]} " if k[3] else ""
    movement = f"m={k[4]} " if k[4] != -1 and not k[3].startswith("m=") else ""
    return f"{extra}{movement}seed {k[6]}"


def headline(runs, group):
    h = collections.OrderedDict()
    h["runs"] = len(runs)
    h["completed"] = sum(1 for r in runs if r["completed"])
    h["early"] = sum(1 for r in runs if r["early"])
    h["incomplete (excl. handed over)"] = sum(1 for r in runs if not r["completed"] and not r.get("handover"))
    h["handed over"] = sum(1 for r in runs if r.get("handover"))
    h["completed on missed exit/branch"] = (
        sum(1 for r in runs if r["completed"] and not r.get("isPAEnding"))
        if group in ("missedFinal", "wrongBranch") else "")
    h["undetected"] = sum(1 for r in runs if not detected(r)) if group in DEVIATION_GROUPS else ""
    h["wrong73 runs"] = sum(1 for r in runs if r["wrong73"] > 0)
    h[f">{UNADMITTED_LINE_S} s unadmitted"] = sum(1 for r in runs if r["unadmitted"] > UNADMITTED_LINE_S)
    h[f">{FALSE_RECOVERY_LINE_S} s false recovery"] = sum(1 for r in runs if r["falseRecovery"] > FALSE_RECOVERY_LINE_S)
    return h


def comparable(row):
    return {k: v for k, v in row.items() if k != "wall"}


def markdown(title, header_lines, base, branch, counts_only=False, note=None):
    """The report body and whether the branch passes."""
    passed, criteria, worse = verdict(base, branch, counts_only)
    out = [f"# {title}", ""]
    out.append(f"**{'PASS' if passed else 'FAIL'}**" + (" (counts and contract lines only)" if counts_only else ""))
    out.append("")
    if note:
        out += [note, ""]
    out += header_lines
    paired = [k for k in base if k in branch]
    changed = sum(1 for k in paired if comparable(base[k]) != comparable(branch[k]))
    out.append(f"- Runs whose row differs from base (ignoring wall time): {changed} of {len(paired)}")
    out += ["", "## Merge criteria", ""]
    for i, (ok, line) in enumerate(criteria, 1):
        out.append(f"{i}. {line} — {'pass' if ok else 'FAIL'}")
    out += ["", f"Tolerance: timing metrics are worse at +{TIMING_TOLERANCE_S} s or more; counts, including runs over the "
            f"{UNADMITTED_LINE_S} s unadmitted and {FALSE_RECOVERY_LINE_S} s false-recovery contract lines, are worse "
            "at +1. URBAN/MULTIPATH rows gate the merge; UNDER2X rows are shown for information and gate through "
            "criteria 2 and 3."]
    for title_, profiles in (("URBAN / MULTIPATH", GATED_PROFILES), ("UNDER2X (information)", ("UNDER2X",))):
        selected = [w for w in worse if w[0][2] in profiles]
        out += ["", f"## Rows worse than base: {title_}: {len(selected)}", ""]
        for row, detail in selected:
            out.append(f"- **{row[0]} {short(row[1])} {row[2]}**")
            for metric, change, runs in detail:
                listed = ", ".join(f"{run_label(k)}{' ' + s if s else ''}" for k, s in runs)
                out.append(f"  - {metric} {change}: {listed or '(no single run moves by the tolerance; percentile shift)'}")
    out += ["", "## Headline counts per group and profile (base / branch)", ""]
    columns = None
    groups = sorted({k[0] for k in paired}, key=lambda g: ("planned", "lapChange", "stopBypass", "missedFinal",
                                                        "wrongBranch", "paReentry").index(g))
    for group in groups:
        for profile in ("URBAN", "MULTIPATH", "UNDER2X"):
            keys = [k for k in paired if k[0] == group and k[2] == profile]
            if not keys:
                continue
            a, b = headline([base[k] for k in keys], group), headline([branch[k] for k in keys], group)
            if columns is None:
                columns = list(a)
                out.append("| group | profile | " + " | ".join(columns) + " |")
                out.append("|" + "---|" * (2 + len(columns)))
            cells = [str(a[c]) if c == "runs" else ("" if a[c] == "" else f"{a[c]} / {b[c]}") for c in columns]
            out.append(f"| {group} | {profile} | " + " | ".join(cells) + " |")
    return "\n".join(out) + "\n", passed
