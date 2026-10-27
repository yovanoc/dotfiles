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
  and .limitations[0:3] == [
    "Counts direct tool calls only; nested codemode calls are uncounted. Files last modified before --since are skipped.",
    "Worker overlap is a first/last logged-span proxy, not actual execution concurrency or a guaranteed lifecycle upper bound.",
    "Terminal statuses come from notifications logged in the parent session, so they are counted per unique notification, not attributed to individual worker sessions or models. Model metrics count assistant messages; missing usage fields count as 0."
  ]
  and .window_end_local == null
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

# --until and per-model metrics use their own fixtures.
mroot="$tmp_root/model-sessions"
mkdir -p "$mroot"
msg() { # timestamp provider model input output cost
  jq -nc --arg t "$1" --arg p "$2" --arg m "$3" --argjson i "$4" --argjson o "$5" --argjson c "$6" \
    '{type:"message",timestamp:$t,message:{role:"assistant",provider:$p,model:$m,content:[{type:"text",text:"MODEL_SECRET"}],usage:{input:$i,output:$o,cacheRead:10,cacheWrite:5,cost:{total:$c}}}}'
}
jq -nc '{type:"session",id:"c",timestamp:"2024-05-02T12:00:00Z"}' > "$mroot/coord.jsonl"
msg 2024-05-02T12:10:00Z anthropic m1 1 2 0.5 >> "$mroot/coord.jsonl"
msg 2024-05-02T12:20:00Z anthropic m1 3 4 0.25 >> "$mroot/coord.jsonl"
msg 2024-05-02T13:30:00Z anthropic m1 100 100 9 >> "$mroot/coord.jsonl"
jq -nc --arg parent "$mroot/coord.jsonl" '{type:"session",id:"w",timestamp:"2024-05-02T12:00:00Z",parentSession:$parent}' > "$mroot/worker.jsonl"
jq -nc '{type:"session_info",timestamp:"2024-05-02T12:00:01Z",name:"general-purpose#WORKER02"}' >> "$mroot/worker.jsonl"
msg 2024-05-02T12:15:00Z openai m2 7 8 1.5 >> "$mroot/worker.jsonl"
jq -nc '{type:"message",timestamp:"2024-05-02T12:16:00Z",message:{role:"assistant",provider:"openai",model:"m2",content:[]}}' >> "$mroot/worker.jsonl"
touch -t 202405021400 "$mroot/coord.jsonl" "$mroot/worker.jsonl"
"$SCRIPT" --sessions-dir "$mroot" --since 2024-05-02T12:00:00Z --until=2024-05-02T13:00:00Z --json > "$tmp_root/model.json"
jq -e '
  (.window_end_local | type) == "string"
  and .model_metrics.nonworker_coordinators == {"anthropic/m1":{requests:2,input:4,output:6,cache_read:20,cache_write:10,cost_total:0.75}}
  and .model_metrics.workers == {"openai/m2":{requests:2,input:7,output:8,cache_read:10,cache_write:5,cost_total:1.5}}
' "$tmp_root/model.json" >/dev/null
"$SCRIPT" --sessions-dir "$mroot" --since 2024-05-02T12:00:00Z --json > "$tmp_root/model-open.json"
jq -e '.window_end_local == null and .model_metrics.nonworker_coordinators["anthropic/m1"].requests == 3' "$tmp_root/model-open.json" >/dev/null
"$SCRIPT" --sessions-dir "$mroot" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z > "$tmp_root/model.txt"
grep -Fq 'Window end (local):' "$tmp_root/model.txt"
grep -Fq 'Model nonworker_coordinators anthropic/m1: requests=2' "$tmp_root/model.txt"
if grep -E 'MODEL_SECRET|WORKER02' "$tmp_root/model.json" "$tmp_root/model.txt"; then
  echo 'model output leaked fixture content' >&2
  exit 1
fi
if "$SCRIPT" --sessions-dir "$mroot" --since 2024-05-02T12:00:00Z --until 2024-05-02T11:00:00Z > /dev/null 2> "$tmp_root/until.err"; then
  echo 'until before since unexpectedly succeeded' >&2
  exit 1
fi
grep -q -- '--until must not be earlier than --since' "$tmp_root/until.err"
if "$SCRIPT" --sessions-dir "$mroot" --until bogus > /dev/null 2> "$tmp_root/until.err"; then
  echo 'bad until unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'invalid --until timestamp' "$tmp_root/until.err"

