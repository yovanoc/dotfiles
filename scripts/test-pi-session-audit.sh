#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/pi-session-audit.sh"
command -v jq >/dev/null || { echo 'test requires jq' >&2; exit 1; }
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/pi-session-audit-test.XXXXXX")
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$tmp_root"
  if [[ -e $tmp_root ]]; then
    echo "temporary test data remains: $tmp_root" >&2
    exit 1
  fi
  exit "$status"
}
trap cleanup EXIT

root="$tmp_root/sessions"
mkdir -p "$root"
main="$root/old-main.jsonl"
cat > "$main" <<'EOF'
{"type":"session","id":"main","timestamp":"2024-05-02T11:00:00-04:00"}
{"type":"message","timestamp":"2024-05-02T11:59:59-04:00","message":{"role":"assistant","content":[{"type":"toolCall","id":"old-dispatch","name":"Agent","arguments":{"max_turns":99,"prompt":"OLD_PROMPT_SECRET"}}]}}
{"type":"message","timestamp":"2024-05-02T12:30:00-04:00","message":{"role":"assistant","content":[{"type":"text","text":"PROMPT_SECRET"},{"type":"toolCall","id":"dispatch","name":"Agent","arguments":{"max_turns":7,"model":"fixture-model","thinking":"high","run_in_background":false,"resume":"WORKER_ID_SECRET","prompt":"PROMPT_SECRET","description":"TOOL_ARGUMENT_SECRET"}}]}}
{"type":"custom_message","customType":"subagent-notification","id":"note-a","timestamp":"2024-05-02T12:30:00-04:00","content":"<task-id>WORKER_ID_SECRET</task-id><status>done</status>"}
{"type":"custom_message","customType":"subagent-notification","id":"note-b","timestamp":"2024-05-02T12:30:00-04:00","content":"<task-id>WORKER_ID_SECRET</task-id><status>done</status>"}
{"type":"message","timestamp":"2024-05-02T12:30:00-04:00","message":{"role":"assistant","content":[{"type":"toolCall","id":"get-1","name":"get_subagent_result","arguments":{"agent_id":"WORKER_ID_SECRET"}}]}}
{"type":"message","timestamp":"2024-05-02T12:30:00-04:00","message":{"role":"toolResult","content":[{"type":"text","text":"Agent not found: WORKER_ID_SECRET"}],"toolName":"get_subagent_result","toolCallId":"get-1"}}
{"type":"message","timestamp":"2024-05-02T12:30:00-04:00","message":{"role":"assistant","content":[{"type":"toolCall","id":"get-2","name":"get_subagent_result","arguments":{"agent_id":"WORKER_ID_SECRET"}}]}}
{"type":"message","timestamp":"2024-05-02T12:30:00-04:00","message":{"role":"toolResult","content":[{"type":"text","text":"Agent not found: WORKER_ID_SECRET"}],"toolName":"get_subagent_result","toolCallId":"get-2"}}
EOF
printf '{"truncated":\n' >> "$main"
touch -t 202405031200 "$main"
# Append-only files last modified before --since cannot hold in-window events; they are skipped unread.
jq -nc '{type:"session",id:"stale",timestamp:"2024-05-02T12:00:00-04:00"}' > "$root/stale.jsonl"
touch -t 202405011200 "$root/stale.jsonl"

jq -nc --arg parent "$main" '{type:"session",id:"worker",timestamp:"2024-05-02T12:01:00-04:00",parentSession:$parent}' > "$root/worker.jsonl"
jq -nc '{type:"session_info",timestamp:"2024-05-02T12:01:01-04:00",name:"general-purpose#WORKER01",parentId:"PARENT_ID_SECRET"}' >> "$root/worker.jsonl"
jq -nc '{type:"message",timestamp:"2024-05-02T12:02:00-04:00",message:{role:"assistant",content:[{type:"toolCall",id:"bash-short",name:"bash",arguments:{timeout:30,command:"TOOL_ARGUMENT_SECRET"}}]}}' >> "$root/worker.jsonl"
jq -nc '{type:"message",timestamp:"2024-05-02T12:03:00-04:00",message:{role:"assistant",content:[{type:"toolCall",id:"bash-long",name:"bash",arguments:{timeout:3601,command:"LONG_WORKER_SECRET"}}]}}' >> "$root/worker.jsonl"
jq -nc '{type:"message",timestamp:"2024-05-02T12:04:00-04:00",message:{role:"assistant",content:[{type:"toolCall",id:"bash-no-timeout",name:"bash",arguments:{command:"NO_WORKER_TIMEOUT_SECRET"}}]}}' >> "$root/worker.jsonl"

