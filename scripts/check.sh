#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
swift run exchange-example
swift run --package-path Examples/LocalSyncSmoke SyncSmoke
python3 -m unittest discover -s scripts -p 'test_*.py'
for script in scripts/*.sh; do bash -n "$script"; done
python3 scripts/check-release.py "$(cat VERSION)" >/dev/null
