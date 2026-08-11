from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
from typing import Any


def _encoded_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class SyntheticK7ReadinessRepository:
    """Isolated positive-path fixture for the historical K7 validator.

    Production evidence remains immutable and is allowed to report drift as the
    current App evolves. This fixture copies the reviewed inputs, binds a
    synthetic distribution review to the temporary bytes, and changes no
    tracked evidence.
    """

    def __init__(self, source_root: Path, root: Path, validator: Any) -> None:
        self.source_root = source_root.resolve()
        self.root = root.resolve()
        self.validator = validator
        self.readiness_relative_path = (
            "data/route-atlas/candidates/"
            "k7-northwest-up-aoba-to-kohoku-release-readiness.json"
        )
        self.distribution_review_relative_path = validator.EXPECTED_BINDING_PATHS[
            "ODBL_DISTRIBUTION_REVIEW"
        ]
        self._materialize()

    @property
    def readiness_path(self) -> Path:
        return self.root / self.readiness_relative_path

    @property
    def distribution_review_path(self) -> Path:
        return self.root / self.distribution_review_relative_path

    def _materialize(self) -> None:
        paths = set(self.validator.EXPECTED_BINDING_PATHS.values())
        paths.update(self.validator.EXPECTED_DISTRIBUTION_BINDING_PATHS.values())
        paths.update(
            binding["repository_path"]
            for binding in self.validator.EXPECTED_TOPOLOGY_REVIEW_BINDINGS.values()
        )
        paths.update(
            binding["repository_path"]
            for binding in self.validator.EXPECTED_LAYOUT_REVIEW_BINDINGS.values()
        )
        paths.add(self.readiness_relative_path)

        for relative_path in sorted(paths):
            source = self.source_root / relative_path
            destination = self.root / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

        self._restore_reviewed_catalog_shape()
        self._write_synthetic_distribution_review()
        self._bind_synthetic_distribution_review()

    def _restore_reviewed_catalog_shape(self) -> None:
        relative_path = self.validator.EXPECTED_DISTRIBUTION_BINDING_PATHS[
            "ATTRIBUTION_CATALOG"
        ]
        path = self.root / relative_path
        catalog = json.loads(path.read_text(encoding="utf-8"))
        catalog["catalog_id"] = "kaido.route-atlas-attribution.2026-07-24"
        catalog["entries"] = [
            entry
            for entry in catalog["entries"]
            if entry.get("mode_id") != "wholeShuto"
        ]
        path.write_bytes(_encoded_json(catalog))
        expected = self.validator.EXPECTED_LAYOUT_REVIEW_BINDINGS[
            "ATTRIBUTION_CATALOG"
        ]["content_sha256"]
        if _sha256(path) != expected:
            raise AssertionError("synthetic historical catalog bytes drifted")

    def _write_synthetic_distribution_review(self) -> None:
        review = json.loads(
            self.distribution_review_path.read_text(encoding="utf-8")
        )
        review["reviewed_by"] = "Synthetic validator fixture"
        for binding in review["artifact_bindings"]:
            binding["content_sha256"] = _sha256(
                self.root / binding["repository_path"]
            )
        self.distribution_review_path.write_bytes(_encoded_json(review))

    def _bind_synthetic_distribution_review(self) -> None:
        readiness = json.loads(self.readiness_path.read_text(encoding="utf-8"))
        binding = next(
            item
            for item in readiness["artifact_bindings"]
            if item["role"] == "ODBL_DISTRIBUTION_REVIEW"
        )
        binding["content_sha256"] = _sha256(self.distribution_review_path)
        self.readiness_path.write_bytes(_encoded_json(readiness))
