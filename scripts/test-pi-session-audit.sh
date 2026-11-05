#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/pi-session-audit.sh"
command -v jq >/dev/null || { echo 'test requires jq' >&2; exit 1; }
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/pi-session-audit-test.XXXXXX")
printf 'test-pi-session-audit owns temporary directory %s\n' "$tmp_root" >&2
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
    "Direct tool-call metrics exclude nested calls; recognized typed nestedCalls metadata is reported separately. Files last modified before --since are skipped.",
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

# Malformed message containers must not interrupt the file reducer or erase valid metrics.
malformed_root="$tmp_root/malformed-messages"
mkdir -p "$malformed_root"
jq -nc '{type:"session",timestamp:"2024-05-02T12:00:00Z"},
  ({type:"message",timestamp:"2024-05-02T12:10:00Z",message:{role:"assistant",provider:"p",model:"m",durationMs:100,content:[]}} as $valid
   | $valid, ([[],"PRIVATE_SECRET",42][] | {type:"message",timestamp:"2024-05-02T12:11:00Z",message:.}), ($valid | .message.durationMs = 900))' > "$malformed_root/c.jsonl"
"$SCRIPT" --sessions-dir "$malformed_root" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/malformed-messages.json"
jq -e '.main_sessions.created_within_window == 1 and .scan.unreadable_files == 0
  and .model_metrics.nonworker_coordinators["p/m"].requests == 2
  and .coordinator_activity.response_duration_ms == {count:2,p50:100,p90:900,assistant_messages:2,missing_or_invalid:0}' "$tmp_root/malformed-messages.json" >/dev/null

# Fractional boundaries keep epoch filtering while labels use the correct local offset.
TZ=Europe/Paris "$SCRIPT" --sessions-dir "$root" --since '2024-05-02T16:30:00.5Z' --until '2024-05-02T16:30:00.75Z' --json > "$tmp_root/fractional.json"
jq -e '.window_start_local == "2024-05-02T18:30:00+02:00" and .window_end_local == "2024-05-02T18:30:00+02:00" and .agent_dispatches.total == 0' "$tmp_root/fractional.json" >/dev/null
TZ=Europe/Paris "$SCRIPT" --sessions-dir "$root" --since '2024-11-04T20:40:54.521288Z' --json > "$tmp_root/fractional-winter.json"
jq -e '.window_start_local == "2024-11-04T21:40:54+01:00"' "$tmp_root/fractional-winter.json" >/dev/null

# A naive local cutoff must select the same events as the equivalent explicit offset.
TZ=America/New_York "$SCRIPT" --sessions-dir "$root" --since '2024-05-02T12:00:00' --json > "$tmp_root/naive.json"
jq -e --slurpfile expected "$tmp_root/report.json" 'del(.scan_timing) == ($expected[0] | del(.scan_timing))' "$tmp_root/naive.json" >/dev/null
TZ=America/New_York "$SCRIPT" --sessions-dir "$root" --since '2024-05-02T12:00:00-04' --json > "$tmp_root/hour-offset.json"
jq -e --slurpfile expected "$tmp_root/report.json" 'del(.scan_timing) == ($expected[0] | del(.scan_timing))' "$tmp_root/hour-offset.json" >/dev/null
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
grep -Fq 'Limitations: Direct tool-call metrics exclude nested calls; recognized typed nestedCalls metadata is reported separately. Files last modified before --since are skipped.' "$tmp_root/plain.txt"
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
  and (.retrospective.task_outcomes.coverage | del(.terminal_tasks_with_receipt, .terminal_tasks_without_receipt)) == {terminal_tasks_observed:6,dispatches_observed:5,receipted_tasks_with_terminal_evidence:2,receipted_tasks_without_terminal_evidence:0}
  and .retrospective.task_outcomes.by_model_effort == {"anthropic/m1":{
      high:{tasks:1,latest_outcomes:{accepted:1},rework_history_tasks:1,receipts:2,check_artifact_present:1},
      low:{tasks:1,latest_outcomes:{rejected:1},rework_history_tasks:0,receipts:1,check_artifact_present:1}}}
  and .retrospective.accepted_outcomes == {available:true,source:"coordinator_reported_task_outcome_receipt",accepted_latest:1,denominator_tasks_with_receipt:2}
  and .retrospective.unattended_checkpoint.nonworker_coordinators.by_status == {done:3}
  and (.retrospective.checkpoint_evidence.unattended | del(.continuation_linkage)) == {successful_by_status:{continue:1},successful:1,error_results:1,invalid_results:2,continuations:1}
  and .retrospective.checkpoint_evidence.handoff_checkpoint == {attempts:2,successful:1,error_results:0,invalid_results:1,written_receipts:1,approved_receipts:1}
  and .retrospective.stop_reason_errors.auth_categories == {overloaded:1,rate_limit:1,network:1,context_overflow:1,unclassified:1}
  and (.scan_reconciliation | del(.partition_residual, .candidate_partition, .unexpected_summary_shape)) == {candidates:9,scanned:9,session_files_with_window_activity:5,session_files_without_window_activity:1,headerless_nonempty:2,headerless_empty:1,unreadable:0,classified_main_fork_worker:5,candidates_match_scanned:true,partition_balanced:true,classification_balanced:true,error_categories_match_errors:true}
' "$tmp_root/ev.json" >/dev/null || { jq '.task_evidence,.retrospective.task_outcomes,.retrospective.checkpoint_evidence,.scan_reconciliation,.retrospective.stop_reason_errors' "$tmp_root/ev.json"; exit 1; }
# Candidate partition explains every scanned file; unusual parsed results are categories, not leftovers.
jq -e '
  .scan_reconciliation.partition_residual == 0
  and .scan_reconciliation.candidate_partition == {
    session_with_window_activity:5,session_without_window_activity:1,headerless_with_parsed_events:1,
    headerless_all_lines_malformed:1,headerless_empty:1,unreadable:0,unexpected_summary_shape:0,
    informational_subsets:{session_header_only:1},explained_total:9,fully_explained:true}
  and .retrospective.task_outcomes.coverage.terminal_tasks_with_receipt == 2
  and .retrospective.task_outcomes.coverage.terminal_tasks_without_receipt == 4
  and .task_evidence.raw_termination.terminal_tasks == {done:4,completed:1,steered:1}
  and .task_evidence.raw_termination.terminal_tasks_by_normalized_status == {done:{done:4,completed:1},turn_limit:{steered:1}}
  and .task_evidence.raw_termination_records_unique_tasks == {completed:1,steered:1}
  and .retrospective.checkpoint_evidence.unattended.continuation_linkage
      == (.retrospective.checkpoint_evidence.unattended.continuation_linkage
          | .linked_continuations = 1 | .linked_by_temporal_order = 1 | .linked_by_exact_parent_id = 0
          | .unlinked_continuation_entries = 0 | .continue_checkpoint_successes = 1 | .continue_successes_without_linked_continuation = 0)
  and .retrospective.checkpoint_evidence.unattended.continuation_linkage.accepted_usefulness.available == false
  and .observability.direct_codemode_tool_calls == 0
' "$tmp_root/ev.json" >/dev/null || { jq '.scan_reconciliation,.retrospective.checkpoint_evidence.unattended,.task_evidence.raw_termination' "$tmp_root/ev.json"; exit 1; }
# Regression: a summary that is neither session, headerless nor unreadable used to leave partition_balanced silently false.
printf '%s\n' '{"path":"b","has_header":false,"nonblank":0,"malformed_lines":0}' '{"path":"c"}' 'null' '{"_candidates":3}' |
  jq -s --arg mode aggregate --arg time '' --arg path '' --argjson cutoff 0 --argjson until null --arg window_end_local '' --arg window_start_local '' -f "$(dirname "$SCRIPT")/pi-session-audit.jq" |
  jq -e '.scan_reconciliation.partition_balanced == true and .scan_reconciliation.partition_residual == 0
    and .scan_reconciliation.candidate_partition.unexpected_summary_shape == 2
    and .scan_reconciliation.candidate_partition.fully_explained == true' >/dev/null