# Retrospective metrics must filter event times even in old session files.
retro_root="$tmp_root/retro"
mkdir -p "$retro_root"
for role in coord worker; do
  file="$retro_root/$role.jsonl"
  jq -nc --arg role "$role" '{type:"session",timestamp:"2024-05-01T00:00:00Z"} + (if $role == "worker" then {parentSession:"/fixture/parent.jsonl"} else {} end)' > "$file"
  if [[ $role == worker ]]; then
    jq -nc '{type:"session_info",timestamp:"2024-05-01T00:00:01Z",name:"general-purpose#WORKER03"}' >> "$file"
  fi
  for time in 2024-05-01T01:00:00Z 2024-05-02T12:30:00Z 2024-05-03T00:00:00Z; do
    jq -nc --arg t "$time" '
      {type:"model_change",timestamp:$t,provider:"fixture",modelId:"m1"},
      {type:"compaction",timestamp:$t,summary:"COMPACTION_SECRET"},
      {type:"custom",timestamp:$t,customType:"unattended-handoff",data:{checkpoint:"HANDOFF_SECRET"}},
      {type:"custom_message",timestamp:$t,customType:"compaction-handoff",content:"HANDOFF_SECRET"},
      {type:"message",timestamp:$t,message:{role:"assistant",provider:"fixture",model:"m1",stopReason:"error",errorMessage:"api_key_expired ERROR_SECRET",content:[
        {type:"toolCall",name:"unattended_checkpoint",arguments:{status:"done",markdown:"CHECKPOINT_SECRET"}},
        {type:"text",text:"unattended_checkpoint TOOL_DEFINITION_SECRET"}
      ]}},
      {type:"message",timestamp:$t,message:{role:"assistant",provider:"fixture",model:"m2",stopReason:"error",errorMessage:"FREEFORM_ERROR_SECRET",content:[]}},
      {type:"model_change",timestamp:$t,provider:"fixture",modelId:"m3"}
    ' >> "$file"
  done
  # Invalid surrogate JSON and invalid UTF-8 must not lose valid later lines.
  printf '%s\n' '{"type":"message","text":"\ud800"}' >> "$file"
  printf '{"bad":"\377"}\n' >> "$file"
  jq -nc '{type:"compaction",timestamp:"2024-05-02T12:40:00Z",summary:"AFTER_MALFORMED_SECRET"}' >> "$file"
done
# Evidence files may contain plausible events, but no session header.
cp "$retro_root/coord.jsonl" "$retro_root/evidence.jsonl"
sed '1d' "$retro_root/evidence.jsonl" > "$tmp_root/evidence-no-header"
mv "$tmp_root/evidence-no-header" "$retro_root/evidence.jsonl"
# Actual structured tool calls only; neither definitions nor embedded codemode source count.
jq -nc '{type:"message",timestamp:"2024-05-02T12:30:00Z",message:{role:"assistant",content:[{type:"toolCall",name:"codemode",arguments:{code:"unattended_checkpoint({status: blocked})"}},{type:"tool",name:"unattended_checkpoint",arguments:{status:"blocked"}}]}}' >> "$retro_root/coord.jsonl"
"$SCRIPT" --sessions-dir "$retro_root" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/retro.json"
jq -e '
  .main_sessions == {older_with_activity:1} and .workers.sessions == 1
  and .scan == {files:3,session_files:2,non_session_jsonl_files:1,malformed_lines:6,skipped_lines:6,unreadable_files:0}
  and .retrospective.compactions == 4
  and .retrospective.handoffs == {custom:{"unattended-handoff":2},custom_message:{"compaction-handoff":2}}
  and .retrospective.unattended_checkpoint == {
    workers:{by_status:{done:1},files:1,files_by_status:{done:1}},
    nonworker_coordinators:{by_status:{done:1},files:1,files_by_status:{done:1}}}
  and .retrospective.stop_reason_errors == {
    by_provider_model:{"fixture/m1":2,"fixture/m2":2},
    auth_categories:{api_key_expired:2,unclassified:2},
    by_provider_model_auth_category:{"fixture/m1":{api_key_expired:2},"fixture/m2":{unclassified:2}}}
  and .retrospective.model_change_events == {transition:4}
  and (.retrospective.top_error_sessions | length) == 2
  and ([.retrospective.top_error_sessions[].errors] == [2,2])
  and .retrospective.top_turn_limit_sessions.available == false
  and .retrospective.accepted_outcomes.available == false and .retrospective.rework.available == false