jq -nc --arg parent "$main" '{type:"session",id:"fork",timestamp:"2024-05-02T12:00:00-04:00",parentSession:$parent}' > "$root/fork.jsonl"
jq -nc '{type:"message",timestamp:"2024-05-02T12:30:00-04:00",message:{role:"assistant",content:[{type:"toolCall",id:"bash-fork",name:"bash",arguments:{timeout:999,command:"FORK_ARGUMENT_SECRET"}}]}}' >> "$root/fork.jsonl"
jq -nc '{type:"session",id:"new",timestamp:"2024-05-02T12:00:00-04:00"}' > "$root/new-main.jsonl"
jq -nc '{type:"session",id:"named-main",timestamp:"2024-05-02T12:00:00-04:00"}' > "$root/named-main.jsonl"
jq -nc '{type:"session_info",timestamp:"2024-05-02T12:00:00-04:00",name:"coordinator",parentId:"PARENT_ID_SECRET"}' >> "$root/named-main.jsonl"
jq -nc '{type:"message",timestamp:"2024-05-02T12:30:00-04:00",message:{role:"assistant",content:[{type:"toolCall",id:"coord-long",name:"bash",arguments:{timeout:120000,command:"COORD_ARGUMENT_SECRET"}}]}}' >> "$root/named-main.jsonl"
jq -nc '{type:"message",timestamp:"2024-05-02T12:30:00-04:00",message:{role:"assistant",content:[{type:"toolCall",id:"coord-no-timeout",name:"bash",arguments:{command:"NO_TIMEOUT_SECRET"}}]}}' >> "$root/named-main.jsonl"

TZ=America/New_York "$SCRIPT" --sessions-dir "$root" --since '2024-05-02T12:00:00-04:00' --json > "$tmp_root/report.json"
jq -e '
  .window_start_local == "2024-05-02T12:00:00-04:00"
  and .main_sessions == {created_within_window:2,older_with_activity:1}
  and .fork_sessions == {created_within_window:1}
  and .workers.sessions == 1 and .workers.types == {"general-purpose":1}
  and .workers.max_concurrency_observed_span_upper_bound == 1
  and .limitations == [
    "Counts direct tool calls only; nested codemode calls are uncounted. Files last modified before --since are skipped.",
    "Worker overlap is a first/last logged-span proxy, not actual execution concurrency or a guaranteed lifecycle upper bound."
  ]
  and .bash_timeouts.workers == {calls:3,timeout_argument_present:2,timeout_over_3600s:1,by_value:{"30":1,"3601":1,not_set:1}}
  and .bash_timeouts.nonworker_coordinators == {calls:3,timeout_argument_present:2,timeout_over_3600s:1,by_value:{"120000":1,"999":1,not_set:1}}
  and .agent_dispatches.max_turns == {"7":1}
  and .agent_dispatches.model == {"fixture-model":1}
  and .agent_dispatches.thinking == {high:1}
  and .agent_dispatches.background == {false:1}
  and .agent_dispatches.resume == {resumed:1}
  and .terminal_notification_statuses_unique == {done:1}
  and .get_subagent_result == {attempts:2,results:2,misses:2,unique_missed_targets:1,duplicate_misses:1}
  and .scan.files == 5 and .scan.malformed_lines == 1 and .scan.unreadable_files == 0
' "$tmp_root/report.json" >/dev/null