# Typed nested metadata is separate from direct attempts and never emits payload fields.
nested="$tmp_root/nested"
mkdir -p "$nested"
cat > "$nested/a.jsonl" <<'EOF'
{"type":"session","timestamp":"2024-05-02T12:00:00Z"}
{"type":"message","timestamp":"not-a-timestamp","message":[]}
{"type":"message","timestamp":"2024-05-02T12:30:00Z","message":{"role":"toolResult","toolName":"codemode","nestedCalls":{"calls":[{"name":"TaskCreate","durationMs":12,"arguments":{"prompt":"NESTED_SECRET"}},{"name":"unattended_checkpoint","durationMs":4,"error":"NESTED_SECRET"},{"name":"TaskCreate","durationMs":"NESTED_SECRET"},{"name":"NESTED_SECRET","durationMs":2}]}}}
{"type":"message","timestamp":"2024-05-03T12:30:00Z","message":{"role":"toolResult","nestedCalls":{"calls":[{"name":"TaskCreate","durationMs":999}]}}}
EOF
"$SCRIPT" --sessions-dir "$nested" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/nested.json"
jq -e '.observability.nested_typed_calls == {TaskCreate:{calls:2,timed:1,duration_ms:12,errors:0},unattended_checkpoint:{calls:1,timed:1,duration_ms:4,errors:1}} and .observability.direct_structured_unattended_checkpoint_attempts == 0 and (.scan_timing.started_at_utc | fromdateiso8601) <= (.scan_timing.ended_at_utc | fromdateiso8601)' "$tmp_root/nested.json" >/dev/null
if grep -q NESTED_SECRET "$tmp_root/nested.json"; then echo 'nested metadata leaked payload' >&2; exit 1; fi