' "$tmp_root/retro.json" >/dev/null || { cat "$tmp_root/retro.json"; exit 1; }
# Initial selections are distinguished from later events, never labeled fallback.
"$SCRIPT" --sessions-dir "$retro_root" --since 2024-05-01T00:00:00Z --until 2024-05-01T02:00:00Z --json > "$tmp_root/retro-initial.json"
jq -e '.retrospective.model_change_events == {initial_selection:2,transition:2}' "$tmp_root/retro-initial.json" >/dev/null
"$SCRIPT" --sessions-dir "$retro_root" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z > "$tmp_root/retro.txt"
if grep -E 'SECRET|WORKER03|errorMessage|markdown|toolCall' "$tmp_root/retro.json" "$tmp_root/retro.txt"; then
  echo 'retrospective output leaked fixture content' >&2
  exit 1
fi

# Receipts, task joins, checkpoint evidence, error categories and scan reconciliation.
ev="$tmp_root/evidence"
mkdir -p "$ev"
T1=aaaaaaaa-1111-2222-3333-444444444444   # joined single model
T2=bbbbbbbb-1111-2222-3333-444444444444   # mixed models
T3=cccccccc-1111-2222-3333-444444444444   # unmatched
T4=dddddddd-1111-2222-3333-444444444444   # prefix collision with T5
T5=dddddddd-9999-2222-3333-444444444444
coord="$ev/coord.jsonl"
ts=2024-05-02T12:10:00Z
{
  jq -nc '{type:"session",id:"c",timestamp:"2024-05-02T12:00:00Z"}'
  for t in "$T1" "$T2" "$T3" "$T4" "$T5"; do
    jq -nc --arg t "$t" '{type:"message",timestamp:"2024-05-02T12:01:00Z",message:{role:"assistant",content:[{type:"toolCall",id:("call-"+$t[0:4]),name:"Agent",arguments:{model:"sonnet",thinking:"medium",prompt:"EVIDENCE_PROMPT_SECRET"}}]}}'
    jq -nc --arg t "$t" '{type:"custom_message",customType:"subagent-notification",id:("n-"+$t[0:4]),timestamp:"2024-05-02T12:10:00Z",content:("<task-notification><task-id>"+$t+"</task-id><tool-use-id>call-"+$t[0:4]+"</tool-use-id><status>Done</status><result>RESULT_SECRET</result></task-notification>")}'
  done
  # Record evidence for T1 duplicates the notification; T3 is a record-only terminal task.
  jq -nc --arg t "$T1" '{type:"custom",customType:"subagents:record",timestamp:"2024-05-02T12:10:01Z",data:{id:$t,type:"general-purpose",status:"completed",result:"RECORD_SECRET"}}'
  jq -nc '{type:"custom",customType:"subagents:record",timestamp:"2024-05-02T12:10:01Z",data:{id:"eeeeeeee-1111",type:"x",status:"steered"}}'
  rc() { jq -nc --arg ts "$2" --argjson d "$1" '{type:"custom",customType:"task-outcome-receipt",timestamp:$ts,data:$d}'; }
  rc '{"taskId":"'"$T1"'","outcome":"reworked","model":"anthropic/m1","effort":"high","checkArtifact":"/tmp/CHECK_ARTIFACT_SECRET"}' 2024-05-02T12:11:00Z
  rc '{"taskId":"'"$T1"'","outcome":"accepted","model":"anthropic/m1","effort":"high","checkArtifact":"/tmp/CHECK_ARTIFACT_SECRET"}' 2024-05-02T12:12:00Z
  rc '{"taskId":"'"$T2"'","outcome":"rejected","model":"anthropic/m1","effort":"low","checkArtifact":"scripts/check.sh"}' 2024-05-02T12:12:00Z
  rc '{"taskId":"'"$T3"'","outcome":"great","model":"anthropic/m1","effort":"low"}' 2024-05-02T12:12:00Z
  rc '{"taskId":"'"$T3"'","outcome":"accepted","model":"bad model!","effort":"low"}' 2024-05-02T12:12:00Z
  rc '{"taskId":"'"$T3"'","outcome":"accepted","model":"m","effort":"ludicrous"}' 2024-05-02T12:12:00Z
  rc '{"taskId":"","outcome":"accepted","model":"m","effort":"low"}' 2024-05-02T12:12:00Z
  rc '{"taskId":"x","outcome":"accepted","model":"m","effort":"low","checkArtifact":{"a":1}}' 2024-05-02T12:12:00Z
  # Checkpoints: attempt, success, error result, unjoined, bad shape; continuation; handoff receipts.
  ck() { jq -nc --arg id "$1" --arg name "$2" '{type:"message",timestamp:"2024-05-02T12:20:00Z",message:{role:"assistant",content:[{type:"toolCall",id:$id,name:$name,arguments:{status:"done",markdown:"CHECKPOINT_SECRET"}}]}}'; }
  cr() { jq -nc --arg id "$1" --arg name "$2" --argjson err "$3" --argjson d "$4" '{type:"message",timestamp:"2024-05-02T12:21:00Z",message:{role:"toolResult",toolCallId:$id,toolName:$name,isError:$err,content:[{type:"text",text:"RESULT_TEXT_SECRET"}],details:$d}}'; }
  ck u1 unattended_checkpoint; cr u1 unattended_checkpoint false '{"status":"continue","path":"/p/PATH_SECRET.md","cwd":"/c"}'
  ck u2 unattended_checkpoint; cr u2 unattended_checkpoint true '{}'
  ck u3 unattended_checkpoint; cr u3 unattended_checkpoint false '{"status":"weird","path":"/p/x.md","cwd":"/c"}'
  cr u9 unattended_checkpoint false '{"status":"done","path":"/p/x.md","cwd":"/c"}'
  ck h1 handoff_checkpoint; cr h1 handoff_checkpoint false '{"path":"/p/h.md","cwd":"/c"}'
  ck h2 handoff_checkpoint; cr h2 handoff_checkpoint false '{"path":"relative.md","cwd":"/c"}'
  jq -nc '{type:"custom_message",customType:"unattended-continuation",timestamp:"2024-05-02T12:22:00Z",content:"CONT_SECRET"}'
  jq -nc '{type:"custom",customType:"compaction-handoff-written",timestamp:"2024-05-02T12:23:00Z",data:{sessionId:"c",checkpointPath:"/p/h.md"}}'
  jq -nc '{type:"custom",customType:"compaction-handoff-approved",timestamp:"2024-05-02T12:23:00Z",data:{sessionId:"c",checkpointPath:"/p/h.md"}}'
  jq -nc '{type:"custom",customType:"compaction-handoff-approved",timestamp:"2024-05-02T12:23:00Z",data:{}}'
  for m in "overloaded_error" "rate_limit_error x" "ECONNRESET" "context_length_exceeded" "SOMETHING_SECRET_ERR"; do
    jq -nc --arg e "$m" '{type:"message",timestamp:"2024-05-02T12:30:00Z",message:{role:"assistant",provider:"p",model:"m",stopReason:"error",errorMessage:$e,content:[]}}'
  done
} > "$coord"
wk() { # name-task model...
  local f="$ev/w-$1.jsonl"; shift
  jq -nc --arg p "$coord" '{type:"session",id:"w",timestamp:"2024-05-02T12:00:00Z",parentSession:$p}' > "$f"
  jq -nc --arg n "$1" '{type:"session_info",timestamp:"2024-05-02T12:00:01Z",name:$n}' >> "$f"
  shift
  for m in "$@"; do msg 2024-05-02T12:05:00Z openai "$m" 1 1 0 >> "$f"; done
}
wk a "general-purpose#${T1:0:8}" wm1
wk b "general-purpose#${T2:0:8}" wm1 wm2
wk d1 "general-purpose#${T4:0:8}" wm1
wk d2 "general-purpose#${T5:0:8}" wm1
: > "$ev/empty.jsonl"; printf '{"x":1}\n' > "$ev/headerless.jsonl"; printf 'not json\n' > "$ev/garbage.jsonl"
jq -nc '{type:"session",timestamp:"2020-01-01T00:00:00Z"}' > "$ev/idle.jsonl"
"$SCRIPT" --sessions-dir "$ev" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/ev.json"
jq -e '
  .task_evidence.terminal_tasks == 6
  and .task_evidence.status_sources == {both:1,notification_only:4,record_only:1}
  and .task_evidence.worker_join == {joined_single_model:1,mixed_models:1,no_worker:2,ambiguous:2}
  and .task_evidence.actual_model_terminal_status == {"openai/wm1":{done:1}}
  and .task_evidence.requested_model == {sonnet:5} and .task_evidence.requested_effort == {medium:5}
  and .task_evidence.request_join == {matched_agent_call:5,unmatched:1}
  and .task_evidence.requested_vs_actual == {"requested=sonnet actual=openai/wm1":1}
  and .task_evidence.runtime_effort.available == false
  and .terminal_notification_statuses_unique == {done:5}
  and .retrospective.task_outcomes.available == true and .retrospective.task_outcomes.actual_runtime_proof == false
  and .retrospective.task_outcomes.receipts_valid == 3 and .retrospective.task_outcomes.receipts_invalid == 5
  and .retrospective.task_outcomes.tasks_with_receipt == 2
  and .retrospective.task_outcomes.latest_outcomes == {accepted:1,rejected:1}
  and .retrospective.task_outcomes.rework_history_tasks == 1 and .retrospective.task_outcomes.rework_events == 1
  and .retrospective.task_outcomes.coverage == {terminal_tasks_observed:6,dispatches_observed:5,receipted_tasks_with_terminal_evidence:2,receipted_tasks_without_terminal_evidence:0}
  and .retrospective.task_outcomes.by_model_effort == {"anthropic/m1":{
      high:{tasks:1,latest_outcomes:{accepted:1},rework_history_tasks:1,receipts:2,check_artifact_present:1},
      low:{tasks:1,latest_outcomes:{rejected:1},rework_history_tasks:0,receipts:1,check_artifact_present:1}}}
  and .retrospective.accepted_outcomes == {available:true,source:"coordinator_reported_task_outcome_receipt",accepted_latest:1,denominator_tasks_with_receipt:2}
  and .retrospective.unattended_checkpoint.nonworker_coordinators.by_status == {done:3}
  and .retrospective.checkpoint_evidence.unattended == {successful_by_status:{continue:1},successful:1,error_results:1,invalid_results:2,continuations:1}
  and .retrospective.checkpoint_evidence.handoff_checkpoint == {attempts:2,successful:1,error_results:0,invalid_results:1,written_receipts:1,approved_receipts:1}
  and .retrospective.stop_reason_errors.auth_categories == {overloaded:1,rate_limit:1,network:1,context_overflow:1,unclassified:1}
  and .scan_reconciliation == {candidates:9,scanned:9,session_files_with_window_activity:5,session_files_without_window_activity:1,headerless_nonempty:2,headerless_empty:1,unreadable:0,classified_main_fork_worker:5,candidates_match_scanned:true,partition_balanced:true,classification_balanced:true,error_categories_match_errors:true}
