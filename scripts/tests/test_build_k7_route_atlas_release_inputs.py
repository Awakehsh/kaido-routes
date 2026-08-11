from __future__ import annotations

from datetime import date
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "build_k7_route_atlas_release_inputs.py"
sys.path.insert(0, str(SCRIPTS_DIR))
sys.path.insert(0, str(Path(__file__).parent))
from k7_readiness_test_fixture import SyntheticK7ReadinessRepository

SPEC = importlib.util.spec_from_file_location(
    "build_k7_route_atlas_release_inputs",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)

REPOSITORY_ROOT = Path(__file__).parents[2]
TOPOLOGY_TEMPLATE_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-topology-release-review.template.json"
)
LAYOUT_TEMPLATE_PATH = (
    REPOSITORY_ROOT / "data/route-atlas/candidates/"
    "k7-northwest-up-aoba-to-kohoku-layout-release-review.template.json"
)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def approved_reviews() -> tuple[dict, dict]:
    topology = load(TOPOLOGY_TEMPLATE_PATH)
    topology["assessed_at"] = "2026-07-27"
    topology["required_checks"]["independent_topology_review"] = "SATISFIED"
    topology["decision"] = {
        "status": "APPROVED",
        "reviewer_id": "topology-reviewer",
        "reviewer_role": "INDEPENDENT_TOPOLOGY_REVIEWER",
        "reviewed_at": "2026-07-27T10:00:00+09:00",
        "valid_through": "2026-08-26",
        "blocker_codes": [],
    }
    layout = load(LAYOUT_TEMPLATE_PATH)
    layout["assessed_at"] = "2026-07-27"
    layout["required_checks"]["topology_release_review"] = "SATISFIED"
    layout["required_checks"]["independent_layout_review"] = "SATISFIED"
    layout["decision"] = {
        "status": "APPROVED",
        "reviewer_id": "layout-reviewer",
        "reviewer_role": "INDEPENDENT_LAYOUT_REVIEWER",
        "reviewed_at": "2026-07-27T11:00:00+09:00",
        "valid_through": "2026-08-26",
        "blocker_codes": [],
    }
    return topology, layout


class BuildK7RouteAtlasReleaseInputsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory()
        cls.synthetic_repository = SyntheticK7ReadinessRepository(
            REPOSITORY_ROOT,
            Path(cls.temporary_directory.name),
            builder.readiness_validator,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_builds_exact_projection_and_review_dated_released_evidence(self) -> None:
        candidate = load(builder.CANDIDATE_PATH)
        topology, layout = approved_reviews()

        draft, authoring = builder.build_inputs(
            candidate,
            topology,
            layout,
            date(2026, 7, 27),
            self.synthetic_repository.root,
        )

        self.assertNotIn("evidence", draft["topology_slice"])
        self.assertNotIn("evidence", draft["definition"])
        self.assertNotIn("source_registry", draft)
        self.assertEqual(authoring["source_registry"], candidate["source_registry"])
        self.assertEqual(authoring["topology_evidence"]["state"], "RELEASED")
        self.assertEqual(authoring["topology_evidence"]["checked_at"], "2026-07-27")
        self.assertEqual(authoring["layout_evidence"]["state"], "RELEASED")
        self.assertEqual(authoring["layout_evidence"]["checked_at"], "2026-07-27")
        self.assertEqual(
            candidate["topology_slice"]["evidence"]["state"],
            "CANDIDATE",
        )
        self.assertEqual(candidate["definition"]["evidence"]["state"], "CANDIDATE")

    def test_rejects_same_reviewer(self) -> None:
        topology, layout = approved_reviews()
        layout["decision"]["reviewer_id"] = topology["decision"]["reviewer_id"]

        with self.assertRaisesRegex(
            builder.readiness_validator.ReadinessError,
            "require different reviewers",
        ):
            builder.build_inputs(
                load(builder.CANDIDATE_PATH),
                topology,
                layout,
                date(2026, 7, 27),
                self.synthetic_repository.root,
            )

    def test_rejects_expired_review(self) -> None:
        topology, layout = approved_reviews()

        with self.assertRaisesRegex(
            builder.ReleaseInputError,
            "not current",
        ):
            builder.build_inputs(
                load(builder.CANDIDATE_PATH),
                topology,
                layout,
                date(2026, 8, 27),
                self.synthetic_repository.root,
            )

    def test_rejects_layout_review_before_topology_approval(self) -> None:
        topology, layout = approved_reviews()
        layout["decision"]["reviewed_at"] = "2026-07-27T09:59:59+09:00"

        with self.assertRaisesRegex(
            builder.readiness_validator.ReadinessError,
            "predates topology approval",
        ):
            builder.build_inputs(
                load(builder.CANDIDATE_PATH),
                topology,
                layout,
                date(2026, 7, 27),
                self.synthetic_repository.root,
            )

    def test_write_refuses_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            draft = Path(directory) / "draft.json"
            config = Path(directory) / "config.json"
            draft.write_text("{}\n", encoding="utf-8")

            with self.assertRaisesRegex(
                builder.ReleaseInputError,
                "already exists",
            ):
                builder.write_inputs(draft, config, date(2026, 7, 27))


if __name__ == "__main__":
    unittest.main()
