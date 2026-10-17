#!/bin/sh
# Compare a branch against a base ref under the navigation stress harness.
# Usage: scripts/stress/compare.sh <base-ref> <branch-ref> [--select EXPR] [--seeds 1-40] [--all-stages]
exec python3 "$(dirname "$0")/stress.py" compare "$@"
