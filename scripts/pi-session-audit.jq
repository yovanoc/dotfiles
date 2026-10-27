def epoch:
  if type != "string" then null else
    try (
      capture("^(?<year>[0-9]{4})-(?<month>[0-9]{2})-(?<day>[0-9]{2})[Tt ](?<hour>[0-9]{2}):(?<minute>[0-9]{2}):(?<second>[0-9]{2})(?:\\.(?<fraction>[0-9]+))?(?<zone>[Zz]|[+-][0-9]{2}(?::?[0-9]{2})?)?$") as $t
      | ($t.year + "-" + $t.month + "-" + $t.day + "T" + $t.hour + ":" + $t.minute + ":" + $t.second
        | strptime("%Y-%m-%dT%H:%M:%S")) as $parts
      | ($parts | mktime) as $wall
      | if $parts[0] != ($t.year | tonumber)
          or ($wall | gmtime | .[0:6]) != ($parts[0:6]) then null
        else
          (if ($t.zone // "") == "" then
             $wall + ($wall - ($wall | localtime | mktime))
           elif ($t.zone | ascii_downcase) == "z" then $wall
           else
             ($t.zone | gsub(":"; "") | .[3:]) as $minutes
             | ($t.zone[1:3] | tonumber) as $hours
             | (if $minutes == "" then 0 else ($minutes | tonumber) end) as $minute_offset
             | if $hours > 23 or $minute_offset > 59 then null
               else
                 (($hours * 3600) + ($minute_offset * 60)) as $offset
                 | if (($t.zone[0:1]) == "-") then $wall + $offset else $wall - $offset end
               end
           end) as $seconds
          | if $seconds == null then null
            else $seconds + (if $t.fraction == null then 0 else ("0." + $t.fraction | tonumber) end)
            end
        end
    ) catch null
  end;

def safe_label:
  if type == "string" and test("^[A-Za-z0-9._:/@+-]{1,100}$") then . else "other" end;

# Fixed enum only: never emit error text or arbitrary extracted error codes.
def auth_category:
  if type != "string" then "unclassified"
  elif test("\\bapi_key_expired\\b"; "i") then "api_key_expired"
  elif test("\\b(invalid_api_key|authentication_error|unauthorized)\\b|(status|http|code)\\W{0,3}401\\b"; "i") then "authentication"
  elif test("\\b(permission_error|forbidden)\\b|(status|http|code)\\W{0,3}403\\b"; "i") then "permission"
  elif test("\\b(insufficient_quota|quota_exceeded|billing_error|credit balance)\\b"; "i") then "quota_or_billing"
  elif test("\\b(rate_limit|rate_limit_error|too many requests)\\b|rate limit|(status|http|code)\\W{0,3}429\\b"; "i") then "rate_limit"
  elif test("\\b(overloaded_error|overloaded|service unavailable)\\b|(status|http|code)\\W{0,3}(503|529)\\b"; "i") then "overloaded"
  elif test("\\b(context_length_exceeded|prompt is too long)\\b|context window|maximum context"; "i") then "context_overflow"
  elif test("\\b(etimedout|timeout|timed out)\\b"; "i") then "timeout"
  elif test("\\b(econnreset|econnrefused|enotfound|eai_again)\\b|fetch failed|socket hang up|network error"; "i") then "network"
  elif test("\\b(internal_server_error|server_error|api_error)\\b|(status|http|code)\\W{0,3}(500|502|504)\\b"; "i") then "server_error"
  else "unclassified" end;

def valid_task_id: type == "string" and test("^[A-Za-z0-9_-]{8,128}$");

def xml_field($tag):
  if type != "string" then null
  else ((capture("<" + $tag + ">(?<v>[^<]{1,128})</" + $tag + ">"; "i")? // null) | if . == null then null else .v end) end;

# subagents:record statuses use the same terminal classes as notification labels.
def record_status:
  if . == "completed" then "done"
  elif . == "steered" or . == "aborted" then "turn_limit"
  elif . == "stopped" then "stopped"
  elif . == "error" then "error"
  else null end;

def receipt_of:
  if type != "object" then null
  elif (.taskId | type) == "string" and (.taskId | test("^[A-Za-z0-9_./:@+-]{1,128}$"))
    and (.outcome | IN("accepted", "reworked", "rejected"))
    and (.model | type) == "string" and (.model | test("^[A-Za-z0-9_./:@+-]{1,128}$"))
    and (.effort | IN("off", "minimal", "low", "medium", "high", "xhigh", "max", "unknown"))
    and ((.checkArtifact | type) == "string" and (.checkArtifact | length) >= 1 and (.checkArtifact | length) <= 300
      and (.checkArtifact | test("[[:space:][:cntrl:]]") | not))
  then {taskId, outcome, model, effort, artifact: (.checkArtifact != null)}
  else null end;

# Managed checkpoint tools return details {path, cwd} (+ status for unattended_checkpoint).
def checkpoint_details_ok($status_required):
  type == "object" and (.path | type) == "string" and (.path | test("^/.{0,4094}\\.md$"))
  and (.cwd | type) == "string"
  and (($status_required | not) or (.status | IN("continue", "blocked", "done")));

def bump($key): .[$key] = ((.[$key] // 0) + 1);

def terminal_status:
  if type != "string" then null else
    (try (capture("<status>(?<value>[^<]{0,512})</status>"; "i").value | ascii_downcase | gsub("^\\s+|\\s+$"; "")) catch "") as $status
    | if $status == "done" or ($status | startswith("completed")) or ($status | startswith("finished")) then "done"
      elif ($status | startswith("wrapped up")) or ($status | startswith("aborted")) or ($status | startswith("turn limit")) or ($status | startswith("max turns")) then "turn_limit"
      elif ($status | startswith("stopped")) or ($status | startswith("cancelled")) or ($status | startswith("canceled")) then "stopped"
      elif ($status | startswith("error")) or ($status | startswith("failed")) then "error"
      else null end
  end;

def content_texts:
  if type == "string" then [.]
  elif type == "object" and (.text | type) == "string" then [.text]
  elif type == "array" then [.[] | select(type == "object" and (.text | type) == "string") | .text]
  else [] end;

def timeout_label($args):
  ($args.timeout) as $timeout
  | if (($args | has("timeout") | not)) or $timeout == null or $timeout == 0 or $timeout == false then "not_set"
    elif ($timeout | type) == "number" and $timeout > 0 then ($timeout | tostring)
    else "other" end;

def dispatch($args):
  .dispatch.max_turns |= bump(
    if $args.max_turns == null then "omitted"
    elif ($args.max_turns | type) == "number" and ($args.max_turns | floor) == $args.max_turns then ($args.max_turns | tostring)
    else "other" end
  )
  | .dispatch.model |= bump(if $args.model == null then "omitted" else ($args.model | safe_label) end)
  | .dispatch.thinking |= bump(if $args.thinking == null then "omitted" else ($args.thinking | safe_label) end)
  | .dispatch.background |= bump(
      if ($args.run_in_background | type) == "boolean" then ($args.run_in_background | tostring)
      elif $args.run_in_background == null then "omitted" else "other" end
    )
  | .dispatch.resume |= bump(
      if $args.resume == null or $args.resume == false or $args.resume == "" or $args.resume == 0 or $args.resume == [] or $args.resume == {} then "fresh" else "resumed" end
    );

def handle_block($block; $in_window):
  ($block.name) as $name
  | (if ($block.arguments | type) == "object" then $block.arguments else {} end) as $args
  | (if ($block.id | type) != "string" then .
     elif $name == "Agent" then
       .agent_calls[$block.id] = {
         model: (if $args.model == null then "omitted" else ($args.model | safe_label) end),
         effort: (if $args.thinking == null then "omitted" else ($args.thinking | safe_label) end)}
     elif $name == "unattended_checkpoint" or $name == "handoff_checkpoint" then .ckpt_calls[$block.id] = $name
     else . end)
  | if $name == "get_subagent_result" then
      (if ($block.id | type) == "string" then .calls[$block.id] = $args.agent_id else . end)
      | if $in_window then .retrieval.attempts += 1 else . end
    elif $in_window and $name == "unattended_checkpoint" then
      .checkpoints |= bump(if $args.status == "continue" or $args.status == "blocked" or $args.status == "done" then $args.status else "other" end)
    elif $in_window and $name == "handoff_checkpoint" then .ckpt.handoff.attempts += 1
    elif $in_window and $name == "Agent" then dispatch($args)
    elif $in_window and ($name == "bash" or $name == "Bash") then
      .bash.calls += 1
      | if ($args | has("timeout")) and $args.timeout != null then .bash.timeout_argument_present += 1 else . end
      | if ($args.timeout | type) == "number" and $args.timeout > 3600 then .bash.timeout_over_3600s += 1 else . end
      | .bash.by_value |= bump(timeout_label($args))
    else . end;

def process_event($event):
  ($event.timestamp | epoch) as $timestamp
  | ($timestamp != null and $timestamp >= $cutoff and ($until == null or $timestamp <= $until)) as $in_window
  | if $event.type == "session" then
      .has_header = true
      | .created = (if .created == null then $timestamp else .created end)
      | if ($event.parentSession | type) == "string" then .parent_session = $event.parentSession else . end
    else . end
  | if $event.type == "session_info" and ($event.name | type) == "string"
      and ($event.name | test("^[^#\\s]+#[A-Za-z0-9_-]{8}$")) then
      .worker_name = ($event.name | split("#")[0] | safe_label)
      | .worker_prefix = ($event.name | split("#")[1])
    else . end
  | if $timestamp != null then
      .earliest = (if .earliest == null then $timestamp else ([.earliest, $timestamp] | min) end)
      | if $in_window then
          .recent = true
          | .first_recent = (if .first_recent == null then $timestamp else ([.first_recent, $timestamp] | min) end)
          | .last_recent = (if .last_recent == null then $timestamp else ([.last_recent, $timestamp] | max) end)
        else . end
    else . end
  | if $in_window and $event.type == "compaction" then .compactions += 1 else . end
  | if $in_window and ($event.type == "custom" or $event.type == "custom_message")
      and ($event.customType == "unattended-handoff" or $event.customType == "compaction-handoff") then
      .handoffs[$event.type] |= bump($event.customType)
    else . end
  | if $in_window and $event.type == "custom"
      and ($event.customType == "compaction-handoff-written" or $event.customType == "compaction-handoff-approved")
      and ($event.data | type) == "object" and ($event.data.sessionId | type) == "string" and ($event.data.checkpointPath | type) == "string" then
      .handoffs.custom |= bump($event.customType)
    else . end
  | if $in_window and $event.type == "custom_message" and $event.customType == "unattended-continuation" then .continuations += 1 else . end
  | if $in_window and $event.type == "custom" and $event.customType == "task-outcome-receipt" then
      ($event.data | receipt_of) as $r
      | if $r == null then .receipts_invalid += 1
        else
          .receipts[$r.taskId].counts |= bump($r.outcome)
          | if .receipts[$r.taskId].latest == null or $timestamp >= .receipts[$r.taskId].latest.ts then
              .receipts[$r.taskId].latest = ($r | del(.taskId) | .ts = $timestamp)
            else . end
        end
    else . end
  | if $in_window and $event.type == "custom" and $event.customType == "subagents:record"
      and ($event.data | type) == "object" and ($event.data.id | valid_task_id)
      and (($event.data.status | record_status) != null) then
      .tasks[$event.data.id].r = ($event.data.status | record_status)
    else . end
  | if $event.type == "model_change" then
      (($event.provider | safe_label) + "/" + ($event.modelId | safe_label)) as $selection
      | if $in_window then
          (if .selection == null then "initial_selection" elif .selection == $selection then "same_selection" else "transition" end) as $kind
          | .model_changes |= bump($kind)
        else . end
      | .selection = $selection
    else . end
  | if $in_window and $event.customType == "subagent-notification" then
      ($event.content | terminal_status) as $status
      | if $status == null then . else
          (if ($event.content | type) == "string" then
             (try ($event.content | capture("<task-id>(?<value>[^<]{0,128})</task-id>"; "i").value) catch $event.id)
           else $event.id end) as $identity
          | (if ($identity | type) == "string" or ($identity | type) == "number" or ($identity | type) == "boolean" then $identity else .line_number end) as $identity
          | .notifications |= (. + [([$path, $identity, $status] | tojson)] | unique)
          | ($event.content | xml_field("task-id")) as $task_id
          | ($event.content | xml_field("tool-use-id")) as $tool_id
          | if ($task_id | valid_task_id) then
              .tasks[$task_id].n = $status
              | if ($tool_id | type) == "string" and ($tool_id | test("^[A-Za-z0-9_.:|=-]{1,128}$")) then .tasks[$task_id].tool = $tool_id else . end
            else . end
        end
    else . end
  | if $in_window and ($event.message | type) == "object" and $event.message.role == "assistant" then
      ($event.message.usage | if type == "object" then . else {} end) as $usage
      | (($event.message.provider | safe_label) + "/" + ($event.message.model | safe_label)) as $key
      | if $event.message.stopReason == "error" then
          .errors |= bump($key)
          | ($event.message.errorMessage | auth_category) as $category
          | .auth_categories |= bump($category)
          | .error_categories[$key] |= (. // {} | bump($category))
        else . end
      | def num($v): if ($v | type) == "number" then $v else 0 end;
      .models[$key] |= (. // {requests: 0, input: 0, output: 0, cache_read: 0, cache_write: 0, cost_total: 0})
      | .models[$key].requests += 1
      | .models[$key].input += num($usage.input)
      | .models[$key].output += num($usage.output)
      | .models[$key].cache_read += num($usage.cacheRead)
      | .models[$key].cache_write += num($usage.cacheWrite)
      | .models[$key].cost_total += num($usage.cost.total? // null)
    else . end
  | if ($event.message | type) == "object" and $event.message.role == "assistant"
      and ($event.message.provider | type) == "string" and ($event.message.model | type) == "string" then
      .selection = (($event.message.provider | safe_label) + "/" + ($event.message.model | safe_label))
      | .all_models[(($event.message.provider | safe_label) + "/" + ($event.message.model | safe_label))] = true
    else . end
  | if ($event.message | type) != "object" then .
    elif $event.message.role == "assistant" and ($event.message.content | type) == "array" then
      reduce $event.message.content[] as $block (.;
        if ($block | type) == "object" and $block.type == "toolCall" then handle_block($block; $in_window) else . end
      )
    elif $in_window and $event.message.role == "toolResult"
      and ($event.message.toolName == "unattended_checkpoint" or $event.message.toolName == "handoff_checkpoint") then
      $event.message as $m
      | ($m.toolName == "unattended_checkpoint") as $unattended
      | (if $unattended then "unattended" else "handoff" end) as $bucket
      | (if ($m.toolCallId | type) == "string" then .ckpt_calls[$m.toolCallId] else null end) as $call
      | if $m.isError == true then .ckpt[$bucket].error_results += 1
        elif $m.isError == false and $call == $m.toolName and ($m.details | checkpoint_details_ok($unattended)) then
          (if $unattended then .ckpt.unattended.successful |= bump($m.details.status) else .ckpt.handoff.successful += 1 end)
        else .ckpt[$bucket].invalid_results += 1 end
    elif $in_window and $event.message.role == "toolResult" and $event.message.toolName == "get_subagent_result" then
      .retrieval.results += 1
      | ($event.message.content | content_texts) as $texts
      | if any($texts[]; test("\\b(?:agent|subagent|worker)\\s+not\\s+found\\b"; "i")) then
          .retrieval.misses += 1
          | ($event.message.toolCallId) as $call_id
          | (if ($call_id | type) == "string" then .calls[$call_id] else null end) as $target
          | (if ($target | type) == "string" and $target != "" then $target
             elif $call_id != null and $call_id != false and $call_id != "" and $call_id != 0 then $call_id
             else .line_number end) as $identity
          | .retrieval.targets |= (. + [([$path, $identity] | tojson)] | unique)
        else . end
    else . end;

def scan_file:
  reduce inputs as $line (
    {
      line_number: 0, malformed_lines: 0, has_header: false,
      compactions: 0, handoffs: {custom: {}, custom_message: {}}, checkpoints: {},
      selection: null, model_changes: {}, errors: {}, auth_categories: {}, error_categories: {}, created: null, parent_session: null, worker_name: null,
      earliest: null, first_recent: null, last_recent: null, recent: false,
      bash: {calls: 0, timeout_argument_present: 0, timeout_over_3600s: 0, by_value: {}},
      dispatch: {max_turns: {}, model: {}, thinking: {}, background: {}, resume: {}},
      nonblank: 0, worker_prefix: null, all_models: {}, agent_calls: {}, ckpt_calls: {}, tasks: {}, receipts: {}, receipts_invalid: 0, continuations: 0,
      ckpt: {unattended: {successful: {}, error_results: 0, invalid_results: 0}, handoff: {attempts: 0, successful: 0, error_results: 0, invalid_results: 0}},
      notifications: [], models: {}, calls: {}, retrieval: {attempts: 0, results: 0, misses: 0, targets: []}
    };
    .line_number += 1
    | if ($line | test("^\\s*$")) then .
      else .nonblank += 1
      | if ($line | contains("�")) then .malformed_lines += 1
        else (try {ok: true, event: ($line | fromjson)} catch {ok: false}) as $parsed
        | if ($parsed.ok | not) or ($parsed.event | type) != "object" then .malformed_lines += 1
          else process_event($parsed.event)
          end
        end
      end
  )
  | . as $summary
  | {
      path: $path,
      has_header: $summary.has_header,
      recent: $summary.recent,
      compactions: $summary.compactions, handoffs: $summary.handoffs, checkpoints: $summary.checkpoints,
      model_changes: $summary.model_changes, errors: $summary.errors,
      auth_categories: $summary.auth_categories, error_categories: $summary.error_categories,
      malformed_lines: $summary.malformed_lines,
      nonblank: $summary.nonblank,
      continuations: $summary.continuations, ckpt: $summary.ckpt,
      receipts: $summary.receipts, receipts_invalid: $summary.receipts_invalid,
      tasks: ($summary.tasks | map_values(. + {req: ($summary.agent_calls[.tool // ""] // null)} | del(.tool))),
      join: (if $summary.has_header and $summary.worker_name != null and $summary.worker_prefix != null
                and ($summary.parent_session | type) == "string" and $summary.parent_session != ""
             then {parent: $summary.parent_session, prefix: $summary.worker_prefix, models: ($summary.all_models | keys)} else null end),
      bash: $summary.bash,
      dispatch: $summary.dispatch,
      notifications: $summary.notifications,
      models: $summary.models,
      retrieval: $summary.retrieval
    }
  + (if $summary.recent and $summary.has_header then
       ($summary.created // $summary.earliest) as $created
       | (if $summary.worker_name != null and ($summary.parent_session | type) == "string" and $summary.parent_session != "" then "worker"
          elif ($summary.parent_session | type) == "string" and $summary.parent_session != "" then "fork" else "main" end) as $classification
       | {
           classification: $classification,
           age: (if $created != null and $created >= $cutoff then "created_within_window" else "older_with_activity" end),
           worker_type: $summary.worker_name,
           parent_session: $summary.parent_session,
           first_recent: $summary.first_recent,
           last_recent: $summary.last_recent
         }
     else {} end);

def sum_counts($objects):
  reduce $objects[] as $object ({};
    reduce ($object | to_entries[]) as $entry (.;
      .[$entry.key] = ((.[$entry.key] // 0) + $entry.value)
    )
  );

def merge_models($files):
  reduce ($files[] | .models // {} | to_entries[]) as $e ({};
    .[$e.key] = (if .[$e.key] == null then $e.value
                 else reduce ($e.value | to_entries[]) as $f (.[$e.key]; .[$f.key] += $f.value) end)
  );

def tally(f): reduce .[] as $x ({}; bump($x | f));

# One row per terminal task seen in a coordinator file; ids never leave this function.
def task_rows($files):
  ([$files[] | select(.join != null) | .join] | group_by(.parent) | map({key: .[0].parent, value: .}) | from_entries) as $workers
  | [ $files[] | select((.tasks | length) > 0) | . as $f
      | ($f.tasks | keys | group_by(.[0:8]) | map({key: .[0][0:8], value: length}) | from_entries) as $first8
      | $f.tasks | to_entries[] | .key as $id | .value as $t
      | ([($workers[$f.path] // [])[] | select(. as $w | $id | startswith($w.prefix))]) as $m
      | {
          path: $f.path, id: $id,
          status: ($t.r // $t.n),
          source: (if $t.r != null and $t.n != null then "both" elif $t.r != null then "record_only" else "notification_only" end),
          join: (if $first8[$id[0:8]] > 1 or ($m | length) > 1 then "ambiguous"
                 elif ($m | length) == 0 then "no_worker"
                 elif ($m[0].models | length) == 0 then "no_assistant_model"
                 elif ($m[0].models | length) == 1 then "joined_single_model"
                 else "mixed_models" end),
          actual: (if ($m | length) == 1 and ($m[0].models | length) == 1 and ($first8[$id[0:8]] == 1) then $m[0].models[0] else null end),
          req: $t.req
        }
    ];

def task_evidence($rows):
  ([$rows[] | select(.req != null)]) as $requested
  | {
      terminal_tasks: ($rows | length),
      status_sources: ($rows | tally(.source)),
      status: ($rows | tally(.status)),
      request_join: {matched_agent_call: ($requested | length), unmatched: (($rows | length) - ($requested | length))},
      requested_model: ($requested | tally(.req.model)),
      requested_effort: ($requested | tally(.req.effort)),
      worker_join: ($rows | tally(.join)),
      actual_model_terminal_status: (reduce ($rows[] | select(.actual != null)) as $r ({}; .[$r.actual][$r.status] = ((.[$r.actual][$r.status] // 0) + 1))),
      requested_vs_actual: ([$rows[] | select(.actual != null and .req != null)] | tally("requested=" + .req.model + " actual=" + .actual)),
      runtime_effort: {available: false, reason: "No session or notification field records the runtime effort actually applied."}
    };

def task_outcomes($files; $rows; $dispatches):
  ([$files[] | .path as $p | (.receipts // {}) | to_entries[] | {path: $p, id: .key} + .value]) as $tasks
  | ([$files[].receipts_invalid // 0] | add // 0) as $invalid
  | ($rows | map({key: (.path + "\u0000" + .id), value: true}) | from_entries) as $terminal
  | ($tasks | map(select($terminal[.path + "\u0000" + .id] == true)) | length) as $with_terminal
  | if ($tasks | length) == 0 then
      {available: false, receipts_invalid: $invalid, reason: "No valid task-outcome-receipt entries; absence is unavailable, not zero quality."}
    else
      {
        available: true,
        source: "coordinator_reported_task_outcome_receipt",
        actual_runtime_proof: false,
        receipts_valid: ([$tasks[].counts[]] | add),
        receipts_invalid: $invalid,
        tasks_with_receipt: ($tasks | length),
        latest_outcomes: ($tasks | tally(.latest.outcome)),
        rework_history_tasks: ([$tasks[] | select((.counts.reworked // 0) > 0)] | length),
        rework_events: ([$tasks[] | .counts.reworked // 0] | add),
        check_artifact_present: ([$tasks[] | select(.latest.artifact)] | length),
        coverage: {
          terminal_tasks_observed: ($rows | length),
          dispatches_observed: $dispatches,
          receipted_tasks_with_terminal_evidence: $with_terminal,
          receipted_tasks_without_terminal_evidence: (($tasks | length) - $with_terminal)
        },
        by_model_effort: (
          reduce ($tasks | group_by([.latest.model, .latest.effort])[]) as $g ({};
            .[$g[0].latest.model][$g[0].latest.effort] = {
              tasks: ($g | length),
              latest_outcomes: ($g | tally(.latest.outcome)),
              rework_history_tasks: ([$g[] | select((.counts.reworked // 0) > 0)] | length),
              receipts: ([$g[].counts[]] | add),
              check_artifact_present: ([$g[] | select(.latest.artifact)] | length)
            })
        )
      }
    end;

def aggregate:
  . as $all
  | ([$all[] | select(has("_candidates")) | ._candidates] | first) as $candidates
  | [$all[] | select(has("_candidates") | not)] as $scanned
  | map(select(.has_header == true)) as $files
  | ([$files[] | select(.classification == "main") | {(.age): 1}] | sum_counts(.)) as $main
  | ([$files[] | select(.classification == "fork") | {(.age): 1}] | sum_counts(.)) as $forks
  | ([$files[] | select(.classification == "worker") | {(.worker_type): 1}] | sum_counts(.)) as $worker_types
  | ([$files[] | select(.classification == "worker") | .bash] | map(del(.by_value)) | sum_counts(.)) as $worker_bash
  | ([$files[] | select(.classification == "worker") | .bash.by_value] | sum_counts(.)) as $worker_bash_values
  | ([$files[] | select(.classification != "worker" and .classification != null) | .bash] | map(del(.by_value)) | sum_counts(.)) as $coordinator_bash
  | ([$files[] | select(.classification != "worker" and .classification != null) | .bash.by_value] | sum_counts(.)) as $coordinator_bash_values
  | ([$files[] | select(.recent) | .dispatch.max_turns] | sum_counts(.)) as $max_turns
  | ([$files[] | select(.recent) | .dispatch.model] | sum_counts(.)) as $models
  | ([$files[] | select(.recent) | .dispatch.thinking] | sum_counts(.)) as $thinking
  | ([$files[] | select(.recent) | .dispatch.background] | sum_counts(.)) as $background
  | ([$files[] | select(.recent) | .dispatch.resume] | sum_counts(.)) as $resume
  | ([ $files[].notifications[]? ] | unique | map(fromjson | .[2]) | group_by(.) | map({(.[0]): length}) | add // {}) as $notifications
  | ([ $files[].retrieval.targets[]? ] | unique | length) as $unique_misses
  | ([$files[] | select(.classification == "worker" and .parent_session != null and .first_recent != null and .last_recent != null)
       | {parent: .parent_session, events: [[.first_recent, 1], [.last_recent, -1]]}
      ] | group_by(.parent) | map(
        [.[].events[]] | sort_by(.[0], -.[1])
        | reduce .[] as $event ({active: 0, peak: 0};
            .active += $event[1] | .peak = ([.peak, .active] | max)
          ) | .peak
      ) | max // 0) as $concurrency
  | task_rows($files) as $task_rows
  | task_outcomes($files; $task_rows; ([$resume[]] | add // 0)) as $outcomes
  | ([$scanned[] | select(._unreadable == true)] | length) as $unreadable
  | ([$files[] | select(.recent)] | length) as $active
  | ([$scanned[] | select(.has_header == false and .nonblank == 0)] | length) as $empty
  | {
      window_start_local: $window_start_local,
      window_end_local: (if $window_end_local == "" then null else $window_end_local end),
      model_metrics: {
        workers: merge_models([$files[] | select(.classification == "worker")]),
        nonworker_coordinators: merge_models([$files[] | select(.classification != "worker" and .classification != null)])
      },
      retrospective: {
        compactions: ([$files[].compactions] | add // 0),
        handoffs: {
          custom: sum_counts([$files[].handoffs.custom]),
          custom_message: sum_counts([$files[].handoffs.custom_message])
        },
        unattended_checkpoint: (
          reduce ["workers", "nonworker_coordinators"][] as $group ({};
            ([$files[] | select(if $group == "workers" then .classification == "worker" else .classification != "worker" end)]) as $group_files
            | .[$group] = {
                by_status: sum_counts([$group_files[].checkpoints]),
                files: ([$group_files[] | select((.checkpoints | length) > 0)] | length),
                files_by_status: sum_counts([$group_files[].checkpoints | with_entries(.value = 1)])
              })
        ),
        stop_reason_errors: {
          by_provider_model: sum_counts([$files[].errors]),
          auth_categories: sum_counts([$files[].auth_categories]),
          by_provider_model_auth_category: (
            reduce ($files[].error_categories | to_entries[]) as $e ({};
              .[$e.key] = sum_counts([.[$e.key] // {}, $e.value]))
          )
        },
        model_change_events: sum_counts([$files[].model_changes]),
        top_error_sessions: ([$files[] | (.errors | [.[]] | add // 0) as $count
          | select($count > 0) | {path, classification, errors: $count}]
          | sort_by(-.errors, .path) | .[:10]),
        top_turn_limit_sessions: {available: false, reason: "No turn-limit session ranking or model attribution; only unique single-model joins appear in task_evidence."},
        checkpoint_evidence: {
          unattended: {
            successful_by_status: sum_counts([$files[].ckpt.unattended.successful]),
            successful: ([$files[].ckpt.unattended.successful[]] | add // 0),
            error_results: ([$files[].ckpt.unattended.error_results] | add // 0),
            invalid_results: ([$files[].ckpt.unattended.invalid_results] | add // 0),
            continuations: ([$files[].continuations] | add // 0)
          },
          handoff_checkpoint: {
            attempts: ([$files[].ckpt.handoff.attempts] | add // 0),
            successful: ([$files[].ckpt.handoff.successful] | add // 0),
            error_results: ([$files[].ckpt.handoff.error_results] | add // 0),
            invalid_results: ([$files[].ckpt.handoff.invalid_results] | add // 0),
            written_receipts: ([$files[].handoffs.custom["compaction-handoff-written"] // 0] | add // 0),
            approved_receipts: ([$files[].handoffs.custom["compaction-handoff-approved"] // 0] | add // 0)
          }
        },
        task_outcomes: $outcomes,
        accepted_outcomes: (if $outcomes.available then
            {available: true, source: $outcomes.source, accepted_latest: ($outcomes.latest_outcomes.accepted // 0), denominator_tasks_with_receipt: $outcomes.tasks_with_receipt}
          else {available: false} end),
        rework: (if $outcomes.available then
            {available: true, source: $outcomes.source, tasks_with_rework_history: $outcomes.rework_history_tasks, rework_events: $outcomes.rework_events, denominator_tasks_with_receipt: $outcomes.tasks_with_receipt}
          else {available: false} end)
      },
      task_evidence: task_evidence($task_rows),
      scan_reconciliation: (
        ([$files[] | select(.classification != null)] | length) as $classified
        | {
            candidates: $candidates,
            scanned: ($scanned | length),
            session_files_with_window_activity: $active,
            session_files_without_window_activity: (($files | length) - $active),
            headerless_nonempty: ([$scanned[] | select(.has_header == false and .nonblank > 0)] | length),
            headerless_empty: $empty,
            unreadable: $unreadable,
            classified_main_fork_worker: $classified,
            candidates_match_scanned: ($candidates == ($scanned | length)),
            partition_balanced: (($scanned | length) == (($files | length) + ([$scanned[] | select(.has_header == false)] | length) + $unreadable)),
            classification_balanced: ($classified == $active),
            error_categories_match_errors: (([$files[].errors[]] | add // 0) == ([$files[].auth_categories[]] | add // 0))
          }
      ),
      limitations: [
        "Counts direct tool calls only; nested codemode calls are uncounted. Files last modified before --since are skipped.",
        "Worker overlap is a first/last logged-span proxy, not actual execution concurrency or a guaranteed lifecycle upper bound.",
        "Terminal statuses come from notifications logged in the parent session, so they are counted per unique notification, not attributed to individual worker sessions or models. Model metrics count assistant messages; missing usage fields count as 0.",
        "No nested codemode parsing or tool-definition counting. Checkpoint calls are attempts, not saved files or accepted outcomes; done is not acceptance.",
        "Handoffs count only custom/custom_message unattended-handoff and compaction-handoff entries (state writes are not necessarily handoffs). Model changes are observed selections/transitions, not automatic fallbacks.",
        "Headerless JSONL is excluded from session metrics. Malformed/skipped lines include invalid JSON/unicode and raw replacement characters; scan counters cover entire candidate files, not timed events.",
        "Model selection classification uses preceding logged model_change/assistant metadata; missing history can make the first observed selection initial.",
        "Task outcomes come only from valid coordinator-written task-outcome-receipt entries (latest verdict per task per coordinator file; rework counted from history); they are not actual-runtime proof, and no receipts means unavailable, not zero quality. Check artifacts are only counted, never read.",
        "task_evidence joins notification/subagents:record task IDs to worker session_info Type#first8(taskId) only for a unique prefix within the same parent session; actual model requires exactly one assistant provider/model in the worker file, otherwise it is mixed/unmatched. Requested model/effort come from the direct Agent tool call matching the notification tool-use-id in the same file; runtime effort is unknown and reported (receipt) model is separate.",
        "Checkpoint attempts are unchanged; checkpoint_evidence counts successes only for toolResults joined by call id with isError false and managed details {path,cwd[,status]}; file contents and paths are never read or output. Terminal notification statuses stay notification-only; terminal evidence adds subagents:record entries deduplicated by task ID. Notifications without a task ID are not joinable."
      ],
      main_sessions: $main,
      fork_sessions: $forks,
      workers: {
        sessions: ([$worker_types[]] | add // 0),
        types: $worker_types,
        max_concurrency_observed_span_upper_bound: $concurrency
      },
      bash_timeouts: {
        workers: ({calls: 0, timeout_argument_present: 0, timeout_over_3600s: 0} + $worker_bash + {by_value: $worker_bash_values}),
        nonworker_coordinators: ({calls: 0, timeout_argument_present: 0, timeout_over_3600s: 0} + $coordinator_bash + {by_value: $coordinator_bash_values})
      },
      agent_dispatches: {
        total: ([$resume[]] | add // 0),
        max_turns: $max_turns,
        model: $models,
        thinking: $thinking,
        background: $background,
        resume: $resume
      },
      terminal_notification_statuses_unique: $notifications,
      get_subagent_result: {
        attempts: ([$files[] | .retrieval.attempts // 0] | add // 0),
        results: ([$files[] | .retrieval.results // 0] | add // 0),
        misses: ([$files[] | .retrieval.misses // 0] | add // 0),
        unique_missed_targets: $unique_misses,
        duplicate_misses: (([ $files[] | .retrieval.misses // 0 ] | add // 0) - $unique_misses)
      },
      scan: {
        files: ($scanned | length),
        session_files: ($files | length),
        non_session_jsonl_files: ([$scanned[] | select(.has_header == false)] | length),
        skipped_lines: ([$scanned[] | .malformed_lines // 0] | add // 0),
        malformed_lines: ([ $scanned[] | .malformed_lines // 0 ] | add // 0),
        unreadable_files: ([$scanned[] | select(._unreadable == true)] | length)
      }
    };

if $mode == "time" then $time | epoch
elif $mode == "aggregate" then aggregate
else scan_file end
