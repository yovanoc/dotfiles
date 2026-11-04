#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ${1:-} == --runtime && $# -eq 1 ]]; then
  if [[ -z ${PI_RUNTIME:-} ]]; then
    command -v brew >/dev/null || { echo 'Set PI_RUNTIME to the Pi package root for --runtime' >&2; exit 1; }
    PI_RUNTIME="$(brew --prefix pi-coding-agent)/libexec/lib/node_modules/@earendil-works/pi-coding-agent"
  fi
  set -- --runtime "$PI_RUNTIME"
fi
node scripts/test-pi-quota-status.mjs "$@"
node home/private_dot_pi/private_agent/private_extensions/quota-status/credits.test.mjs "$@"
node home/private_dot_pi/private_agent/private_extensions/quota-status/cache.test.mjs
