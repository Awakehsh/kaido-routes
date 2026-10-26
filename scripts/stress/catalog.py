"""The navigation stress cells, their tags, and selection.

A cell is (group, route, profile, extra); a unit is a cell at one seed. The
catalog lists every cell the harness can drive. Cells tagged `default` are what
a comparison runs unless `--select` says otherwise.
"""

import itertools
from pathlib import Path

GROUPS = ("planned", "missedFinal", "wrongBranch", "stopBypass", "lapChange", "paReentry")
PROFILES = ("URBAN", "MULTIPATH", "UNDER2X")
LOOPS = ("c1-inner", "c1-outer", "c2", "daikoku", "stop")
# Loops entered from a radial route, ending at that route's exit.
RADIAL_LOOPS = ("c1-inner-s1", "c1-outer-s1", "c2-s1", "c1-inner-r4", "c1-outer-r4")
LAP_COUNTS = (1, 2, 3)
BUNDLED = {
    "c1-inner-shibakoen-to-shiodome-product-release.json": "c1-inner",
    "c2-inner-oujiminami-itabashihoncho-product-release.json": "c2",
    "wangan-westbound-chidoricho-daikoku-pa-product-release.json": "wangan",
    "daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json": "daikoku",
    "scenic-harumi-daikoku-pa-product-release.json": "scenic",
}
BUNDLED_PA_ENDINGS = ("wangan-", "daikoku-", "scenic-")
# The bundled releases' reviewed divergent junctions.
BUNDLED_WRONG_BRANCHES = {
    "c1-inner-shibakoen-to-shiodome-product-release.json": ("m=283", "m=487"),
    "c2-inner-oujiminami-itabashihoncho-product-release.json": ("m=234",),
    "wangan-westbound-chidoricho-daikoku-pa-product-release.json": ("m=130",),
}
# The same junction pairs in a runtime loop.
LOOP_WRONG_BRANCH_PAIRS = {"c1-inner": ("pair=283", "pair=487"), "c2": ("pair=234",)}
LAP_CHANGES = ("stop:drop", "stop:finish", "endPA:finish")
# Forks whose untaken road runs beside the plan, where a wrong branch looks like
# the plan until the roads part; see the file's header. Each drive stops 2.5 km
# past its fork: 1,500 fixes on average.
BESIDE_FORKS = Path(__file__).with_name("beside-forks.tsv")
BESIDE_FORK_FIXES = 1500

# Approximate fixes per drive, the scheduling cost: the longest drives start
# first so no core idles behind one long drive at the end. A missing route
# sorts first.
FIXES = {
    "loop:c2-s1:3": 12500, "loop:c2-s1:2": 9700, "loop:c2:3": 7100, "loop:c2-s1:1": 6800,
    "loop:stop:3": 6600, "loop:daikoku:3": 5700, "loop:c1-inner-s1:3": 5300,
    "loop:c1-outer-s1:3": 5300, "loop:stop:2": 5000, "lapchange:stop:drop": 5000,
    "loop:c2:2": 4900, "loop:c1-inner-s1:2": 4600, "loop:c1-outer-s1:2": 4600,
    "loop:daikoku:2": 4100, "loop:c1-inner-s1:1": 3900, "loop:c1-outer-s1:1": 3900,
    "lapchange:stop:finish": 3400, "loop:stop:1": 3300, "loop:c1-inner-r4:3": 3300,
    "loop:c1-outer-r4:3": 3300, "loop:c1-inner-r4:2": 2600, "loop:c1-outer-r4:2": 2600,
    "loop:daikoku:1": 2500, "lapchange:endPA:finish": 2500, "loop:c2:1": 2400,
    "loop:c1-outer:3": 2400, "loop:c1-inner:3": 1900, "loop:c1-inner-r4:1": 1900,
    "loop:c1-outer-r4:1": 1900, "loop:c1-outer:2": 1700, "loop:c1-inner:2": 1400,
    "loop:c1-outer:1": 1000, "loop:c1-inner:1": 800,
    "bundled:c2-inner-oujiminami-itabashihoncho-product-release.json": 2400,
    "bundled:daikoku-yokohama-wangankanpachi-daikoku-pa-product-release.json": 2500,
    "bundled:scenic-harumi-daikoku-pa-product-release.json": 2200,
    "bundled:wangan-westbound-chidoricho-daikoku-pa-product-release.json": 1900,
    "bundled:c1-inner-shibakoen-to-shiodome-product-release.json": 800,
}