' "$tmp_root/ev.json" >/dev/null || { jq '.task_evidence,.retrospective.task_outcomes,.retrospective.checkpoint_evidence,.scan_reconciliation,.retrospective.stop_reason_errors' "$tmp_root/ev.json"; exit 1; }
"$SCRIPT" --sessions-dir "$ev" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z > "$tmp_root/ev.txt"
if grep -E "SECRET|$T1|${T1:0:8}|call-|/tmp/|/p/" "$tmp_root/ev.json" "$tmp_root/ev.txt"; then
  echo 'evidence output leaked fixture content' >&2
  exit 1
fi
# Without receipts, outcomes are unavailable rather than zero.
"$SCRIPT" --sessions-dir "$mroot" --since 2024-05-02T12:00:00Z --json | jq -e '.retrospective.task_outcomes.available == false and .retrospective.rework.available == false and .scan_reconciliation.balanced != false' >/dev/null

# Receipt trust-boundary limits match the emitting extension, including required artifacts.
receipt_root="$tmp_root/receipt-boundaries"
mkdir -p "$receipt_root"
jq -nc '{type:"session",timestamp:"2024-05-02T12:00:00Z"},
  ({taskId:"task/a@b+c",outcome:"accepted",model:("m" * 128),effort:"unknown",checkArtifact:("p" * 300)} as $good
   | [$good, ($good | .taskId = "x" | del(.checkArtifact)),
      ($good | .checkArtifact = ("p" * 301)), ($good | .checkArtifact = "a b"),
      ($good | .model = ("m" * 129)), ($good | .taskId = ("t" * 129))][]
   | {type:"custom",customType:"task-outcome-receipt",timestamp:"2024-05-02T12:01:00Z",data:.})' > "$receipt_root/c.jsonl"
"$SCRIPT" --sessions-dir "$receipt_root" --since 2024-05-02T12:00:00Z --json |
  jq -e '.retrospective.task_outcomes.receipts_valid == 1 and .retrospective.task_outcomes.receipts_invalid == 5' >/dev/null

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

# Discovery failures must not produce a plausible partial-coverage report.
failed_find="$tmp_root/failed-find-bin"
mkdir -p "$failed_find"
printf '#!/bin/sh\nexit 7\n' > "$failed_find/find"
chmod +x "$failed_find/find"
if PATH="$failed_find:$PATH" "$SCRIPT" --sessions-dir "$root" --json > "$tmp_root/failed-find.out"; then
  echo 'failed candidate discovery unexpectedly succeeded' >&2
  exit 1
fi
test ! -s "$tmp_root/failed-find.out"

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
