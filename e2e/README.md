# Portable E2E scenarios

This directory stores implementation-independent product scenarios.

```text
e2e/
├── schema/scenario.schema.json
└── scenarios/*.json
```

The JSON Schema documents the envelope. The dependency-free validator also
checks cross-field rules that are awkward to express in JSON Schema, including
contiguous occurrence indexes, unique event IDs, event ordering, and assertion
references.

Run:

```sh
python3 scripts/validate_e2e.py
```

Scenario IDs are stable. File names may add descriptive words, but changing a
scenario's behavior should retain its ID or create a new version intentionally.

Real operator data is allowed only as a small, dated evidence fixture with
direct source links. All other road IDs must be visibly synthetic.