def _loop_cells(loop, laps):
    route = f"loop:{loop}:{laps}"
    family = ["loop", loop, f"laps{laps}"] + (["radial"] if loop in RADIAL_LOOPS else [])
    if loop == "daikoku":
        family.append("pa-end")
    # Final-lap logic needs one and two laps; a third lap only repeats them.
    default = laps <= 2
    yield "planned", route, "", family, default
    yield "missedFinal", route, "", family, default
    if loop == "stop":
        yield "stopBypass", route, "", family, default
        if laps >= 2:
            yield "paReentry", route, "", family, default
    for pair in LOOP_WRONG_BRANCH_PAIRS.get(loop, ()):
        if laps >= 2:
            # On two laps, lap 2 is the last lap: the same drives as lap=last.
            # Only a third lap has a later lap that is not the last.
            later = laps >= 3
            yield "wrongBranch", route, f"{pair},lap=2", family + (["later-lap"] if later else []), later
        yield "wrongBranch", route, f"{pair},lap=last", family, default


def _route_cells():
    for laps in LAP_COUNTS:
        for loop in LOOPS + RADIAL_LOOPS:
            yield from _loop_cells(loop, laps)
    for file, name in BUNDLED.items():
        route = f"bundled:{file}"
        family = ["bundled", f"bundled:{name}"] + (["pa-end"] if file.startswith(BUNDLED_PA_ENDINGS) else [])
        yield "planned", route, "", family, True
        yield "missedFinal", route, "", family, True
        for spec in BUNDLED_WRONG_BRANCHES.get(file, ()):
            yield "wrongBranch", route, spec, family, True
    for line in BESIDE_FORKS.read_text().splitlines():
        if line.startswith("#"):
            continue
        route, incoming, planned, untaken, _, where = line.split("\t")[:6]
        yield "wrongBranch", route, f"fork={incoming}/{planned}/{untaken}", ["beside-fork", f"beside-fork:{where}"], False
    for spec in LAP_CHANGES:
        # The lap-change fixtures are three-lap drives by construction.
        yield "lapChange", f"lapchange:{spec}", spec, ["lapchange"] + (["pa-end"] if "PA" in spec else []), True


def _via_cells(routes_file):
    """Planned and missed-final cells for `via:` routes listed one per line (first column)."""
    for line in open(routes_file):
        route = line.split("\t")[0].strip()
        if not route or route.startswith("#"):
            continue
        _, circuit, _, exit_id, laps = route.split(":")
        family = ["via", "sweep", f"via:{circuit}", f"laps{laps}"] + (["pa-end"] if exit_id == "-" else [])
        yield "planned", route, "", family, False
        yield "missedFinal", route, "", family, False


def cells(routes_file=None):
    """Every cell with its tags, in a stable order."""
    result = []
    extra_cells = _via_cells(routes_file) if routes_file else ()
    for group, route, extra, family, default in itertools.chain(_route_cells(), extra_cells):
        for profile in PROFILES:
            tags = {group, profile, route, *family}
            if default:
                tags.add("default")
            result.append({"group": group, "route": route, "profile": profile, "extra": extra, "tags": tags})
    return result


def select(expression, routes_file=None):
    """Cells matching a selection.

    Comma-separated terms. A term is one or more tags joined by `+` (a cell
    must carry all of them); a term starting with `-` removes the cells it
    matches from the union of the others. `all` matches every cell.
    """
    include, exclude = [], []
    for term in filter(None, (t.strip() for t in expression.split(","))):
        target = exclude if term.startswith("-") else include
        target.append(set(term.lstrip("-").split("+")) - {"all"})
    universe = cells(routes_file)
    known = set().union(*(c["tags"] for c in universe)) | {"all"}
    unknown = set().union(*include, *exclude) - known
    if unknown:
        raise ValueError(f"unknown tags: {', '.join(sorted(unknown))}")
    return [
        c for c in universe
        if any(t <= c["tags"] for t in include) and not any(t <= c["tags"] for t in exclude)
    ]


def cost(unit):
    if unit[0] == "wrongBranch" and unit[3].startswith("fork="):
        return BESIDE_FORK_FIXES
    return FIXES.get(unit[1], max(FIXES.values()) + 1)