# A naive local cutoff must select the same events as the equivalent explicit offset.
TZ=America/New_York "$SCRIPT" --sessions-dir "$root" --since '2024-05-02T12:00:00' --json > "$tmp_root/naive.json"
jq -e --slurpfile expected "$tmp_root/report.json" '. == $expected[0]' "$tmp_root/naive.json" >/dev/null
TZ=America/New_York "$SCRIPT" --sessions-dir "$root" --since '2024-05-02T12:00:00-04' --json > "$tmp_root/hour-offset.json"
jq -e --slurpfile expected "$tmp_root/report.json" '. == $expected[0]' "$tmp_root/hour-offset.json" >/dev/null
TZ=America/New_York "$SCRIPT" --sessions-dir "$root" --since '2024-11-03T01:30:00' --json > "$tmp_root/fall-back.json"
jq -e '.window_start_local == "2024-11-03T01:30:00-04:00"' "$tmp_root/fall-back.json" >/dev/null
TZ=America/New_York "$SCRIPT" --sessions-dir "$root" --since '2024-03-10T02:30:00' --json > "$tmp_root/spring-gap.json"
jq -e '.window_start_local == "2024-03-10T03:30:00-04:00"' "$tmp_root/spring-gap.json" >/dev/null
if "$SCRIPT" --sessions-dir "$root" --since '2024-05-02T12:30Z' --json > "$tmp_root/unsupported.out" 2> "$tmp_root/unsupported.err"; then
  echo 'unsupported timestamp unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'invalid --since timestamp' "$tmp_root/unsupported.err"

# The plain-text interface remains metadata-only.
TZ=America/New_York "$SCRIPT" --sessions-dir "$root" --since '2024-05-02T12:00:00-04:00' > "$tmp_root/plain.txt"
grep -q 'Main sessions: 1 older, 2 created in window' "$tmp_root/plain.txt"
grep -Fq 'Observed worker-span overlap proxy:' "$tmp_root/plain.txt"
grep -Fq 'Limitations: Counts direct tool calls only; nested codemode calls are uncounted. Files last modified before --since are skipped.' "$tmp_root/plain.txt"
grep -Fq 'Worker overlap is a first/last logged-span proxy, not actual execution concurrency or a guaranteed lifecycle upper bound.' "$tmp_root/plain.txt"
if grep -E 'PROMPT_SECRET|OLD_PROMPT_SECRET|TOOL_ARGUMENT_SECRET|FORK_ARGUMENT_SECRET|WORKER_ID_SECRET|WORKER01|PARENT_ID_SECRET|COORD_ARGUMENT_SECRET|NO_TIMEOUT_SECRET|NO_WORKER_TIMEOUT_SECRET|LONG_WORKER_SECRET' "$tmp_root/report.json" "$tmp_root/naive.json" "$tmp_root/plain.txt"; then
  echo 'audit output leaked fixture content' >&2
  exit 1
fi

# Exercise the default last-48-hour window with a current event.
default_root="$tmp_root/default-sessions"
mkdir -p "$default_root"
now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
jq -nc --arg now "$now" '{type:"session",timestamp:$now}' > "$default_root/current.jsonl"
"$SCRIPT" --sessions-dir "$default_root" --json > "$tmp_root/default.json"
jq -e '.main_sessions == {created_within_window:1} and .scan.files == 1' "$tmp_root/default.json" >/dev/null

"$SCRIPT" --help > "$tmp_root/help.txt"
grep -q 'last 48 hours' "$tmp_root/help.txt"
if "$SCRIPT" --sessions-dir "$tmp_root/does-not-exist" > "$tmp_root/missing.out" 2> "$tmp_root/missing.err"; then
  echo 'missing directory unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'sessions directory does not exist or is not a directory' "$tmp_root/missing.err"

# Keep only the utilities needed before jq detection on PATH to verify its diagnostic.
no_jq_path="$tmp_root/no-jq-bin"
mkdir -p "$no_jq_path"
for utility in dirname find date; do
  utility_path=$(command -v "$utility")
  ln -s "$utility_path" "$no_jq_path/$utility"
done
if PATH="$no_jq_path" /bin/bash "$SCRIPT" --sessions-dir "$root" > "$tmp_root/no-jq.out" 2> "$tmp_root/no-jq.err"; then
  echo 'missing jq unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'jq is required' "$tmp_root/no-jq.err"

echo 'pi-session-audit tests passed'
