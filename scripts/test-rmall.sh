#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'chmod -R u+w "$fixture"; rm -rf "$fixture"' EXIT
mkdir -p "$fixture/work/project with spaces/node_modules/.cache/go/module/baselines"
mkdir -p "$fixture/work/.hidden/node_modules" "$fixture/outside"
printf keep > "$fixture/outside/keep"
chmod 444 "$fixture/outside/keep"
ln -s "$fixture/outside" "$fixture/work/project with spaces/node_modules/external"
touch "$fixture/work/project with spaces/node_modules/.cache/go/module/baselines/file.js"
chmod -R a-w "$fixture/work/project with spaces/node_modules/.cache/go"
for artifact in .next dist .turbo target; do
    mkdir -p "$fixture/work/project with spaces/$artifact"
done
touch "$fixture/work/project with spaces/.DS_Store" "$fixture/work/project with spaces/tsconfig.tsbuildinfo"
touch "$fixture/work/project with spaces/keep"
(cd "$fixture/work" && zsh -f -c 'source "$1"; rmall' zsh "$repo/home/dot_config/zsh/functions.zsh") 2> "$fixture/errors" || { head -n 5 "$fixture/errors" >&2; exit 1; }
if [[ -s "$fixture/errors" ]]; then
    printf "rmall emitted deletion errors:\n" >&2
    head -n 5 "$fixture/errors" >&2
    exit 1
fi
for artifact in node_modules .next dist .turbo target .DS_Store tsconfig.tsbuildinfo; do
    [[ ! -e "$fixture/work/project with spaces/$artifact" ]]
done
[[ -f "$fixture/work/project with spaces/keep" ]]
[[ -d "$fixture/work/.hidden/node_modules" ]]
[[ -f "$fixture/outside/keep" && ! -w "$fixture/outside/keep" ]]
echo 'rmall regression tests passed'
