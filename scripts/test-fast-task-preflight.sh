#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PI_FAST_PREFLIGHT_ONLY=1 ./scripts/test-fast-task-dispatch.sh
