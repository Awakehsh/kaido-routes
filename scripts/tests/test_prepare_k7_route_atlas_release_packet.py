from __future__ import annotations

from datetime import date
import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "prepare_k7_route_atlas_release_packet.py"
sys.path.insert(0, str(SCRIPTS_DIR))
sys.path.insert(0, str(Path(__file__).parent))
from k7_readiness_test_fixture import SyntheticK7ReadinessRepository

SPEC = importlib.util.spec_from_file_location(
    "prepare_k7_route_atlas_release_packet",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
preparer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(preparer)

REPOSITORY_ROOT = Path(__file__).parents[2]


class PrepareK7RouteAtlasReleasePacketTests(unittest.TestCase):
    def test_packet_derives_exact_fail_closed_authoring_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            synthetic = SyntheticK7ReadinessRepository(
                REPOSITORY_ROOT,
                temporary_root / "repository",
                preparer.readiness_validator,
            )
            source_paths = (
                preparer.CANDIDATE_PATH,
                preparer.TOPOLOGY_REVIEW_PATH,
                preparer.LAYOUT_REVIEW_PATH,
                preparer.SCHEMATIC_SVG_PATH,
            )
            synthetic_paths = []
            for source in source_paths:
                destination = synthetic.root / source.relative_to(REPOSITORY_ROOT)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
                synthetic_paths.append(destination)
            output = temporary_root / "k7-atlas-review"

            with mock.patch.multiple(
                preparer,
                REPOSITORY_ROOT=synthetic.root,
                READINESS_PATH=synthetic.readiness_path,
                CANDIDATE_PATH=synthetic_paths[0],
                TOPOLOGY_REVIEW_PATH=synthetic_paths[1],
                LAYOUT_REVIEW_PATH=synthetic_paths[2],
                SCHEMATIC_SVG_PATH=synthetic_paths[3],
            ):
                manifest = preparer.prepare(output, date(2026, 7, 28))

            self.assertEqual(
                {path.name for path in output.iterdir()},
                preparer.EXPECTED_PACKET_FILES,
            )
            self.assertFalse(manifest["navigation_authority"])
            self.assertFalse(manifest["candidate_ready_for_release_validation"])
            self.assertEqual(
                manifest["expected_blocker_codes"],
                preparer.EXPECTED_BLOCKERS,
            )
            authoring = json.loads(
                (output / "route-atlas-release-authoring.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(authoring["topology_evidence"]["state"], "CANDIDATE")
            self.assertEqual(authoring["layout_evidence"]["state"], "CANDIDATE")
            draft = json.loads(
                (output / "route-atlas-release-draft.json").read_text(encoding="utf-8")
            )
            self.assertNotIn("evidence", draft["topology_slice"])
            self.assertNotIn("evidence", draft["definition"])
            self.assertNotIn("source_registry", draft)
            with self.assertRaisesRegex(
                preparer.ReleasePacketError,
                "already exists",
            ):
                preparer.prepare(output, date(2026, 7, 28))

    def test_nonignored_repository_output_is_rejected(self) -> None:
        with self.assertRaisesRegex(
            preparer.ReleasePacketError,
            "must stay under ignored research",
        ):
            preparer.prepare(
                REPOSITORY_ROOT / "artifacts/k7-atlas-review",
                date(2026, 7, 28),
            )

    def test_ready_tracked_release_does_not_block_candidate_packet(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "k7-atlas-review"
            with mock.patch.object(
                preparer.readiness_validator,
                "evaluate",
                return_value={
                    "status": "READY_FOR_RELEASE_VALIDATION",
                    "candidate_ready_for_release_validation": True,
                    "blocker_codes": [],
                    "navigation_authority": False,
                },
            ):
                manifest = preparer.prepare(output, date(2026, 7, 28))

            self.assertFalse(manifest["candidate_ready_for_release_validation"])
            self.assertEqual(
                manifest["expected_blocker_codes"],
                preparer.EXPECTED_BLOCKERS,
            )
            authoring = json.loads(
                (output / "route-atlas-release-authoring.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(authoring["topology_evidence"]["state"], "CANDIDATE")
            self.assertEqual(authoring["layout_evidence"]["state"], "CANDIDATE")

    def test_candidate_promotion_is_rejected(self) -> None:
        candidate = preparer.load_object(preparer.CANDIDATE_PATH)
        candidate["topology_slice"]["evidence"]["state"] = "RELEASED"

        with self.assertRaisesRegex(
            preparer.ReleasePacketError,
            "cannot promote",
        ):
            preparer.validate_candidate(candidate)


if __name__ == "__main__":
    unittest.main()