# Response timing and compaction use typed fields, never message or summary bodies.
activity="$tmp_root/activity"
mkdir -p "$activity"
cat > "$activity/a.jsonl" <<'EOF'
{"type":"session","timestamp":"2024-05-02T12:00:00Z"}
{"type":"message","timestamp":"2024-05-02T12:10:00Z","message":{"role":"assistant","provider":"p","model":"m","durationMs":100,"content":[{"type":"toolCall","name":"bash","arguments":{"command":"ACTIVITY_SECRET"}},{"type":"toolCall","name":"read","arguments":{"path":"ACTIVITY_SECRET"}}]}}
{"type":"message","timestamp":"2024-05-02T12:11:00Z","message":{"role":"assistant","provider":"p","model":"m","durationMs":900,"content":[]}}
{"type":"message","timestamp":"2024-05-02T12:12:00Z","message":{"role":"assistant","provider":"p","model":"m","durationMs":-1}}
{"type":"message","timestamp":"2024-05-03T12:12:00Z","message":{"role":"assistant","provider":"p","model":"m","durationMs":99999,"content":[]}}
{"type":"custom","customType":"task-outcome-activation","timestamp":"2024-05-02T12:12:01Z","data":{"schemaVersion":1,"extensionVersion":1,"source":"startup","timestamp":"2024-05-02T12:12:01Z","extensionSha256":null,"coordinatorPolicySha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}
{"type":"custom","customType":"task-outcome-activation","timestamp":"2024-05-02T12:12:02Z","data":{"schemaVersion":2,"source":"ACTIVITY_SECRET"}}
{"type":"compaction","timestamp":"2024-05-02T12:13:00Z","tokensBefore":1200,"summary":"ACTIVITY_SECRET"}
{"type":"compaction","timestamp":"2024-05-02T12:14:00Z","tokensBefore":"invalid","summary":"ACTIVITY_SECRET"}
EOF
"$SCRIPT" --sessions-dir "$activity" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/activity.json"
jq -e '.coordinator_activity.response_duration_ms == {count:2,p50:100,p90:900,assistant_messages:3,missing_or_invalid:1}
  and .coordinator_activity.tool_calls_per_assistant_message == {count:2,p50:0,p90:2,total:2,missing_content:1}
  and .coordinator_activity.compaction_tokens_before == {count:1,p50:1200,p90:1200,compaction_events:2,missing_or_invalid:1}
  and .coordinator_activity.turn_tool_calls.available == false
  and .future_evidence.policy_receipts.valid == 1 and .future_evidence.policy_receipts.invalid == 1 and .future_evidence.policy_receipts.sources == {startup:1} and .future_evidence.policy_receipts.policy_hash_present == 1 and .future_evidence.policy_receipts.extension_hash_present == 0
  and .future_evidence.accepted_board_task_cost.available == false
  and .future_evidence.checkpoint_parent_identity.available == false' "$tmp_root/activity.json" >/dev/null
if grep -q ACTIVITY_SECRET "$tmp_root/activity.json"; then echo 'activity metadata leaked payload' >&2; exit 1; fi

# Published producer event shapes: valid timings, unknown pairs, inverted clock, quota provenance.
producer="$tmp_root/producer"
mkdir -p "$producer"
{
  jq -nc '{type:"session",timestamp:"2024-05-02T12:00:00Z"}'
  jq -nc '[{taskId:"b1",attemptId:"attempt01",state:"ready",timestamp:1000},{taskId:"b1",attemptId:"attempt01",state:"submitted",timestamp:1200},{taskId:"b1",attemptId:"attempt01",state:"started",timestamp:1300,requestedModel:"p/m",actualModel:"p/m2",actualEffort:"high",actualSource:"subagents:usage"},{taskId:"b2",attemptId:"attempt02",state:"submitted",timestamp:2000},{taskId:"b2",attemptId:"attempt02",state:"started",timestamp:1900},{taskId:"b2",attemptId:"attempt02",state:"blocked",timestamp:2100}][] | {type:"custom",customType:"fast-task-dispatch",timestamp:"2024-05-02T12:10:00Z",data:(. + {schemaVersion:1,coordinatorSessionId:"session01",reason:(if .state == "ready" then "eligible" elif .state == "submitted" then "native_submission" elif .state == "started" then "native_started" else "PRODUCER_SECRET" end)})}'
  jq -nc '{type:"custom",customType:"quota-status-metrics",timestamp:"2024-05-02T12:10:00Z",data:{version:1,decisionSnapshotAt:5000,fetchDurationMs:12,refreshReason:"default",observations:[{provider:"openai",capturedAt:4900,cacheHit:true,ageMs:100},{provider:"anthropic",capturedAt:null,cacheHit:null,ageMs:null},{provider:"opencode-go",capturedAt:5000,cacheHit:false,ageMs:0}]}}'
} > "$producer/a.jsonl"
"$SCRIPT" --sessions-dir "$producer" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/producer.json"
jq -e '.dispatch_lifecycle.attempts == 2 and .dispatch_lifecycle.ready_to_submitted_ms == {count:1,p50:200,p90:200,attempts:2,unknown:1,inverted:0}
  and .dispatch_lifecycle.submitted_to_started_ms == {count:1,p50:100,p90:100,attempts:2,unknown:0,inverted:1}
  and .dispatch_lifecycle.blocked_events == 1 and .dispatch_lifecycle.provenance.actual_model == {"p/m2":1} and .dispatch_lifecycle.provenance.requested_and_actual == {"requested=p/m actual=p/m2":1} and .dispatch_lifecycle.provenance.actual_effort == {high:1} and .quota_cache.fetch_duration_ms.count == 1 and .quota_cache.fetch_duration_ms.p50 == 12
  and .quota_cache.providers.openai.hit == 1 and .quota_cache.providers.anthropic.unknown == 1 and .quota_cache.providers["opencode-go"].miss == 1' "$tmp_root/producer.json" >/dev/null
if grep -q PRODUCER_SECRET "$tmp_root/producer.json"; then echo 'producer metadata leaked payload' >&2; exit 1; fi

# Raw termination labels distinguish aborted/steered/wrapped-up from explicit cap labels; normalized counts stay comparable.
tr_root="$tmp_root/termination"
mkdir -p "$tr_root"
{
  jq -nc '{type:"session",timestamp:"2024-05-02T12:00:00Z"}'
  i=0
  for st in "Done" "Wrapped up (limit)" "Aborted" "Turn limit reached" "Max turns exceeded" "Steered" "Stopped" "Error: SECRET_ERR" "weird SECRET_STATUS"; do
    i=$((i + 1))
    jq -nc --arg st "$st" --arg id "term000$i" '{type:"custom_message",customType:"subagent-notification",id:$id,timestamp:"2024-05-02T12:10:00Z",content:("<task-id>"+$id+"-xxxx</task-id><status>"+$st+"</status><result>TERM_SECRET</result>")}'
  done
  jq -nc '{type:"custom",customType:"subagents:record",timestamp:"2024-05-02T12:10:01Z",data:{id:"recd0001-xxxx",status:"aborted"}}'
  jq -nc '{type:"custom",customType:"subagents:record",timestamp:"2024-05-02T12:10:01Z",data:{id:"recd0002-xxxx",status:"steered"}}'
} > "$tr_root/c.jsonl"
"$SCRIPT" --sessions-dir "$tr_root" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/term.json"
jq -e '
  .terminal_notification_statuses_unique == {done:1,turn_limit:4,stopped:1,error:1}
  and .task_evidence.raw_termination_notifications_unique == {done:1,wrapped_up:1,aborted:1,turn_limit_cap:1,max_turns_cap:1,steered:1,stopped:1,error:1,other:1}
  and .task_evidence.raw_termination_records_unique_tasks == {aborted:1,steered:1}
  and .task_evidence.raw_termination.terminal_tasks_by_normalized_status.turn_limit
      == {wrapped_up:1,aborted:2,turn_limit_cap:1,max_turns_cap:1,steered:1}
' "$tmp_root/term.json" >/dev/null || { jq '.terminal_notification_statuses_unique,.task_evidence' "$tmp_root/term.json"; exit 1; }
if grep -E 'SECRET|term000' "$tmp_root/term.json"; then echo 'termination output leaked fixture content' >&2; exit 1; fi

# Continuation linkage is same-file, ordered and consumed once; it never implies acceptance.
ln_root="$tmp_root/linkage"
mkdir -p "$ln_root"
{
  jq -nc '{type:"session",timestamp:"2024-05-02T12:00:00Z"}'
  lk() { jq -nc --arg id "$1" --arg ts "$2" --arg st "$3" --arg eid "$4" '{type:"message",id:$eid,timestamp:$ts,message:{role:"toolResult",toolCallId:$id,toolName:"unattended_checkpoint",isError:false,details:{status:$st,path:"/p/x.md",cwd:"/c"}}}'; }
  lc() { jq -nc --arg ts "$1" --arg parent "$2" '{type:"custom_message",customType:"unattended-continuation",timestamp:$ts,parentId:$parent,content:"LINK_SECRET"}'; }
  call() { jq -nc --arg id "$1" '{type:"message",timestamp:"2024-05-02T12:01:00Z",message:{role:"assistant",content:[{type:"toolCall",id:$id,name:"unattended_checkpoint",arguments:{status:"continue"}}]}}'; }
  call a; lk a 2024-05-02T12:02:00Z continue ent-a
  lc 2024-05-02T12:03:00Z other        # temporal link
  lc 2024-05-02T12:04:00Z other        # already consumed: notice
  call b; lk b 2024-05-02T12:05:00Z continue ent-b
  lc 2024-05-02T12:06:00Z ent-b        # exact parent link
  call c; lk c 2024-05-02T12:07:00Z blocked ent-c
  lc 2024-05-02T12:08:00Z ent-c        # no pending continue: notice
  call d; lk d 2024-05-02T12:09:00Z continue ent-d   # never continued
  lc 2024-05-02T12:08:30Z ent-d                    # timestamp inversion must stay unlinked
  call e; lk e 2024-05-02T12:10:00Z done ent-e       # clears pending d
  lc 2024-05-02T12:11:00Z ent-d
} > "$ln_root/a.jsonl"
{ jq -nc '{type:"session",timestamp:"2024-05-02T12:00:00Z"}'
  jq -nc '{type:"custom_message",customType:"unattended-continuation",timestamp:"2024-05-02T12:30:00Z",content:"LINK_SECRET"}'
} > "$ln_root/b.jsonl"
"$SCRIPT" --sessions-dir "$ln_root" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/link.json"
jq -e '.retrospective.checkpoint_evidence.unattended | .continuations == 7
  and .continuation_linkage.linked_continuations == 2 and .continuation_linkage.linked_by_exact_parent_id == 1
  and .continuation_linkage.linked_by_temporal_order == 1 and .continuation_linkage.unlinked_continuation_entries == 5
  and .continuation_linkage.continue_checkpoint_successes == 3
  and .continuation_linkage.continue_successes_without_linked_continuation == 1
  and .continuation_linkage.accepted_usefulness.available == false' "$tmp_root/link.json" >/dev/null || { jq '.retrospective.checkpoint_evidence.unattended' "$tmp_root/link.json"; exit 1; }
if grep -E 'SECRET|ent-' "$tmp_root/link.json"; then echo 'linkage output leaked fixture content' >&2; exit 1; fi

"$SCRIPT" --sessions-dir "$ev" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z > "$tmp_root/ev.txt"
# Diagnostic session paths may live under /tmp; fixture payload paths contain SECRET.
if grep -E "SECRET|$T1|${T1:0:8}|call-|/p/" "$tmp_root/ev.json" "$tmp_root/ev.txt"; then
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

# Execute actual producers offline, reusing the continuity producer's own harness.
# Dispatch emitter/native-usage projection is extracted below; earlier synthetic cases remain compatibility tests.
export AUDIT_FIXTURE_ROOT="$tmp_root/producer-shaped"
mkdir -p "$AUDIT_FIXTURE_ROOT"
AUDIT_FIXTURE_ROOT=$(cd "$AUDIT_FIXTURE_ROOT" && pwd)
export AUDIT_REPO="$(cd "$(dirname "$SCRIPT")/.." && pwd)"
if [[ -z ${PI_RUNTIME:-} ]]; then
  command -v brew >/dev/null || { echo 'set PI_RUNTIME to the provisioned Pi package directory' >&2; exit 1; }
  PI_RUNTIME="$(brew --prefix pi-coding-agent)/libexec/lib/node_modules/@earendil-works/pi-coding-agent"
fi
for required in package.json dist/index.js dist/core/nested-tool-calls.js node_modules/jiti/lib/jiti.mjs node_modules/typebox/build/index.mjs node_modules/@earendil-works/pi-ai/dist/models.js; do
  [[ -f "$PI_RUNTIME/$required" ]] || { echo "invalid PI_RUNTIME package directory: missing $required" >&2; exit 1; }
done
command -v bun >/dev/null || { echo 'producer tests require Bun' >&2; exit 1; }
export PI_RUNTIME
bun --no-install - <<'TS'
import assert from "node:assert/strict"
import { randomUUID } from "node:crypto"
import { readFile, writeFile, mkdir } from "node:fs/promises"
import { join } from "node:path"
const repoRoot = process.env.AUDIT_REPO!, root = process.env.AUDIT_FIXTURE_ROOT!, runtime = process.env.PI_RUNTIME!
assert.equal(JSON.parse(await readFile(join(runtime, "package.json"), "utf8")).name, "@earendil-works/pi-coding-agent", "PI_RUNTIME must name the Pi package directory")
const { createJiti } = await import(join(runtime, "node_modules/jiti/lib/jiti.mjs"))
const jiti = createJiti(join(repoRoot, "scripts/test-pi-session-audit.sh"), { moduleCache: false, fsCache: false,
  alias: { "@earendil-works/pi-ai/models": join(runtime, "node_modules/@earendil-works/pi-ai/dist/models.js"), "@earendil-works/pi-coding-agent": join(runtime, "dist/index.js"), typebox: join(runtime, "node_modules/typebox/build/index.mjs") } })
const { default: outcomes, validateReceipt } = await jiti.import(join(repoRoot, "home/private_dot_pi/private_agent/private_extensions/task-outcome-receipt.ts"))
const { default: handoff } = await jiti.import(join(repoRoot, "home/private_dot_pi/private_agent/private_extensions/compaction-handoff.ts"))
const ts = "2024-05-02T12:10:00Z", coordinator = join(root, "c.jsonl")
const events: any[] = [{ type: "session", timestamp: ts }]
const emit = (customType: string, data: unknown) => events.push({ type: "custom", customType, data, timestamp: ts })
let receiptTool: any; const hooks: any = {}
outcomes({ registerTool: (t: any) => receiptTool = t, on: (name: string, fn: any) => hooks[name] = fn, appendEntry: emit } as never)
const ctx = { getSystemPrompt: () => "coordinator", sessionManager: { getBranch: () => [] }, ui: { setStatus() {}, notify() {} } }
hooks.session_start({ reason: "startup" }, ctx)
const receipt = async (worker: string, board: string | undefined, extra: any = {}) => {
  const data = { taskId: worker, outcome: "accepted", model: "claimed/model", effort: "medium", checkArtifact: "/PRIVATE_SECRET/check.md",
    ...(board ? { boardTaskId: board, attemptId: "attempt-" + worker, phase: "implementation" } : {}), ...extra }
  assert.deepEqual(validateReceipt(data), data)
  await receiptTool.execute("receipt", data, undefined, undefined, ctx)
}
await receipt("worker01-aaaa", "board-1", { reviewerWorkerId: "review01-aaaa", coordinatorReportedDurationMs: 500 })
await receipt("worker01-aaaa", "board-1", { reviewerWorkerId: "review01-aaaa", coordinatorReportedDurationMs: 500 }) // identical evidence, once
await receipt("repair01-aaaa", "repair-1", { outcome: "reworked", phase: "repair", parentTaskId: "board-1", coordinatorReportedDurationMs: 1234 })
await receipt("missing1-aaaa", "board-2")
await receipt("mixed001-aaaa", "board-3")
await receipt("reused01-aaaa", "board-4")
await receipt("reused01-aaaa", "board-5")
await receipt("sparse01-aaaa", "board-6")
await receipt("legacy01-aaaa", undefined, { outcome: "rejected", phase: "review", coordinatorReportedDurationMs: 250 })
events.push({ type: "custom", customType: "task-outcome-receipt", timestamp: ts,
  data: { taskId: "bad", outcome: "accepted", model: "p/m", effort: "high", checkArtifact: "x", phase: "PRIVATE_SECRET" } })
events.push({ ...events[1], timestamp: "2024-05-03T12:00:00Z" })
const worker = async (id: string, costs: any[], models = ["m"]) => {
  const rows: any[] = [{ type: "session", timestamp: ts, parentSession: coordinator }, { type: "session_info", timestamp: ts, name: "implementer#" + id.slice(0, 8) }]
  costs.forEach((cost, i) => rows.push({ type: "message", id: "message-" + i, timestamp: ts, message: { role: "assistant", provider: "p", model: models[i % models.length], usage: cost === null ? {} : { cost: { total: cost } }, content: [] } }))
  if (id === "worker01-aaaa") rows.push({ ...rows[2] })
  rows.push({ type: "message", timestamp: "2024-05-03T12:00:00Z", message: { role: "assistant", provider: "p", model: "m", usage: { cost: { total: 999 } }, content: [] } })
  await writeFile(join(root, id + ".jsonl"), rows.map(r => JSON.stringify(r)).join("\n") + "\n")
}
await worker("worker01-aaaa", [2]); await worker("review01-aaaa", [0.5]); await worker("repair01-aaaa", [1])
await worker("mixed001-aaaa", [8, 9], ["m", "m2"]); await worker("reused01-aaaa", [10]); await worker("sparse01-aaaa", [null, 0, -1])
// Extract the *actual* privacy projection expression; no network collector invocation.
const quotaSource = await readFile(join(repoRoot, "home/private_dot_pi/private_agent/private_extensions/quota-status/index.ts"), "utf8")
const start = quotaSource.indexOf('pi.appendEntry("quota-status-metrics", {')
const end = quotaSource.indexOf('\n      return { content:', start)
assert.ok(start >= 0 && end > start)
const projectQuota = new Function("pi", "snapshot", "decisionSnapshotAt", "startedAt", "_params", quotaSource.slice(start, end))
projectQuota({ appendEntry: emit }, {
  providers: ["openai", "anthropic", "anthropic-api", "github-copilot", "opencode-go", "opencode"].map((provider, i) => ({ provider, capturedAt: i === 1 ? null : 4900, ...(i === 1 ? {} : { cache: { hit: i === 0 } }), secret: "PRIVATE_SECRET" })),
  codexbarCredits: { capturedAt: null, secret: "PRIVATE_SECRET" },
}, 5000, 4980, {})
// Reuse the producer test harness, but run only one offline write/proposal/consume.
const harnessSource = await readFile(join(repoRoot, "scripts/test-compaction-handoff.sh"), "utf8")
const harness = harnessSource.slice(harnessSource.indexOf("type Handler ="), harnessSource.indexOf('for (const event of ["session_start"'))
assert.ok(harness.includes("function harness("))
const scenario = `
const h = harness("audit-provenance"); h.ctx.hasUI = false;
await h.command("10"); await h.save("PRIVATE_SECRET checkpoint A"); await h.save("PRIVATE_SECRET checkpoint B");
const proposal = h.boundary().entries.at(-1).details;
h.fire("turn_start");
h.handlers.get("context_with_system")({ messages: [{ role: "custom", customType: "unattended-continuation", details: proposal, content: "PRIVATE_SECRET" }] }, h.ctx);
h.boundary("turn_end");
return h.branch().filter(e => ["checkpoint-provenance", "unattended-continuation", "continuation-provenance"].includes(e.customType));`
const transpiler = new Bun.Transpiler({ loader: "ts", target: "bun" })
const execute = new Function("handoff", "assert", "repo", "sessions", transpiler.transformSync(`return (async () => { ${harness} ${scenario} })()`))
// Extract the actual dispatch emitter and native usage observer, with no Agent call.
const dispatchSource = await readFile(join(repoRoot, "home/private_dot_pi/private_agent/private_extensions/fast-task-dispatch.ts"), "utf8")
const reasonMatch = dispatchSource.match(/export const REASONS = (\[[^\n]+\]) as const/)
assert.ok(reasonMatch)
const reasons = JSON.parse(reasonMatch[1])
const dispatchEvents: any[] = [{ type: "session", timestamp: ts }]
let clock = 1714651800000
const attempt = { schemaVersion: 1, coordinatorSessionId: "session01", taskId: "board-1", attemptId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", workerId: "worker01-aaaa", phase: "implementation", state: "ready", timestamp: clock, reason: "eligible", requestedModel: "p/requested", requestedEffort: "medium" }
const chunk = dispatchSource.slice(dispatchSource.indexOf("  const emit ="), dispatchSource.indexOf("  const restore ="))
assert.ok(chunk.includes('actualSource = "subagents:usage"'))
const makeDispatch = new Function("pi", "attempts", "context", "TYPE", "object", "label", "route", "EFFORTS", "active", "Date", "terminal",
  transpiler.transformSync(chunk + "\nreturn { emit, observe }"))
const dispatch = makeDispatch({ appendEntry: (customType: string, data: any) => dispatchEvents.push({ type: "custom", customType, data, timestamp: ts }) },
  new Map([[attempt.taskId, attempt]]), {}, "fast-task-dispatch", (x: any) => !!x && typeof x === "object" && !Array.isArray(x), /^[A-Za-z0-9_./:@+-]{1,128}$/, /^[A-Za-z0-9_.:@+-]+\/[A-Za-z0-9_./:@+-]+$/, ["off", "minimal", "low", "medium", "high", "xhigh", "max"],
  (a: any) => ["submitted", "started"].includes(a.state), { now: () => clock },
  new Function(transpiler.transformSync(dispatchSource.match(/^const terminal = .*$/m)![0] + "\nreturn terminal"))())
dispatch.emit(attempt, "ready", "eligible"); clock += 5
dispatch.emit(attempt, "ready", "reserved"); clock += 15
dispatch.emit(attempt, "submitted", "native_submission"); clock += 30
dispatch.observe("started", { id: attempt.workerId, prompt: "PRIVATE_SECRET" })
clock += 7
dispatch.emit(attempt, "started", "worker_linked"); clock += 8
dispatch.observe("usage", { id: attempt.workerId, model: "p/actual", thinking: "high", secret: "PRIVATE_SECRET" })
const transitionBase = dispatchEvents.slice()
const beforeCases = dispatchEvents.length
const timingAttempt = (taskId: string) => ({ ...attempt, taskId, attemptId: randomUUID(), actualModel: undefined, actualEffort: undefined, actualSource: undefined })
let t = timingAttempt("reservation-only")
clock += 10; dispatch.emit(t, "ready", "reserved")
clock += 10; dispatch.emit(t, "submitted", "native_submission")
clock += 40; dispatch.emit(t, "started", "native_started")
t = timingAttempt("inverted")
clock = 1714651800300; dispatch.emit(t, "ready", "eligible")
clock -= 10; dispatch.emit(t, "submitted", "native_submission")
clock -= 10; dispatch.emit(t, "started", "native_started")
t = timingAttempt("ambiguous-ready")
clock += 40; dispatch.emit(t, "ready", "eligible")
clock += 10; dispatch.emit(t, "ready", "eligible")
clock += 10; dispatch.emit(t, "submitted", "native_submission")
clock += 10; dispatch.emit(t, "started", "native_started")
const timingRows = [...transitionBase, ...dispatchEvents.splice(beforeCases)]
const timingRoot = join(root, "..", "transition-coverage")
await mkdir(timingRoot)
await writeFile(join(timingRoot, "c.jsonl"), timingRows.map(e => JSON.stringify(e)).join("\n") + "\n")
// Conflicting native usage/request effort observations must not become a comparison.
const beforeEffort = dispatchEvents.length
const conflicting: any = timingAttempt("effort-conflict")
dispatch.emit(conflicting, "submitted", "native_submission")
conflicting.requestedEffort = "low"; conflicting.actualSource = "subagents:usage"; conflicting.actualEffort = "high"
dispatch.emit(conflicting, "started", "runtime_observed")
conflicting.actualEffort = "low"; dispatch.emit(conflicting, "started", "runtime_observed")
const unverified: any = timingAttempt("effort-unverified")
delete unverified.requestedEffort
unverified.actualEffort = "max"; unverified.actualSource = "PRIVATE_SECRET"
dispatch.emit(unverified, "submitted", "native_submission")
const effortRows = [...transitionBase, ...dispatchEvents.splice(beforeEffort)]
const effortRoot = join(root, "..", "effort-coverage")
await mkdir(effortRoot)
await writeFile(join(effortRoot, "c.jsonl"), effortRows.map(e => JSON.stringify(e)).join("\n") + "\n")
// Terminal callback supplies native evidence, but still no causal refill pair.
clock += 10; dispatch.observe("completed", { id: attempt.workerId, durationMs: 999, status: "completed" })
for (const reason of reasons) {
  const blocked: any = { ...attempt, taskId: "blocked-" + reason, attemptId: randomUUID() }
  for (const k of ["actualModel", "actualEffort", "actualSource"]) delete blocked[k]
  dispatch.emit(blocked, "blocked", reason)
}
// Unknown reason stays unknown, never leaks a novel token into distribution keys.
dispatchEvents.push({ ...dispatchEvents.at(-1), data: { ...dispatchEvents.at(-1).data, reason: "PRIVATE_SECRET" } })
const dispatchRoot = join(root, "..", "actual-dispatch-only")
await mkdir(dispatchRoot)
await writeFile(join(dispatchRoot, "dispatch.jsonl"), dispatchEvents.map(e => JSON.stringify(e)).join("\n") + "\n")
await writeFile(join(root, "expected-reasons.json"), JSON.stringify(reasons))
// Exercise the entire actual module for live callbacks and durable-record recovery.
const { default: nativeDispatch } = await jiti.import(join(repoRoot, "home/private_dot_pi/private_agent/private_extensions/fast-task-dispatch.ts"))
const nativeRows: any[] = [{ type: "session", timestamp: ts }]
const nativeCase = (id: string, phase: string, raw: any, recovered = false, failed = false) => {
  const handlers: any = {}, listeners: any = {}
  const seeded = { ...attempt, taskId: id, attemptId: randomUUID(), workerId: "worker-" + id, phase, state: "submitted", reason: "native_submission" }
  for (const key of ["nativeStatus", "nativeSource", "nativeDurationMs", "actualModel", "actualEffort", "actualSource"]) delete seeded[key]
  const entries = [{ type: "custom", customType: "fast-task-dispatch", data: seeded }]
  if (recovered) entries.push({ type: "custom", customType: "subagents:record", data: { ...raw, id: seeded.workerId } })
  nativeDispatch({ on: (name: string, fn: any) => handlers[name] = fn,
    events: { on: (name: string, fn: any) => { listeners[name] = fn; return () => {} } }, registerTool() {},
    appendEntry: (customType: string, data: any) => nativeRows.push({ type: "custom", customType, data, timestamp: ts }) } as never)
  handlers.session_start({}, { getSystemPrompt: () => "coordinator", sessionManager: { getEntries: () => entries } })
  if (!recovered) listeners[failed ? "subagents:failed" : "subagents:completed"]({ ...raw, id: seeded.workerId, secret: "PRIVATE_SECRET" })
  handlers.session_shutdown()
  return nativeRows.at(-1)
}
// Additional actual-producer boundary assertions, kept out of the summary population.
for (const durationMs of [-1, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
  const bad = nativeCase("boundary", "implementation", { status: "PRIVATE_SECRET", durationMs, startedAt: 0.5, completedAt: Infinity })
  assert.equal(bad.data.nativeDurationMs, undefined); assert.equal(bad.data.nativeStatus, undefined)
  assert.equal(bad.data.nativeStartedAt, undefined); assert.equal(bad.data.nativeCompletedAt, undefined)
  nativeRows.pop()
}
const completedOnly = nativeCase("completed-only", "review", { status: "completed", completedAt: 5000, durationMs: 99 }, true)
assert.equal(completedOnly.data.nativeCompletedAt, 5000); assert.equal(completedOnly.data.nativeStartedAt, undefined)
assert.equal(completedOnly.data.nativeDurationMs, undefined)
nativeRows.pop()
const live = nativeCase("live", "implementation", { status: "completed", durationMs: 120, startedAt: 1000, completedAt: 1120 })
assert.equal(live.data.nativeDurationMs, 120); assert.equal(live.data.observationSource, "live")
nativeRows.push({ ...live }, { ...live, data: { ...live.data, timestamp: live.data.timestamp + 1 } })
const recovered = nativeCase("recovered", "review", { status: "completed", startedAt: 2000, completedAt: 2250, durationMs: 999999 }, true)
assert.equal(recovered.data.nativeDurationMs, 250); assert.equal(recovered.data.nativeSource, "subagents:record")
assert.equal(recovered.data.observationSource, "recovered")
nativeCase("failed", "repair", { status: "error", durationMs: 0 }, false, true)
const missing = nativeCase("missing", "review", { status: "completed", startedAt: 3000, durationMs: 999 }, true)
assert.equal(missing.data.nativeDurationMs, undefined); assert.equal(missing.data.nativeCompletedAt, undefined)
const invalid = nativeCase("invalid", "implementation", { status: "PRIVATE_SECRET", durationMs: -1, startedAt: 1.5, completedAt: -2 })
assert.equal(invalid.data.nativeStatus, undefined); assert.equal(invalid.data.nativeDurationMs, undefined)
const reversed = nativeCase("reversed", "repair", { status: "aborted", startedAt: 5000, completedAt: 4000 }, true)
assert.equal(reversed.data.nativeCompletedAt, undefined); assert.equal(reversed.data.nativeDurationMs, undefined)
const conflict = nativeCase("conflict", "repair", { status: "completed", durationMs: 400 })
nativeRows.push({ ...conflict, data: { ...conflict.data, nativeDurationMs: 401 } })
// Historical v1 evidence lacks observation/native provenance: never assume live.
nativeRows.push({ ...missing, data: { ...missing.data, taskId: "legacy", attemptId: randomUUID(), observationSource: undefined, nativeSource: undefined, nativeStatus: undefined, nativeStartedAt: undefined, nativeDurationMs: 888 } })
// Corrupt persisted additive fields stay bounded, without throwing away the event.
nativeRows.push({ ...missing, data: { ...missing.data, taskId: "corrupt", attemptId: randomUUID(), observationSource: "PRIVATE_SECRET", nativeSource: "PRIVATE_SECRET", nativeStatus: [], nativeDurationMs: "PRIVATE_SECRET", nativeStartedAt: -1, nativeCompletedAt: 8640000000000001 } })
nativeRows.push({ ...recovered, data: { ...recovered.data, taskId: "record-no-pair", attemptId: randomUUID(), nativeStartedAt: undefined, nativeCompletedAt: undefined, nativeDurationMs: 999 } })
// Same identities as live native evidence, but a deliberately different coordinator claim.
nativeRows.push({ type: "custom", customType: "task-outcome-receipt", timestamp: ts, data: validateReceipt({ taskId: live.data.workerId, boardTaskId: live.data.taskId, attemptId: live.data.attemptId, phase: "implementation", outcome: "accepted", model: "p/m", effort: "medium", checkArtifact: "check.md", coordinatorReportedDurationMs: 9000 }) })
const nativeRoot = join(root, "..", "native-lifecycle")
await mkdir(nativeRoot)
await writeFile(join(nativeRoot, "c.jsonl"), nativeRows.map(e => JSON.stringify(e)).join("\n") + "\n")
const { NestedCallRecorder } = await import(join(runtime, "dist/core/nested-tool-calls.js"))
const recorder = new NestedCallRecorder()
const record = recorder.start({ id: "nested-error", name: "TaskGet", arguments: { secret: "PRIVATE_SECRET" } })
recorder.finish(record, true, "")
assert.equal(recorder.snapshot().calls[0].status, "error")
assert.equal(recorder.snapshot().calls[0].error, undefined)
events.push({ type: "message", timestamp: ts, message: { role: "toolResult", toolName: "codemode", nestedCalls: recorder.snapshot() } })
const continuity = await execute(handoff, assert, root, join(root, "private-checkpoints"))
assert.equal(continuity.filter((e: any) => e.data?.phase === "consumed").length, 1)
for (const e of continuity) events.push({ ...e, timestamp: ts })
// Replayed evidence must not double count; legacy and malformed entries remain unknown/invalid.
events.push(...continuity.map((e: any) => ({ ...e, timestamp: ts })))
events.push({ type: "custom_message", customType: "unattended-continuation", timestamp: ts, content: "PRIVATE_SECRET legacy" })
events.push({ type: "custom", customType: "checkpoint-provenance", timestamp: ts, data: { schemaVersion: 1, phase: "write-success", checkpointId: "PRIVATE_SECRET" } })
// Actual cache publication can discard a hit when a reset is crossed below TTL.
const { QuotaCache } = await jiti.import(join(repoRoot, "home/private_dot_pi/private_agent/private_extensions/quota-status/cache.ts"))
let quotaClock = 1714651800000
const cache = new QuotaCache(() => quotaClock)
cache.write("account", { provider: "openai", capturedAt: quotaClock - 1000, status: "fresh", windows: [{ resetsAt: (quotaClock + 500) / 1000 }], secret: "PRIVATE_SECRET" })
const hit = cache.read("account")
assert.equal(hit.cache.hit, true)
const usable = cache.publish(hit, { provider: "openai", status: "unknown" })
quotaClock += 1000
const discarded = cache.publish(hit, { provider: "openai", status: "unknown", windows: [] })
assert.equal(discarded.cache.hit, true); assert.equal(discarded.status, "unknown")
assert.ok(discarded.cache.ageMs < discarded.cache.ttlMs)
const quotaRows: any[] = [{ type: "session", timestamp: ts }]
for (const [value, at] of [[usable, 1714651800000], [discarded, quotaClock]] as any[]) {
  projectQuota({ appendEntry: (customType: string, data: any) => quotaRows.push({ type: "custom", customType, data, timestamp: new Date(at).toISOString() }) },
    { providers: [value], codexbarCredits: { capturedAt: null } }, at, at - 10, {})
  quotaRows.push({ type: "message", timestamp: new Date(at).toISOString(), message: { role: "toolResult", toolName: "quota_status", isError: false, details: { providers: [value], secret: "PRIVATE_SECRET" } } })
}
quotaRows.push({ type: "message", timestamp: ts, message: { role: "toolResult", toolName: "quota_status", isError: false, details: { providers: [{ provider: "anthropic", status: "PRIVATE_SECRET", cache: "PRIVATE_SECRET" }, { provider: "opencode", status: "unknown", capturedAt: null }] } } })
const quotaRoot = join(root, "..", "quota-publication")
await mkdir(quotaRoot)
await writeFile(join(quotaRoot, "c.jsonl"), quotaRows.map(e => JSON.stringify(e)).join("\n") + "\n")
// Actual receipt validation plus the same worker-file identity: two IDs collide.
const collisionRoot = join(root, "..", "prefix-collision")
await mkdir(collisionRoot)
const collisionParent = join(collisionRoot, "c.jsonl")
const collisionRows = [{ type: "session", timestamp: ts }, ...["worker01-aaaa", "worker01-bbbb"].map(taskId => ({ type: "custom", customType: "task-outcome-receipt", timestamp: ts,
  data: validateReceipt({ taskId, boardTaskId: taskId, attemptId: taskId, phase: "implementation", outcome: "accepted", model: "p/m", effort: "medium", checkArtifact: "check.md" }) }))]
await writeFile(collisionParent, collisionRows.map(e => JSON.stringify(e)).join("\n") + "\n")
const workerRows = (await readFile(join(root, "worker01-aaaa.jsonl"), "utf8")).trim().split("\n").map(JSON.parse)
workerRows[0].parentSession = collisionParent
await writeFile(join(collisionRoot, "worker.jsonl"), workerRows.map(e => JSON.stringify(e)).join("\n") + "\n")
await writeFile(coordinator, events.map(e => JSON.stringify(e)).join("\n") + "\n")
TS
"$SCRIPT" --sessions-dir "$AUDIT_FIXTURE_ROOT" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/shaped.json"
jq -e '
  .retrospective.board_attempt_outcomes as $b | .future_evidence.accepted_board_task_cost as $c
  | .future_evidence.checkpoint_parent_identity as $p
  | $b.explicit_board_attempt_worker_groups == 7 and $b.board_tasks == 7
  and $b.receipt_outcomes_deduplicated == {accepted:6,reworked:1,rejected:1}
  and $b.phases == {implementation:6,repair:1} and $b.parent_link_present == 1
  and $b.receipt_to_dispatch == {no_dispatch:7,missing_receipt_ids:1}
  and $c.available and $c.accepted_board_tasks == 6 and $c.tasks_with_observed_cost == 2
  and $c.observed_cost_total == 3.5 and $c.valid_cost_samples == 4 and $c.duplicate_worker_events_excluded == 1
  and $c.components == {observed:4,no_worker_session:1,mixed_or_unknown_model:1,reused_worker_or_shared_component:2}
  and $c.missing_or_invalid_cost_samples == 2 and $c.outside_window_assistant_messages == 7
  and $c.phases == {implementation:6,review:1,repair:1}
  and $p.successful_writes == 2 and $p.proposals == 1 and $p.consumed == 1
  and $p.consumption_links == {exact_parent:1} and $p.legacy_unknown == 1 and $p.invalid_metadata == 1
  and $p.accepted_usefulness.available == false
  and .quota_cache.providers.openai.hit == 1 and .quota_cache.providers.anthropic.unknown == 1
  and .quota_cache.providers.codexbarCredits.unknown == 1 and .quota_cache.fetch_duration_ms.p50 == 20
  and .future_evidence.policy_receipts.valid == 1
  and .retrospective.phase_duration_claims_ms.by_phase.implementation.p50 == 500
  and .retrospective.phase_duration_claims_ms.by_phase.repair.p50 == 1234
  and .retrospective.phase_duration_claims_ms.by_phase.review.p50 == 250
  and .retrospective.phase_duration_claims_ms.measured_native_duration_ms.available == false
  and .observability.nested_typed_calls.TaskGet.errors == 1
' "$tmp_root/shaped.json" >/dev/null || { jq '.retrospective.board_attempt_outcomes,.future_evidence,.quota_cache' "$tmp_root/shaped.json"; exit 1; }
if grep -E 'PRIVATE_SECRET|worker01|board-1|attempt-worker|audit-provenance' "$tmp_root/shaped.json"; then
  echo 'producer-shaped output leaked private evidence' >&2; exit 1
fi

# Actual producer allowlist must match the audit's bounded distribution exactly.
"$SCRIPT" --sessions-dir "$tmp_root/actual-dispatch-only" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/actual-dispatch.json"
jq -e --slurpfile reasons "$AUDIT_FIXTURE_ROOT/expected-reasons.json" '
  .dispatch_lifecycle as $d
  | ($d.blocked_reasons | keys) == (($reasons[0] + ["unknown"]) | sort)
  and all($d.blocked_reasons[]; . == 1)
  and $d.ready_to_submitted_ms.p50 == 20 and $d.submitted_to_started_ms.p50 == 30
  and $d.provenance.actual_model == {"p/actual":1} and $d.provenance.actual_effort == {high:1}
  and $d.provenance.requested_vs_actual_effort == {"requested=medium actual=high":1}
  and $d.native_evidence.duration_ms == {count:1,p50:999,p90:999}
  and $d.native_evidence.observation_sources == {live:1}
  and $d.native_evidence.native_timestamp_pairs == 0
  and $d.rolling_refill.completion_to_replacement_start_ms.available == false
  and $d.rolling_refill.submission_reaction_ms.available == false
  and $d.rolling_refill.unpaired_event_coverage == {terminal_observations:1,terminal_live_or_recovered_unknown:0,designated_start_observations:1,designated_submission_observations:1,causally_paired:0}
' "$tmp_root/actual-dispatch.json" >/dev/null
if grep -q PRIVATE_SECRET "$tmp_root/actual-dispatch.json"; then echo 'actual dispatch projection leaked metadata' >&2; exit 1; fi

"$SCRIPT" --sessions-dir "$tmp_root/native-lifecycle" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/native-lifecycle.json"
jq -e '.dispatch_lifecycle.native_evidence as $n
  | $n.terminal_attempts == 10 and $n.duration_coverage == {measured:3,without_duration:4,conflicting:1,unknown_source:2}
  and $n.duration_ms == {count:3,p50:120,p90:250}
  and $n.by_phase.implementation == {count:1,p50:120,p90:120}
  and $n.by_phase.review == {count:1,p50:250,p90:250}
  and $n.by_phase.repair == {count:1,p50:0,p90:0}
  and $n.by_source["subagents:record"] == {count:1,p50:250,p90:250}
  and $n.by_source["subagents:completed"].p50 == 120 and $n.by_source["subagents:failed"].p50 == 0
  and $n.by_observation_source.live == {count:2,p50:0,p90:120}
  and $n.by_observation_source.recovered == {count:1,p50:250,p90:250}
  and $n.status_attempts == 9 and $n.terminal_observations == 13
  and $n.native_timestamp_pairs == 2 and $n.duplicate_observations_excluded == 1
  and $n.observation_sources == {live:7,recovered:4,unknown:2}
  and $n.status == {completed:4,error:1,aborted:1,unknown:3}
  and $n.invalid_supplied_fields == 8
  and .retrospective.phase_duration_claims_ms.by_phase.implementation.p50 == 9000
  and .retrospective.phase_duration_claims_ms.measured_native_duration_ms == $n
  and .dispatch_lifecycle.first_token_ms.available == false
  and .dispatch_lifecycle.rolling_refill.occupancy.available == false
  and .dispatch_lifecycle.rolling_refill.unpaired_event_coverage.causally_paired == 0' "$tmp_root/native-lifecycle.json" >/dev/null || { jq '.dispatch_lifecycle.native_evidence,.retrospective.phase_duration_claims_ms' "$tmp_root/native-lifecycle.json"; exit 1; }
if grep -q PRIVATE_SECRET "$tmp_root/native-lifecycle.json"; then echo 'native evidence privacy failure' >&2; exit 1; fi

"$SCRIPT" --sessions-dir "$tmp_root/quota-publication" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/quota-publication.json"
jq -e '.quota_cache | .providers.openai.hit == 2
  and .typed_results.results == 3 and .typed_results.rows == 4
  and .typed_results.status == {fresh:1,unknown:2,unknown_status:1}
  and .typed_results.reuse == {usable_reuse:1,discarded_or_unusable_reuse:1,cache_unknown:2}
  and .typed_results.cache_bounds_at_result.within_ttl_no_observed_reset == 2
  and .typed_result_linkage.available == false and .typed_results.discard_cause.available == false' "$tmp_root/quota-publication.json" >/dev/null
"$SCRIPT" --sessions-dir "$tmp_root/prefix-collision" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/collision.json"
jq -e '.retrospective.board_attempt_outcomes.receipt_to_worker_session == {ambiguous:2}
  and .future_evidence.accepted_board_task_cost.components == {ambiguous_worker:2}
  and .future_evidence.accepted_board_task_cost.observed_cost_total == null' "$tmp_root/collision.json" >/dev/null
if grep -q PRIVATE_SECRET "$tmp_root/quota-publication.json" "$tmp_root/collision.json"; then echo 'typed metric privacy failure' >&2; exit 1; fi

"$SCRIPT" --sessions-dir "$tmp_root/transition-coverage" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/transitions.json"
jq -e '.dispatch_lifecycle | .attempts == 4
  and .ready_to_submitted_ms == {count:1,p50:20,p90:20,attempts:4,unknown:2,inverted:1}
  and .submitted_to_started_ms == {count:3,p50:30,p90:40,attempts:4,unknown:0,inverted:1}' "$tmp_root/transitions.json" >/dev/null
"$SCRIPT" --sessions-dir "$tmp_root/effort-coverage" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/effort.json"
jq -e '.dispatch_lifecycle.provenance | .effort_coverage == {attempts:3,requested:{known:1,ambiguous:1,unknown:1},actual:{known:1,ambiguous:1,unknown:1},comparable:1}
  and .requested_effort == {medium:1} and .actual_effort == {high:1}
  and .requested_vs_actual_effort == {"requested=medium actual=high":1}' "$tmp_root/effort.json" >/dev/null
if grep -q PRIVATE_SECRET "$tmp_root/effort.json"; then echo 'unverified effort source leaked' >&2; exit 1; fi

# Negative cases mutate *emitted* provenance, retaining producer field names.
continuity_negative="$tmp_root/continuity-negative"
mkdir -p "$continuity_negative"
jq -sc '
  [ .[] | select(.customType == "checkpoint-provenance" or .customType == "continuation-provenance" or .customType == "unattended-continuation") ] as $all
  | ($all | map(select(.data.phase == "consumed")) | first) as $c
  | ($all | map(select(.details.phase == "proposal")) | first) as $p
  | ($all | map(select(.data.checkpointId == $c.data.parentCheckpointId)) | first) as $w
  | {type:"session",timestamp:"2024-05-02T12:00:00Z"},
    ($w | .timestamp = "2024-05-02T12:12:00Z"), $p, $c,
    ($c | .data.continuationId = "11111111-1111-1111-1111-111111111111"),
    ($p | .details.continuationId = "22222222-2222-2222-2222-222222222222"),
    ($c | .data.continuationId = "33333333-3333-3333-3333-333333333333" | del(.data.parentCheckpointId))
' "$AUDIT_FIXTURE_ROOT/c.jsonl" > "$continuity_negative/a.jsonl"
"$SCRIPT" --sessions-dir "$continuity_negative" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json |
  jq -e '.future_evidence.checkpoint_parent_identity | .consumed == 3
    and .consumption_links == {inverted:1,missing_or_ambiguous_evidence:1,parent_unavailable:1}
    and .proposals_without_consumption == 1 and .accepted_usefulness.available == false' >/dev/null
# A write outside the requested period cannot satisfy an in-period consumption.
sed 's/2024-05-02T12:12:00Z/2024-05-02T11:59:00Z/' "$continuity_negative/a.jsonl" > "$tmp_root/negative.jsonl"
mv "$tmp_root/negative.jsonl" "$continuity_negative/a.jsonl"
"$SCRIPT" --sessions-dir "$continuity_negative" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json |
  jq -e '.future_evidence.checkpoint_parent_identity | .successful_writes == 0
    and .consumption_links.missing_or_ambiguous_evidence == 2' >/dev/null

# Proposed dispatch compatibility only: derive join keys from actual emitted receipts.
jq -sc '[.[] | select(.customType == "task-outcome-receipt" and .data.boardTaskId == "board-1")][0]
  | {type:"custom",customType:"fast-task-dispatch",timestamp:.timestamp,
     data:{schemaVersion:1,coordinatorSessionId:"session01",taskId:.data.boardTaskId,attemptId:.data.attemptId,
           workerId:.data.taskId,phase:.data.phase,state:"started",timestamp:1714651800000,reason:"PRIVATE_SECRET"}}
  | ., .,
    (.data.taskId = "unreceipted-repair" | .data.attemptId = "unreceipted-attempt" | del(.data.workerId)
      | .data.parentTaskId = "board-1" | .data.phase = "repair"),
    (.data.phase = "PRIVATE_SECRET")
' "$AUDIT_FIXTURE_ROOT/c.jsonl" >> "$tmp_root/dispatch-compat.jsonl"
cat "$tmp_root/dispatch-compat.jsonl" >> "$AUDIT_FIXTURE_ROOT/c.jsonl"
"$SCRIPT" --sessions-dir "$AUDIT_FIXTURE_ROOT" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/compat.json"
jq -e '.retrospective.board_attempt_outcomes.receipt_to_dispatch.joined == 1
  and .retrospective.board_attempt_outcomes.dispatch_attempts_with_joined_receipt == 1
  and .future_evidence.accepted_board_task_cost.observed_cost_total == 3.5
  and .future_evidence.accepted_board_task_cost.components.worker_id_unavailable == 1
  and .dispatch_lifecycle.rejected_events == 1' "$tmp_root/compat.json" >/dev/null
if grep -q PRIVATE_SECRET "$tmp_root/compat.json"; then echo 'dispatch compatibility leaked metadata' >&2; exit 1; fi

# Missing-agent classes never search the enclosing codemode text a second time.
metrics="$tmp_root/remaining-metrics"
mkdir -p "$metrics"
cat > "$metrics/c.jsonl" <<'EOF'
{"type":"session","timestamp":"2024-05-02T12:00:00Z"}
{"type":"message","timestamp":"2024-05-02T11:59:59Z","message":{"role":"assistant","content":[{"type":"toolCall","id":"before","name":"Agent","arguments":{"resume":"METRIC_SECRET"}}]}}
{"type":"message","id":"m1","timestamp":"2024-05-02T12:01:00Z","message":{"role":"assistant","usage":{"output":10,"reasoning":4},"content":[{"type":"toolCall","id":"get","name":"get_subagent_result","arguments":{"agent_id":"METRIC_SECRET"}},{"type":"toolCall","id":"resume","name":"Agent","arguments":{"resume":"METRIC_SECRET"}},{"type":"toolCall","id":"fresh","name":"Agent","arguments":{}}]}}
{"type":"message","timestamp":"2024-05-02T12:01:01Z","message":{"role":"toolResult","toolName":"get_subagent_result","toolCallId":"get","content":[{"type":"text","text":"Agent not found: METRIC_SECRET"}]}}
{"type":"message","timestamp":"2024-05-02T12:01:02Z","message":{"role":"toolResult","toolName":"Agent","toolCallId":"resume","isError":false,"content":[{"type":"text","text":"Agent not found: METRIC_SECRET. It may have been cleaned up."}]}}
{"type":"message","timestamp":"2024-05-02T12:01:02Z","message":{"role":"toolResult","toolName":"Agent","toolCallId":"fresh","content":[{"type":"text","text":"Agent not found: METRIC_SECRET"}]}}
{"type":"message","timestamp":"2024-05-02T12:01:02Z","message":{"role":"toolResult","toolName":"Agent","toolCallId":"before","content":[{"type":"text","text":"Agent not found: METRIC_SECRET"}]}}
{"type":"message","timestamp":"2024-05-02T12:01:02Z","message":{"role":"toolResult","toolName":"Agent","toolCallId":"unknown","content":[{"type":"text","text":"Agent not found: METRIC_SECRET"}]}}
{"type":"message","timestamp":"2024-05-02T12:01:03Z","message":{"role":"toolResult","toolName":"codemode","content":[{"type":"text","text":"Agent not found: METRIC_SECRET Agent not found: METRIC_SECRET"}],"nestedCalls":{"complete":false,"calls":[{"name":"get_subagent_result","status":"error","error":"Nested agent not found or not owned by this parent: METRIC_SECRET"},{"name":"get_subagent_result","status":"ok"},{"name":"get_subagent_result","status":"error"},{"name":"get_subagent_result","status":"unfinished"},{"name":"Agent","status":"error","arguments":{"resume":"METRIC_SECRET"},"error":"Agent not found: METRIC_SECRET"},{"name":"Agent","status":"error","argumentsBytes":50000,"error":"Agent not found: METRIC_SECRET"}]}}}
{"type":"custom_message","customType":"subagent-notification","timestamp":"2024-05-02T12:02:00Z","content":"<task-id>metric01-aaaa</task-id><status>done</status><result>METRIC_SECRET</result>"}
{"type":"custom_message","customType":"subagent-notification","timestamp":"2024-05-02T12:02:00Z","content":"<task-id>metric01-aaaa</task-id><status>done</status><result>METRIC_SECRET</result>"}
{"type":"message","id":"m2","timestamp":"2024-05-02T12:02:02Z","message":{"role":"assistant","usage":{"output":20},"content":[]}}
{"type":"message","id":"m3","timestamp":"2024-05-02T12:02:05Z","message":{"role":"assistant","usage":{"output":0,"reasoning":0},"content":[{"type":"toolCall","name":"Agent","arguments":{}}]}}
{"type":"custom","customType":"subagents:record","timestamp":"2024-05-02T12:03:00Z","data":{"id":"metric01-aaaa","status":"completed","completedAt":1714651319000,"result":"METRIC_SECRET"}}
{"type":"custom","customType":"subagents:record","timestamp":"2024-05-02T12:03:00Z","data":{"id":"metric01-aaaa","status":"completed","completedAt":1714651319000}}
{"type":"custom_message","customType":"subagent-notification","timestamp":"2024-05-02T12:04:00Z","content":"<task-id>metric02-aaaa</task-id><status>done</status>"}
{"type":"message","id":"m4","timestamp":"2024-05-02T12:03:59Z","message":{"role":"assistant","usage":{"output":5,"reasoning":-1},"content":[{"type":"toolCall","name":"Agent","arguments":{}}]}}
{"type":"custom","customType":"subagents:record","timestamp":"2024-05-02T12:04:01Z","data":{"id":"metric02-aaaa","status":"completed","completedAt":1714651441000}}
{"type":"message","id":"m5","timestamp":"2024-05-02T12:05:00Z","message":{"role":"assistant","usage":{"output":2,"reasoning":3},"content":[]}}
{"type":"message","id":"m5","timestamp":"2024-05-02T12:05:00Z","message":{"role":"assistant","usage":{"output":2,"reasoning":3},"content":[]}}
{"type":"message","id":"m6","timestamp":"2024-05-02T12:06:00Z","message":{"role":"assistant","usage":{"output":"bad","reasoning":2},"content":[]}}
{"type":"message","id":"m7","timestamp":"2024-05-02T12:07:00Z","message":{"role":"assistant","usage":{"reasoning":null},"content":[]}}
{"type":"custom_message","customType":"subagent-notification","timestamp":"2024-05-02T12:59:59Z","content":"<task-id>metric03-aaaa</task-id><status>done</status>"}
{"type":"message","timestamp":"2024-05-02T13:00:01Z","message":{"role":"assistant","usage":{"reasoning":999,"output":999},"content":[{"type":"toolCall","name":"Agent","arguments":{}}]}}
EOF
# Same task identity in a different file must not supply the missing completion or next event.
cat > "$metrics/w.jsonl" <<'EOF'
{"type":"session","timestamp":"2024-05-02T12:00:00Z","parentSession":"METRIC_SECRET"}
{"type":"session_info","timestamp":"2024-05-02T12:00:00Z","name":"implementer#worker01"}
{"type":"custom","customType":"subagents:record","timestamp":"2024-05-02T12:59:59Z","data":{"id":"metric03-aaaa","status":"completed","completedAt":1714654799000}}
{"type":"message","timestamp":"2024-05-02T13:00:00Z","message":{"role":"assistant","usage":{"output":8,"reasoning":2},"content":[]}}
EOF
"$SCRIPT" --sessions-dir "$metrics" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json > "$tmp_root/metrics.json"
jq -e '.missing_agent_failures as $f | .notification_timing as $t | .reasoning_tokens.by_role as $r
  | $f.direct_retrieval == {attempts:1,results:1,missing_agent:1}
  and $f.agent_resume == {attempts:1,results:2,missing_agent:2}
  and $f.nested_codemode_retrieval == {attempts:4,results:3,missing_agent:1,unfinished_or_unknown:1,errors_without_text:1}
  and $f.nested_agent_resume == {attempts:1,results:1,missing_agent:1,unfinished_or_unknown:0,errors_without_text:0}
  and $f.coverage == {resume_arguments_unavailable:1,unjoined_agent_results:1,incomplete_nested_records:1}
  and $t.notifications == 3 and $t.duplicate_notifications_excluded == 1
  and $t.completed_to_notification_ms == {count:1,p50:1000,p90:1000,denominator_notifications:3,coverage:{measured:1,inverted:1,missing_completion:1},denominator_completion_tasks:3,right_censored_completion_tasks:1}
  and $t.notification_to_next.assistant_ms == {count:1,p50:2000,p90:2000,denominator_notifications:3,coverage:{measured:1,inverted:1,right_censored:1}}
  and $t.notification_to_next.Agent_ms == {count:1,p50:5000,p90:5000,denominator_notifications:3,coverage:{measured:1,inverted:1,right_censored:1}}
  and $r.nonworker_coordinators == {assistant_messages:7,duplicate_events_excluded:1,reasoning_valid:4,reasoning_missing:1,reasoning_invalid:2,
    output_valid:5,output_missing:1,output_invalid:1,reasoning_tokens:9,output_tokens:37,comparable_messages:2,comparable_reasoning_tokens:4,
    comparable_output_tokens:10,reasoning_exceeds_output:1,noncomparable_messages:5,output_share:0.4}
  and $r["worker/implementer"].output_share == 0.25 and $r["worker/implementer"].assistant_messages == 1
' "$tmp_root/metrics.json" >/dev/null || { jq '.missing_agent_failures,.notification_timing,.reasoning_tokens' "$tmp_root/metrics.json"; exit 1; }
"$SCRIPT" --sessions-dir "$metrics" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z > "$tmp_root/metrics.txt"
if grep -E 'METRIC_SECRET|metric0[123]|worker01' "$tmp_root/metrics.json" "$tmp_root/metrics.txt"; then echo 'new metrics leaked payload or task identity' >&2; exit 1; fi
# A conflicting completion is unknown, never silently first/last; zero output has no share.
jq -nc '{type:"custom",customType:"subagents:record",timestamp:"2024-05-02T12:03:01Z",data:{id:"metric01-aaaa",status:"completed",completedAt:1714651318000}}' >> "$metrics/c.jsonl"
"$SCRIPT" --sessions-dir "$metrics" --since 2024-05-02T12:02:04Z --until 2024-05-02T12:02:05Z --json |
  jq -e '.reasoning_tokens.by_role.nonworker_coordinators | .comparable_messages == 1 and .output_share == null' >/dev/null
"$SCRIPT" --sessions-dir "$metrics" --since 2024-05-02T12:00:00Z --until 2024-05-02T13:00:00Z --json |
  jq -e '.notification_timing.completed_to_notification_ms | .count == 0 and .coverage.ambiguous_completion == 1' >/dev/null

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
