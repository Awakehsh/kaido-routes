from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
MODULE_PATH = SCRIPTS_DIR / "prepare_k7_road_register_review.py"
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location(
    "prepare_k7_road_register_review",
    MODULE_PATH,
)
assert SPEC and SPEC.loader
preparer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(preparer)

REPOSITORY_ROOT = Path(__file__).parents[2]


class PrepareK7RoadRegisterReviewTests(unittest.TestCase):
    def test_private_manifest_is_exact_template_and_never_overwritten(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "k7-kohoku-road-register-review.json"

            digest = preparer.prepare(output)

            self.assertTrue(output.is_file())
            self.assertEqual(
                output.read_bytes(),
                preparer.TRACKED_TEMPLATE_PATH.read_bytes(),
            )
            self.assertEqual(
                json.loads(output.read_text(encoding="utf-8"))["schema_version"],
                "1.0",
            )
            self.assertEqual(len(digest), 64)
            with self.assertRaisesRegex(
                preparer.RoadRegisterReviewError,
                "already exists",
            ):
                preparer.prepare(output)

    def test_tracked_or_nonignored_repository_output_is_rejected(
        self,
    ) -> None:
        with self.assertRaisesRegex(
            preparer.RoadRegisterReviewError,
            "template is immutable",
        ):
            preparer.prepare(preparer.TRACKED_TEMPLATE_PATH)

        with self.assertRaisesRegex(
            preparer.RoadRegisterReviewError,
            "must stay under ignored research",
        ):
            preparer.prepare(REPOSITORY_ROOT / "data/road-register-review.json")


if __name__ == "__main__":
    unittest.main()
