def epoch:
  if type != "string" then null else
    (try (
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
    ) catch null) // null
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

def receipt_label: type == "string" and test("^[A-Za-z0-9_./:@+-]{1,128}$");
def uuid: type == "string" and test("^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$");
# fast-task-dispatch.REASONS v1; unknown codes are never echoed.
def dispatch_reason:
  if IN("eligible", "reserved", "worker_linked", "invalid_packet", "missing_grants", "preflight", "missing_tools", "board_unverified", "dependency", "ownership", "duplicate", "capacity", "busy", "cancelled", "native_submission", "native_started", "native_terminal", "native_failed", "startup_failed", "submission_unknown", "timeout", "recovery_unknown", "runtime_observed") then . else "unknown" end;
def nonnegative: type == "number" and . >= 0 and isfinite;

# Match nativeEvidence's bounded types; observation time never supplies missing native times.
def native_time: nonnegative and . <= 8640000000000000 and floor == .;
def native_fields:
  . as $d
  | {observationSource: (if (.observationSource | IN("live", "recovered")) then .observationSource else null end),
     nativeSource: (if (.nativeSource | IN("subagents:completed", "subagents:failed", "subagents:record")) then .nativeSource else null end),
     nativeStatus: (if (.nativeStatus | IN("completed", "steered", "aborted", "stopped", "error")) then .nativeStatus else null end),
     nativeStartedAt: (if (.nativeStartedAt | native_time) then .nativeStartedAt else null end),
     nativeCompletedAt: (if (.nativeCompletedAt | native_time) then .nativeCompletedAt else null end)}
  | if .nativeCompletedAt != null and .nativeStartedAt != null and .nativeCompletedAt < .nativeStartedAt then .nativeCompletedAt = null else . end
  | .nativeDurationMs = (if .nativeSource == "subagents:record" then
       if .nativeStartedAt != null and .nativeCompletedAt != null then .nativeCompletedAt - .nativeStartedAt else null end
     elif .nativeSource != null and ($d.nativeDurationMs | nonnegative) and $d.nativeDurationMs <= 9007199254740991 then $d.nativeDurationMs else null end)
  | . as $clean
  | .invalid_native_fields = ([keys[] | . as $k | select(($d | has($k)) and $d[$k] != $clean[$k])] | length);

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

# Fixed enum of the raw source label; normalized comparison counts keep using terminal_status/record_status.
def raw_termination:
  if type != "string" then null else
    (ascii_downcase | gsub("^\\s+|\\s+$"; "")) as $s
    | if $s == "done" then "done"
      elif ($s | startswith("completed")) then "completed"
      elif ($s | startswith("finished")) then "finished"
      elif ($s | startswith("wrapped up")) then "wrapped_up"
      elif ($s | startswith("aborted")) then "aborted"
      elif ($s | startswith("steered")) then "steered"
      elif ($s | startswith("turn limit")) then "turn_limit_cap"
      elif ($s | startswith("max turns")) then "max_turns_cap"
      elif ($s | startswith("stopped")) then "stopped"
      elif ($s | startswith("cancelled")) or ($s | startswith("canceled")) then "cancelled"
      elif ($s | startswith("error")) then "error"
      elif ($s | startswith("failed")) then "failed"
      else "other" end
  end;

def notification_raw_termination:
  if type != "string" then null else
    (try capture("<status>(?<value>[^<]{0,512})</status>"; "i").value catch null) | raw_termination
  end;

def receipt_of:
  if type != "object" then null
  elif (.taskId | type) == "string" and (.taskId | test("^[A-Za-z0-9_./:@+-]{1,128}$"))
    and (.outcome | IN("accepted", "reworked", "rejected"))
    and (.model | type) == "string" and (.model | test("^[A-Za-z0-9_./:@+-]{1,128}$"))
    and (.effort | IN("off", "minimal", "low", "medium", "high", "xhigh", "max", "unknown"))
    and ((.checkArtifact | type) == "string" and (.checkArtifact | length) >= 1 and (.checkArtifact | length) <= 300
      and (.checkArtifact | test("[[:space:][:cntrl:]]") | not))
  and (. as $r | all(["boardTaskId", "attemptId", "parentTaskId", "reviewerWorkerId"][]; . as $k | if $r | has($k) then ($r[$k] | receipt_label) else true end))
    and ((has("phase") | not) or (.phase | IN("implementation", "review", "repair")))
    and ((has("coordinatorReportedDurationMs") | not) or (.coordinatorReportedDurationMs | nonnegative and floor == . and . <= 9007199254740991))
  then {taskId, outcome, model, effort, boardTaskId, attemptId, phase, parentTaskId, reviewerWorkerId, coordinatorReportedDurationMs, artifact: (.checkArtifact != null)}
  else null end;

# Managed checkpoint tools return details {path, cwd} (+ status for unattended_checkpoint).
def checkpoint_details_ok($status_required):
  type == "object" and (.path | type) == "string" and (.path | test("^/.{0,4094}\\.md$"))
  and (.cwd | type) == "string"
  and (($status_required | not) or (.status | IN("continue", "blocked", "done")));

# Nearest-rank percentiles; only valid nonnegative numeric samples enter the list.
def distribution($values):
  ($values | sort) as $v | ($v | length) as $n
  | {count: $n, p50: (if $n == 0 then null else $v[(($n * 0.5 | ceil) - 1)] end),
     p90: (if $n == 0 then null else $v[(($n * 0.9 | ceil) - 1)] end)};

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
    elif $in_window and $name == "codemode" then .codemode_calls += 1
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
  | if $in_window and $event.type == "compaction" then
      .compactions += 1
      | if ($event.tokensBefore | type) == "number" and $event.tokensBefore >= 0 then .compaction_tokens += [$event.tokensBefore] else . end
    else . end
  | if $in_window and ($event.type == "custom" or $event.type == "custom_message")
      and ($event.customType == "unattended-handoff" or $event.customType == "compaction-handoff") then
      .handoffs[$event.type] |= bump($event.customType)
    else . end
  | if $in_window and $event.type == "custom"
      and ($event.customType == "compaction-handoff-written" or $event.customType == "compaction-handoff-approved")
      and ($event.data | type) == "object" and ($event.data.sessionId | type) == "string" and ($event.data.checkpointPath | type) == "string" then
      .handoffs.custom |= bump($event.customType)
    else . end
  | if $in_window and $event.type == "custom_message" and $event.customType == "unattended-continuation" then
      .continuations += 1
      # Conservative link: same file, the nearest preceding unconsumed successful `continue` checkpoint result, no event-time inversion.
      | if .pending_continue != null and $timestamp != null and $timestamp >= .pending_continue.ts then
          (if ($event.parentId | type) == "string" and $event.parentId == .pending_continue.entry then "exact_parent" else "temporal" end) as $kind
          | .link.linked |= bump($kind)
          | .pending_continue = null
        else .link.unlinked += 1 end
    else . end
  | if $in_window and ($event.customType | IN("checkpoint-provenance", "continuation-provenance", "unattended-continuation")) then
      (if $event.customType == "unattended-continuation" then $event.details else $event.data end) as $d
      | if $d == null then .provenance_legacy += 1
        elif ($d | type) == "object" and $d.schemaVersion == 1 and
          (($event.type == "custom" and $event.customType == "checkpoint-provenance" and
            (($d.phase == "write-success" and ($d.mode | IN("interactive", "unattended")) and ($d.checkpointId | uuid) and ($d.continuationLink | IN("supported", "unavailable")))
             or ($d.phase == "notice" and $d.mode == "interactive" and $d.continuationLink == "unavailable")))
           or ($event.type == "custom_message" and $event.customType == "unattended-continuation" and $d.phase == "proposal" and ($d.continuationId | uuid) and (($d | has("checkpointId") | not) or ($d.checkpointId | uuid)))
           or ($event.type == "custom" and $event.customType == "continuation-provenance" and $d.phase == "consumed" and ($d.continuationId | uuid) and (($d | has("parentCheckpointId") | not) or ($d.parentCheckpointId | uuid)) and $d.observation == "context-with-system/completed-turn")) then
          .provenance += [($d | {phase, mode, checkpointId, continuationId, parentCheckpointId, continuationLink}) + {ts: $timestamp}]
        else .provenance_invalid += 1 end
    else . end
  | if $in_window and $event.type == "custom" and $event.customType == "quota-status-metrics" then
      $event.data as $q
      | if ($q | type) == "object" and $q.version == 1 and ($q.decisionSnapshotAt | type) == "number" and ($q.fetchDurationMs | type) == "number" and $q.fetchDurationMs >= 0 and ($q.refreshReason | IN("explicit", "default")) and ($q.observations | type) == "array" then
          .quota.fetch += [$q.fetchDurationMs] | .quota.refresh |= bump($q.refreshReason)
          | reduce $q.observations[] as $o (. ;
              if ($o | type) == "object" and ($o.provider | IN("openai", "anthropic", "anthropic-api", "github-copilot", "opencode-go", "opencode", "codexbarCredits"))
                and ($o.capturedAt == null or ($o.capturedAt | nonnegative))
                and ($o.cacheHit == null or ($o.cacheHit | type) == "boolean")
                and ($o.ageMs == null or ($o.ageMs | nonnegative)) then
                .quota.observations[$o.provider] |= (. // {hit: 0, miss: 0, unknown: 0, ages: []})
                | .quota.observations[$o.provider] |= bump(if $o.cacheHit == true then "hit" elif $o.cacheHit == false then "miss" else "unknown" end)
                | if ($o.ageMs | type) == "number" and $o.ageMs >= 0 then .quota.observations[$o.provider].ages += [$o.ageMs] else . end
              else .quota.invalid_observations += 1 end)
        else .quota.invalid_events += 1 end
    else . end
  | if $in_window and $event.type == "custom" and $event.customType == "fast-task-dispatch" then
      $event.data as $d
      | if ($d | type) == "object" and $d.schemaVersion == 1 and ($d.coordinatorSessionId | valid_task_id) and ($d.taskId | type) == "string" and ($d.taskId | test("^[A-Za-z0-9_./:@+-]{1,128}$")) and ($d.attemptId | valid_task_id) and ($d.state | IN("ready", "submitted", "started", "blocked", "terminal")) and ($d.timestamp | type) == "number" and $d.timestamp >= 0
          and (all(["workerId", "parentTaskId"][]; . as $k | if $d | has($k) then ($d[$k] | receipt_label) else true end))
          and (($d | has("phase") | not) or ($d.phase | IN("implementation", "review", "repair"))) then
          .fast_events += [($d | {coordinatorSessionId, taskId, attemptId, state, timestamp, workerId, phase, parentTaskId, requestedModel, requestedEffort, actualModel, actualEffort, actualSource, reason: (.reason | dispatch_reason)} + native_fields)]
        else .fast_invalid += 1 end
    else . end
  | if $in_window and $event.type == "custom" and $event.customType == "task-outcome-activation" then
      $event.data as $d
      | if ($d | type) == "object" and $d.schemaVersion == 1 and $d.extensionVersion == 1
          and ($d.source | IN("startup", "reload", "new", "resume", "fork", "unknown"))
          and (($d.timestamp | epoch) != null)
          and (($d.extensionSha256 == null) or (($d.extensionSha256 | type) == "string" and ($d.extensionSha256 | test("^[a-f0-9]{64}$"))))
          and (($d.coordinatorPolicySha256 == null) or (($d.coordinatorPolicySha256 | type) == "string" and ($d.coordinatorPolicySha256 | test("^[a-f0-9]{64}$")))) then
          .activation.valid += 1 | .activation.sources |= bump($d.source)
          | if $d.extensionSha256 != null then .activation.extension_hash_present += 1 else . end
          | if $d.coordinatorPolicySha256 != null then .activation.policy_hash_present += 1 else . end
        else .activation.invalid += 1 end
    else . end
  | if $in_window and $event.type == "custom" and $event.customType == "task-outcome-receipt" then
      ($event.data | receipt_of) as $r
      | if $r == null then .receipts_invalid += 1
        else
          .receipt_events += [($r + {ts: $timestamp})]
          | .receipts[$r.taskId].counts |= bump($r.outcome)
          | if .receipts[$r.taskId].latest == null or $timestamp >= .receipts[$r.taskId].latest.ts then
              .receipts[$r.taskId].latest = ($r | del(.taskId) | .ts = $timestamp)
            else . end
        end
    else . end
  | if $in_window and $event.type == "custom" and $event.customType == "subagents:record"
      and ($event.data | type) == "object" and ($event.data.id | valid_task_id)
      and (($event.data.status | record_status) != null) then
      .tasks[$event.data.id].r = ($event.data.status | record_status)
      | .tasks[$event.data.id].rr = ($event.data.status | raw_termination)
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
      | ($event.content | notification_raw_termination) as $raw
      | (if ($event.content | type) == "string" then
           (try ($event.content | capture("<task-id>(?<value>[^<]{0,128})</task-id>"; "i").value) catch $event.id)
         else $event.id end) as $identity
      | (if ($identity | type) == "string" or ($identity | type) == "number" or ($identity | type) == "boolean" then $identity else .line_number end) as $identity
      | (if $raw != null then .raw_notifications |= (. + [([$path, $identity, $raw] | tojson)] | unique) else . end)
      | if $status == null then . else
          .notifications |= (. + [([$path, $identity, $status] | tojson)] | unique)
          | ($event.content | xml_field("task-id")) as $task_id
          | ($event.content | xml_field("tool-use-id")) as $tool_id
          | if ($task_id | valid_task_id) then
              .tasks[$task_id].n = $status
              | .tasks[$task_id].nr = $raw
              | if ($tool_id | type) == "string" and ($tool_id | test("^[A-Za-z0-9_.:|=-]{1,128}$")) then .tasks[$task_id].tool = $tool_id else . end
            else . end
        end
    else . end
  | if ($event.message | type) == "object" and $event.message.role == "assistant" then
      if $in_window then
        if ($event.id | type) == "string" and .cost.seen[$event.id] == true then .cost.duplicate_events += 1
        else .cost.requests += 1
          | if ($event.id | type) == "string" then .cost.seen[$event.id] = true else .cost.requests_without_event_id += 1 end
          | if ($event.message.usage.cost.total? | nonnegative) then .cost.samples += 1 | .cost.observed += $event.message.usage.cost.total else . end
        end
      else .cost.outside_window_requests += 1 end
    else . end
  | if $in_window and ($event.message | type) == "object" and $event.message.role == "assistant" then
      (if ($event.message.durationMs | type) == "number" and $event.message.durationMs >= 0 then .response_durations += [$event.message.durationMs] else . end)
      | (if ($event.message.content | type) == "array" then
          .request_tool_counts += [[$event.message.content[] | select(type == "object" and .type == "toolCall")] | length]
        else .request_tool_counts_unknown += 1 end)
      | ($event.message.usage | if type == "object" then . else {} end) as $usage
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
  | if $in_window and ($event.message | type) == "object" and $event.message.role == "toolResult" and $event.message.toolName? == "quota_status" then
      if $event.message.isError == false and ($event.message.details | type) == "object" and ($event.message.details.providers | type) == "array" then
        .quota_typed_results += 1
        | reduce ($event.message.details | .providers + (if (.codexbarCredits | type) == "object" then [(.codexbarCredits + {provider: "codexbarCredits"})] else [] end))[] as $o (. ;
          if ($o | type) == "object" and ($o.provider | IN("openai", "anthropic", "anthropic-api", "github-copilot", "opencode-go", "opencode", "codexbarCredits")) then
            (if ($o.status | IN("fresh", "unknown", "unavailable")) then $o.status else "unknown_status" end) as $status
            | (if ($o.cache | type) == "object" then $o.cache else {} end) as $cache
            | (if ($o.capturedAt | nonnegative) and ($cache.ageMs | nonnegative) and ($cache.ttlMs | nonnegative) and $cache.ttlMs > 0 then
                 if $o.capturedAt > ($timestamp * 1000) then "future_capture"
                 elif any((if ($o.windows | type) == "array" then $o.windows else [] end)[]; type == "object" and (.resetsAt | nonnegative) and .resetsAt * 1000 <= ($timestamp * 1000)) then "reset_crossed"
                 elif ($timestamp * 1000 - $o.capturedAt) >= $cache.ttlMs then "expired"
                 else "within_ttl_no_observed_reset" end
               else "unknown" end) as $bounds
            | .quota_typed += [{provider: $o.provider, status: $status, cache_bounds: $bounds,
                reuse: (if $cache.hit == true then
                    if $status == "fresh" and $bounds == "within_ttl_no_observed_reset" then "usable_reuse"
                    elif $status == "unknown_status" then "reuse_status_unknown"
                    else "discarded_or_unusable_reuse" end
                  elif $cache.hit == false then "collected" else "cache_unknown" end)}]
          else .quota_typed_invalid += 1 end)
      else .quota_typed_invalid += 1 end
    else . end
  | if $in_window and ($event.message | type) == "object" and $event.message.role == "toolResult" and ($event.message.nestedCalls | type) == "object" and ($event.message.nestedCalls.calls | type) == "array" then
      reduce $event.message.nestedCalls.calls[] as $call (. ;
        if ($call | type) == "object" and ($call.name | IN("TaskCreate", "TaskGet", "TaskList", "TaskUpdate", "TaskExecute", "TaskOutput", "TaskStop", "Agent", "get_subagent_result", "unattended_checkpoint", "handoff_checkpoint")) then
          .nested_calls[$call.name].calls += 1
          | if ($call.durationMs | type) == "number" and $call.durationMs >= 0 then .nested_calls[$call.name].duration_ms += $call.durationMs | .nested_calls[$call.name].timed += 1 else . end
          | if $call.status == "error" or (($call | has("error")) and $call.error != null and $call.error != false) then .nested_calls[$call.name].errors += 1 else . end
        else . end)
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
          (if $unattended then
             .ckpt.unattended.successful |= bump($m.details.status)
             | if $m.details.status == "continue" and $timestamp != null then
                 .link.continue_successes += 1
                 | .pending_continue = {ts: $timestamp, entry: (if ($event.id | type) == "string" then $event.id else null end)}
               else .pending_continue = null end
           else .ckpt.handoff.successful += 1 end)
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
      cost: {requests: 0, samples: 0, observed: 0, outside_window_requests: 0, seen: {}, duplicate_events: 0, requests_without_event_id: 0}, receipt_events: [], provenance: [], provenance_invalid: 0, provenance_legacy: 0,
      quota_typed: [], quota_typed_results: 0, quota_typed_invalid: 0,
      quota: {fetch: [], refresh: {}, observations: {}, invalid_events: 0, invalid_observations: 0}, fast_events: [], fast_invalid: 0, activation: {valid: 0, invalid: 0, sources: {}, extension_hash_present: 0, policy_hash_present: 0}, compactions: 0, compaction_tokens: [], response_durations: [], request_tool_counts: [], request_tool_counts_unknown: 0, handoffs: {custom: {}, custom_message: {}}, checkpoints: {},
      selection: null, model_changes: {}, errors: {}, auth_categories: {}, error_categories: {}, created: null, parent_session: null, worker_name: null,
      earliest: null, first_recent: null, last_recent: null, recent: false,
      bash: {calls: 0, timeout_argument_present: 0, timeout_over_3600s: 0, by_value: {}},
      dispatch: {max_turns: {}, model: {}, thinking: {}, background: {}, resume: {}},
      nonblank: 0, worker_prefix: null, all_models: {}, agent_calls: {}, ckpt_calls: {}, tasks: {}, receipts: {}, receipts_invalid: 0, continuations: 0,
      ckpt: {unattended: {successful: {}, error_results: 0, invalid_results: 0}, handoff: {attempts: 0, successful: 0, error_results: 0, invalid_results: 0}},
      notifications: [], raw_notifications: [], models: {}, calls: {}, codemode_calls: 0, nested_calls: {},
      pending_continue: null, link: {linked: {}, unlinked: 0, continue_successes: 0}, retrieval: {attempts: 0, results: 0, misses: 0, targets: []}
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
      cost: ($summary.cost | del(.seen)), receipt_events: $summary.receipt_events, provenance: $summary.provenance, provenance_invalid: $summary.provenance_invalid, provenance_legacy: $summary.provenance_legacy,
      quota_typed: $summary.quota_typed, quota_typed_results: $summary.quota_typed_results, quota_typed_invalid: $summary.quota_typed_invalid,
      quota: $summary.quota, fast_events: $summary.fast_events, fast_invalid: $summary.fast_invalid, activation: $summary.activation, compactions: $summary.compactions, compaction_tokens: $summary.compaction_tokens, response_durations: $summary.response_durations, request_tool_counts: $summary.request_tool_counts, request_tool_counts_unknown: $summary.request_tool_counts_unknown, handoffs: $summary.handoffs, checkpoints: $summary.checkpoints,
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
      notifications: $summary.notifications, raw_notifications: $summary.raw_notifications,
      codemode_calls: $summary.codemode_calls, nested_calls: $summary.nested_calls, link: $summary.link,
      nonblank_events_header_only: ($summary.has_header and $summary.nonblank == 1),
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
          raw: (if $t.r != null then $t.rr else $t.nr end),
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
      raw_termination: {
        note: "Fixed-enum raw source labels beside the unchanged normalized status; turn_limit normalized = wrapped_up|aborted|steered(records)|turn_limit_cap|max_turns_cap.",
        terminal_tasks: ($rows | tally(.raw)),
        terminal_tasks_by_normalized_status: (reduce $rows[] as $r ({}; .[$r.status][$r.raw] = ((.[$r.status][$r.raw] // 0) + 1)))
      },
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
      {available: false, receipts_invalid: $invalid, coverage: {terminal_tasks_observed: ($rows | length), terminal_tasks_with_receipt: 0, terminal_tasks_without_receipt: ($rows | length)}, reason: "No valid task-outcome-receipt entries; absence is unavailable, not zero quality."}
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
          receipted_tasks_without_terminal_evidence: (($tasks | length) - $with_terminal),
          terminal_tasks_with_receipt: $with_terminal,
          terminal_tasks_without_receipt: (($rows | length) - $with_terminal)
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

# Same-state reservations/linkage/usage are not transition observations.
def transition($state):
  .state == $state and .reason == (if $state == "ready" then "eligible" elif $state == "submitted" then "native_submission" else "native_started" end);

def latency($groups; $from; $to):
  ([$groups[] | ([.[] | select(transition($from)) | .timestamp] | unique) as $a
    | ([.[] | select(transition($to)) | .timestamp] | unique) as $b
    | if ($a | length) != 1 or ($b | length) != 1 then {kind:"unknown"}
      elif $b[0] < $a[0] then {kind:"inverted"}
      else {kind:"valid", ms: ($b[0] - $a[0])} end]) as $pairs
  | distribution([$pairs[] | select(.kind == "valid") | .ms]) + {attempts: ($pairs | length), unknown: ([$pairs[] | select(.kind == "unknown")] | length), inverted: ([$pairs[] | select(.kind == "inverted")] | length)};

# These rows stay internal: identifiers and private paths never enter metric output.
def board_attempts($files):
  [$files[] | . as $f
    | (($f.fast_events // [] | group_by([.coordinatorSessionId, .taskId, .attemptId]) | map({
        board: .[0].taskId, attempt: .[0].attemptId, events: .}))) as $dispatch
    | (($f.receipt_events // [] | unique | group_by([.boardTaskId, .attemptId, .taskId]))) as $receipts
    | ([$receipts[] | . as $r | .[0] as $first
    | ([$dispatch[] | select(.board == $first.boardTaskId and .attempt == $first.attemptId)]) as $d
    | ([$r[] | .phase // empty] + [$d[].events[] | .phase // empty] | unique) as $phases
    | ([$r[] | .parentTaskId // empty] + [$d[].events[] | .parentTaskId // empty] | unique) as $parents
    | ([$d[].events[] | .workerId // empty] | unique) as $workers
    | ($r | map(.ts) | max) as $latest
    | ([$r[] | select(.ts == $latest) | .outcome] | unique) as $outcomes
    | {file: $f.path, has_receipt: true, worker: $first.taskId, board: $first.boardTaskId, attempt: $first.attemptId,
       phase: (if ($phases | length) == 1 then $phases[0] else null end),
       parent: (if ($parents | length) == 1 then $parents[0] else null end),
       phase_conflict: (($phases | length) > 1), parent_conflict: (($parents | length) > 1),
       ts: $latest, outcome: (if ($outcomes | length) == 1 then $outcomes[0] else "unknown" end),
       receipt_counts: ($r | unique_by(del(.ts)) | tally(.outcome)),
       reviewers: ([$r[].reviewerWorkerId // empty] | unique),
       dispatch: (if $first.boardTaskId == null or $first.attemptId == null then "missing_receipt_ids"
         elif ($d | length) == 0 then "no_dispatch"
         elif ($d | length) != 1 or ($workers | length) > 1 then "ambiguous"
         elif ($workers | length) == 0 then "dispatch_worker_missing"
         elif $workers[0] != $first.taskId then "worker_mismatch"
         else "joined" end)}]
      + [$dispatch[] | . as $d
        | select(any($receipts[]; .[0].boardTaskId == $d.board and .[0].attemptId == $d.attempt) | not)
        | ([.events[].workerId // empty] | unique) as $workers
        | ([.events[].phase // empty] | unique) as $phases
        | ([.events[].parentTaskId // empty] | unique) as $parents
        | {file: $f.path, has_receipt: false, board: .board, attempt: .attempt,
           worker: (if ($workers | length) == 1 then $workers[0] else null end),
           phase: (if ($phases | length) == 1 then $phases[0] else null end),
           parent: (if ($parents | length) == 1 then $parents[0] else null end),
           phase_conflict: (($phases | length) > 1), parent_conflict: (($parents | length) > 1),
           ts: null, outcome: "unknown", receipt_counts: {}, reviewers: [], dispatch: "no_receipt"}])[]];

def board_metrics($files):
  board_attempts($files) as $attempts
  | [$attempts[] | select(.has_receipt)] as $rows
  | ([$files[] | .path as $p | .fast_events[]? | [.coordinatorSessionId, .taskId, .attemptId, $p]] | unique) as $dispatches
  | [$rows[] | select(.board != null and .attempt != null)] as $linked
  | {available: (($rows | length) > 0), source: "explicit_coordinator_receipt_ids; optional_dispatch_confirmation",
     actual_runtime_proof: false, receipt_worker_groups: ($rows | length),
     receipt_to_dispatch: ($rows | tally(.dispatch)),
     receipt_to_worker_session: ([$rows[] | . as $r
       | [$files[] | select(.join != null and .join.parent == $r.file and (.join.prefix as $p | $r.worker | startswith($p)))] as $workers
       | ([$attempts[] | select(.worker == $r.worker) | [.file, .board, .attempt]] | unique | length) as $uses
       | ([$attempts[] | select(.file == $r.file and .worker[0:8] == $r.worker[0:8]) | .worker] | unique | length) as $prefixes
       | if $uses != 1 then "reused_worker"
         elif $prefixes != 1 or ($workers | length) > 1 then "ambiguous"
         elif ($workers | length) == 0 then "missing"
         elif ($workers[0].join.models | length) == 1 then "joined_single_model"
         else "mixed_or_unknown_model" end] | tally(.)),
     explicit_board_attempt_worker_groups: ($linked | length),
     board_tasks: ($linked | unique_by([.file, .board]) | length),
     attempts: ($linked | unique_by([.file, .board, .attempt]) | length),
     latest_attempt_outcomes: ($linked | tally(.outcome)),
     receipt_outcomes_deduplicated: sum_counts([$rows[].receipt_counts]),
     phases: ($linked | tally(.phase // "unknown")),
     parent_link_present: ([$linked[] | select(.parent != null)] | length),
     parent_target_known: ([$linked[] | . as $r | select(.parent != null and any($attempts[]; .file == $r.file and .board == $r.parent))] | length),
     parent_conflicts: ([$linked[] | select(.parent_conflict)] | length),
     phase_conflicts: ([$linked[] | select(.phase_conflict)] | length),
     reviewer_worker_claim_present: ([$rows[] | select((.reviewers | length) > 0)] | length),
     dispatch_attempts_observed: ($dispatches | length),
     dispatch_attempts_with_joined_receipt: ([$rows[] | select(.dispatch == "joined")] | unique_by([.file, .board, .attempt]) | length)};

# Transitive explicit board-parent edges only, scoped to one coordinator file.
def board_family($rows; $ids):
  ($ids + [$rows[] | select(.parent as $p | $ids | index($p)) | .board] | unique) as $next
  | if $next == $ids then $ids else board_family($rows; $next) end;

def accepted_cost($files):
  board_attempts($files) as $all
  | [$all[] | select(.board != null and .attempt != null)] as $rows
  | ([$rows[]] | group_by([.file, .board]) | map(
      map(select(.has_receipt)) | select(length > 0) | (map(.ts) | max) as $ts | [.[] | select(.ts == $ts)]
      | select((map(.outcome) | unique) == ["accepted"]) | .[0])) as $accepted
  | [$accepted[] | . as $a | [$rows[] | select(.file == $a.file)] as $local
      | board_family($local; [$a.board]) as $family
      | {file: $a.file, board: $a.board, components: ([$local[] | select(.board as $b | $family | index($b))] as $components
        | $components + [$components[].reviewers[] | . as $id
            | select(any($components[]; .worker == $id) | not)
            | {file: $a.file, board: $a.board, attempt: null, worker: $id, phase: "review", reviewers: [], dispatch: "reviewer_claim"}]
        | unique_by([.file, .board, .attempt, .worker]))}] as $tasks
  | [$tasks[] | . as $task
      | [$task.components[] | . as $r
          | ([$files[] | select(.join != null and .join.parent == $r.file and (.join.prefix as $prefix | ($r.worker | type) == "string" and ($r.worker | startswith($prefix))))]) as $w
          | ([($all + [$tasks[].components[]])[] | select(.worker == $r.worker) | [.file, .board, .attempt]] | unique | length) as $uses
          | ([$tasks[] | select(any(.components[]; .worker == $r.worker))] | length) as $owners
          | ([$rows[] | select(.file == $r.file and .board == $r.board and .attempt == $r.attempt) | .worker] | unique | length) as $attempt_workers
          | ([($all + [$tasks[].components[]])[] | select(.file == $r.file and .worker[0:8] == $r.worker[0:8]) | .worker] | unique | length) as $prefixes
          | (if $r.worker == null then "worker_id_unavailable"
             elif $uses != 1 or $owners != 1 then "reused_worker_or_shared_component"
             elif $attempt_workers > 1 then "ambiguous_attempt"
             elif $prefixes != 1 or ($w | length) > 1 then "ambiguous_worker"
             elif ($w | length) == 0 then "no_worker_session"
             elif ($w[0].join.models | length) != 1 then "mixed_or_unknown_model"
             elif $r.parent_conflict or $r.phase_conflict or ($r.dispatch | IN("ambiguous", "worker_mismatch")) then "conflicting_linkage"
             elif ($w[0].cost.samples // 0) == 0 then "no_valid_cost_samples"
             else "observed" end) as $status
          | {status: $status, phase: ($r.phase // "unknown"),
             missing_reviewer: ([$r.reviewers[] | . as $id | select(any($task.components[]; .worker == $id) | not)] | length),
             cost: (if $status == "observed" then $w[0].cost.observed else null end),
             samples: (if $status == "observed" then $w[0].cost.samples else 0 end),
             duplicate_events: (if ($w | length) == 1 then ($w[0].cost.duplicate_events // 0) else 0 end),
             requests_without_event_id: (if ($w | length) == 1 then ($w[0].cost.requests_without_event_id // 0) else 0 end),
             missing_samples: (if ($w | length) == 1 then (($w[0].cost.requests // 0) - ($w[0].cost.samples // 0)) else 0 end),
             outside_window_requests: (if ($w | length) == 1 then ($w[0].cost.outside_window_requests // 0) else 0 end)}] as $c
      | {components: $c, observed: ([$c[].cost | select(. != null)] | if length > 0 then add else null end)}] as $costs
  | [$costs[].components[]] as $components
  | {available: (any($costs[]; .observed != null)),
     source: "Pi-local assistant usage.cost.total; explicit receipt board/attempt/worker claims and unique parent session worker prefix join",
     scope: "Observed in-window worker estimates only; not full-loaded cost, provider billing, or verified acceptance. Coordinator overhead and unrecorded reviews/repairs are excluded.",
     accepted_board_tasks: ($accepted | length),
     tasks_with_observed_cost: ([$costs[] | select(.observed != null)] | length),
     tasks_without_observed_cost: ([$costs[] | select(.observed == null)] | length),
     observed_cost_per_accepted_board_task: distribution([$costs[].observed | select(. != null)]),
     observed_cost_total: ([$costs[].observed | select(. != null)] | if length > 0 then add else null end),
     components: ($components | tally(.status)), phases: ($components | tally(.phase)),
     valid_cost_samples: ([$components[].samples] | add // 0),
     duplicate_worker_events_excluded: ([$components[].duplicate_events] | add // 0),
     worker_requests_without_dedup_identity: ([$components[].requests_without_event_id] | add // 0),
     missing_or_invalid_cost_samples: ([$components[].missing_samples] | add // 0),
     outside_window_assistant_messages: ([$components[].outside_window_requests] | add // 0),
     reviewer_claims_without_explicit_component: ([$components[].missing_reviewer] | add // 0),
     unrecorded_attempt_review_repair_coverage: "unknown"};

# One sample per file/coordinator/task/attempt, not per replay or observation time.
def native_metrics($files):
  [$files[] | .path as $file | .fast_events[]? | select(.state == "terminal" and (.reason | IN("native_terminal", "native_failed"))) | . + {file: $file}]
  | group_by([.file, .coordinatorSessionId, .taskId, .attemptId]) as $groups
  | [$groups[]
      | ([.[] | {nativeSource, nativeStatus, nativeDurationMs, nativeStartedAt, nativeCompletedAt} | select(.nativeSource != null)] | unique) as $e
      | ([.[].phase // empty] | unique) as $phases
      | ([.[].workerId // empty] | unique) as $workers
      | ([.[].observationSource // "unknown"] | unique) as $observed
      | {observation_source: (if ($observed | length) == 1 then $observed[0] else "ambiguous" end),
         kind: (if ($e | length) == 0 then "unknown_source" elif ($e | length) > 1 or ($phases | length) > 1 or ($workers | length) > 1 then "conflicting" elif $e[0].nativeDurationMs == null then "without_duration" else "measured" end),
         phase: (if ($phases | length) == 1 then $phases[0] else "unknown" end), evidence: $e[0]}] as $rows
  | [$rows[] | select(.kind == "measured")] as $measured
  | {available: (($measured | length) > 0), source: "fast-task-dispatch v1 validated native evidence; record durations require ordered native timestamp pairs",
     timestamp_semantics: "timestamp is observation time, never native completion; recovered observations do not date execution",
     terminal_attempts: ($rows | length), duration_coverage: ($rows | tally(.kind)),
     terminal_observations: ([$groups[][]] | length),
     duplicate_observations_excluded: (([$groups[][]] | length) - ([$groups[][]] | unique | length)),
     invalid_supplied_fields: ([$groups[][] | .invalid_native_fields] | add // 0),
     observation_sources: ([$groups[][] | .observationSource // "unknown"] | tally(.)),
     status_attempts: ([$rows[] | select(.kind != "conflicting")] | length),
     status: ([$rows[] | select(.kind != "conflicting") | .evidence.nativeStatus // "unknown"] | tally(.)),
     native_timestamp_pairs: ([$rows[] | select(.kind != "conflicting" and .evidence.nativeStartedAt != null and .evidence.nativeCompletedAt != null)] | length),
     duration_ms: distribution([$measured[].evidence.nativeDurationMs]),
     by_phase: (reduce ["implementation", "review", "repair", "unknown"][] as $phase ({};
       .[$phase] = distribution([$measured[] | select(.phase == $phase) | .evidence.nativeDurationMs]))),
     by_observation_source: (reduce ["live", "recovered", "unknown", "ambiguous"][] as $source ({};
       .[$source] = distribution([$measured[] | select(.observation_source == $source) | .evidence.nativeDurationMs]))),
     by_source: (reduce ["subagents:completed", "subagents:failed", "subagents:record"][] as $source ({};
       .[$source] = distribution([$measured[] | select(.evidence.nativeSource == $source) | .evidence.nativeDurationMs]))),
     note: "Native execution evidence is not acceptance. Conflicting evidence is excluded; missing/invalid timing is not zero. Observation-source counts include repeats."};

def duration_claims($files):
  [$files[] | .path as $file | .receipt_events[]? | select(.coordinatorReportedDurationMs != null) | . + {file: $file}]
  | unique_by([.file, .taskId, .boardTaskId, .attemptId, .phase, .coordinatorReportedDurationMs]) as $claims
  | {source: "coordinator_reported_task_outcome_receipt", measured_runtime_proof: false,
     claims: ($claims | length),
     receipt_observations_without_duration: ([$files[].receipt_events[]? | select(.coordinatorReportedDurationMs == null)] | unique | length),
     by_phase: (reduce ["implementation", "review", "repair", "unknown"][] as $phase ({};
       .[$phase] = distribution([$claims[] | select((.phase // "unknown") == $phase) | .coordinatorReportedDurationMs]))),
     measured_native_duration_ms: native_metrics($files)};

def checkpoint_identity($files):
  [$files[] | (.provenance // [] | unique) as $events
    | [$events[] | select(.phase == "write-success")] as $writes
    | [$events[] | select(.phase == "proposal")] as $proposals
    | [$events[] | select(.phase == "consumed")] as $consumed
    | ($consumed | group_by(.continuationId)) as $consumption_groups
    | {writes: ($writes | length), notices: ([$events[] | select(.phase == "notice")] | length),
       proposals: ($proposals | length), consumed: ($consumption_groups | length),
       links: [$consumption_groups[] | . as $cg | .[0] as $c
         | [$proposals[] | select(.continuationId == $c.continuationId)] as $p
         | [$writes[] | select(.checkpointId == $c.parentCheckpointId)] as $w
         | if ($cg | length) != 1 then "ambiguous_consumption"
           elif $c.parentCheckpointId == null then "parent_unavailable"
           elif ($p | length) != 1 or ($w | length) != 1 then "missing_or_ambiguous_evidence"
           elif $p[0].checkpointId != $c.parentCheckpointId then "parent_mismatch"
           elif $w[0].ts > $p[0].ts or $p[0].ts > $c.ts then "inverted"
           else "exact_parent" end],
       unconsumed_proposals: ([$proposals[] | . as $p | select(any($consumed[]; .continuationId == $p.continuationId) | not)] | length)}] as $sessions
  | {available: (([$sessions[] | .writes + .proposals + .consumed + .notices] | add // 0) > 0),
     source: "checkpoint-provenance / unattended-continuation.details / continuation-provenance v1",
     successful_writes: ([$sessions[].writes] | add // 0), notices: ([$sessions[].notices] | add // 0),
     proposals: ([$sessions[].proposals] | add // 0), consumed: ([$sessions[].consumed] | add // 0),
     consumption_links: ([$sessions[].links[]] | tally(.)),
     proposals_without_consumption: ([$sessions[].unconsumed_proposals] | add // 0),
     legacy_unknown: ([$files[].provenance_legacy // 0] | add // 0), invalid_metadata: ([$files[].provenance_invalid // 0] | add // 0),
     accepted_usefulness: {available: false, reason: "Consumption observes a completed turn after tagged context; it does not establish reading, acceptance, usefulness, or provider payload contents."}};

def aggregate:
  . as $all
  | ([$all[] | select(type == "object" and has("_candidates")) | ._candidates] | first) as $candidates
  | [$all[] | select(type != "object" or (has("_candidates") | not))] as $scanned
  | [$scanned[] | select(type == "object" and ._unreadable != true and (.has_header | type) == "boolean" and (.nonblank | type) == "number" and (.malformed_lines | type) == "number")] as $valid
  | [$valid[] | select(.has_header == true)] as $files
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
  | ([$scanned[] | select(type == "object" and ._unreadable == true)] | length) as $unreadable
  | (($scanned | length) - ($valid | length) - $unreadable) as $odd
  | ([$files[] | select(.recent)] | length) as $active
  | ([$valid[] | select(.has_header == false and .nonblank == 0)] | length) as $empty
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
            continuations: ([$files[].continuations] | add // 0),
            continuation_linkage: (
              ([$files[].link.linked.exact_parent // 0] | add // 0) as $exact
              | ([$files[].link.linked.temporal // 0] | add // 0) as $temporal
              | ([$files[].link.continue_successes // 0] | add // 0) as $continues
              | {
                  rule: "Same session file; nearest preceding unconsumed successful continue-status checkpoint result with non-inverted event time; consumed once; any other successful checkpoint status clears it. Counts are never matched across files or inferred from totals.",
                  linked_continuations: ($exact + $temporal),
                  linked_by_exact_parent_id: $exact,
                  linked_by_temporal_order: $temporal,
                  unlinked_continuation_entries: ([$files[].link.unlinked // 0] | add // 0),
                  continue_checkpoint_successes: $continues,
                  continue_successes_without_linked_continuation: ($continues - $exact - $temporal),
                  accepted_usefulness: {available: false, reason: "A continuation entry carries no task id or receipt; linkage shows a continuation followed a checkpoint, not that it was accepted or useful."}
                })
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
        board_attempt_outcomes: board_metrics($files),
        phase_duration_claims_ms: duration_claims($files),
        accepted_outcomes: (if $outcomes.available then
            {available: true, source: $outcomes.source, accepted_latest: ($outcomes.latest_outcomes.accepted // 0), denominator_tasks_with_receipt: $outcomes.tasks_with_receipt}
          else {available: false} end),
        rework: (if $outcomes.available then
            {available: true, source: $outcomes.source, tasks_with_rework_history: $outcomes.rework_history_tasks, rework_events: $outcomes.rework_events, denominator_tasks_with_receipt: $outcomes.tasks_with_receipt}
          else {available: false} end)
      },
      task_evidence: (task_evidence($task_rows) + {
        raw_termination_notifications_unique: ([$files[].raw_notifications[]?] | unique | map(fromjson | .[2]) | tally(.)),
        raw_termination_records_unique_tasks: ([$files[].tasks[]? | select(.r != null) | .rr] | tally(.))
      }),
      coordinator_activity: (
        [$files[] | select(.classification != "worker" and .classification != null)] as $coordinators
        | ([$coordinators[].response_durations[]?]) as $durations
        | ([$coordinators[].request_tool_counts[]?]) as $calls
        | ([$coordinators[].compaction_tokens[]?]) as $tokens
        | {
            response_duration_ms: (distribution($durations) + {assistant_messages: ([$coordinators[].models[].requests] | add // 0), missing_or_invalid: (([$coordinators[].models[].requests] | add // 0) - ($durations | length))}),
            tool_calls_per_assistant_message: (distribution($calls) + {total: ($calls | add // 0), missing_content: ([$coordinators[].request_tool_counts_unknown] | add // 0)}),
            compaction_tokens_before: (distribution($tokens) + {compaction_events: ([$coordinators[].compactions] | add // 0), missing_or_invalid: (([$coordinators[].compactions] | add // 0) - ($tokens | length))}),
            turn_tool_calls: {available: false, reason: "No proven turn boundary is recorded in the session entries."},
            context_window: {available: false, reason: "Model context window is not recorded in session entries."}
          }),
      dispatch_lifecycle: (
        ([$files[] | .path as $path | .fast_events[]? | . + {file: $path}] | group_by([.file, .coordinatorSessionId, .taskId, .attemptId])) as $groups
        | {attempts: ($groups | length), rejected_events: ([$files[].fast_invalid // 0] | add // 0),
           ready_to_submitted_ms: latency($groups; "ready"; "submitted"), submitted_to_started_ms: latency($groups; "submitted"; "started"),
           native_evidence: native_metrics($files),
           first_token_ms: {available: false, reason: "No native first-token timestamp contract."},
           transition_rule: "Designated reasons: eligible / native_submission / native_started; repeated designated timestamps are ambiguous, not first readiness. Same-state reserved, worker_linked and runtime_observed do not retime transitions.",
           rolling_refill: {
             completion_to_replacement_start_ms: {available: false, reason: "No explicit release-to-admission or predecessor/successor linkage."},
             submission_reaction_ms: {available: false, reason: "No explicit release/admission causal identity; submission may precede completion."},
             occupancy: {available: false, reason: "No authoritative occupancy/capacity lifecycle attribution."},
             unpaired_event_coverage: {
               terminal_observations: ([$groups[][] | select(.state == "terminal" and (.reason | IN("native_terminal", "native_failed")))] | unique | length),
               terminal_live_or_recovered_unknown: ([$groups[][] | select(.state == "terminal" and (.reason | IN("native_terminal", "native_failed")) and .observationSource == null)] | unique | length),
               designated_start_observations: ([$groups[][] | select(transition("started"))] | unique | length),
               designated_submission_observations: ([$groups[][] | select(transition("submitted"))] | unique | length),
               causally_paired: 0},
             note: "All observations are unpaired; no nearest-event inference. Observation timestamps are not authoritative native execution times."},
           blocked_events: ([$groups[][] | select(.state == "blocked")] | length),
           blocked_reasons: ([$groups[][] | select(.state == "blocked") | .reason // "unknown"] | tally(.)),
           reason_schema: "fast-task-dispatch.REASONS v1 allowlist; unknown codes remain unknown.",
           provenance: (
             ([$groups[] | ([.[] | select(.requestedModel != null) | .requestedModel | safe_label] | unique) as $requested
               | ([.[] | select(.actualSource == "subagents:usage" and .actualModel != null) | .actualModel | safe_label] | unique) as $actual
               | ([.[] | select(.actualSource == "subagents:usage" and (.actualEffort | IN("off", "minimal", "low", "medium", "high", "xhigh", "max"))) | .actualEffort] | unique) as $effort
               | ([.[] | select(.requestedEffort | IN("off", "minimal", "low", "medium", "high", "xhigh", "max")) | .requestedEffort] | unique) as $requested_effort
               | {requested_effort: (if ($requested_effort | length) == 1 then $requested_effort[0] else null end),
                  requested_effort_coverage: (if ($requested_effort | length) == 0 then "unknown" elif ($requested_effort | length) == 1 then "known" else "ambiguous" end),
                  actual_effort_coverage: (if ($effort | length) == 0 then "unknown" elif ($effort | length) == 1 then "known" else "ambiguous" end), requested: (if ($requested | length) == 1 then $requested[0] else null end), actual: (if ($actual | length) == 1 then $actual[0] else null end), effort: (if ($effort | length) == 1 then $effort[0] else null end)}]) as $p
             | {requested_is_runtime_proof: false, actual_source: "subagents:usage",
                requested_model: ([$p[] | select(.requested != null) | .requested] | tally(.)),
                actual_model: ([$p[] | select(.actual != null) | .actual] | tally(.)),
                actual_effort: ([$p[] | select(.effort != null) | .effort] | tally(.)),
                requested_effort: ([$p[] | select(.requested_effort != null) | .requested_effort] | tally(.)),
                requested_vs_actual_effort: ([$p[] | select(.requested_effort != null and .effort != null) | "requested=" + .requested_effort + " actual=" + .effort] | tally(.)),
                effort_coverage: {attempts: ($p | length), requested: ($p | tally(.requested_effort_coverage)), actual: ($p | tally(.actual_effort_coverage)),
                  comparable: ([$p[] | select(.requested_effort != null and .effort != null)] | length)},
                requested_and_actual: ([$p[] | select(.requested != null and .actual != null) | "requested=" + .requested + " actual=" + .actual] | tally(.)),
                actual_model_unknown_or_ambiguous: ([$p[] | select(.actual == null)] | length)})}
      ),
      quota_cache: (
        ([$files[].quota.fetch[]?]) as $fetch
        | {fetch_duration_ms: distribution($fetch), refresh_reason: sum_counts([$files[].quota.refresh // {}]),
           invalid_events: ([$files[].quota.invalid_events // 0] | add // 0), invalid_observations: ([$files[].quota.invalid_observations // 0] | add // 0),
           providers: (reduce ($files[].quota.observations // {} | to_entries[]) as $e ({};
             .[$e.key].hit += $e.value.hit | .[$e.key].miss += $e.value.miss | .[$e.key].unknown += $e.value.unknown | .[$e.key].ages += $e.value.ages)
             | with_entries(.value.age_ms = distribution(.value.ages) | del(.value.ages))),
           typed_results: {available: (([$files[].quota_typed_results // 0] | add // 0) > 0),
             source: "quota_status toolResult.details bounded status/cache fields",
             results: ([$files[].quota_typed_results // 0] | add // 0),
             invalid: ([$files[].quota_typed_invalid // 0] | add // 0),
             rows: ([$files[].quota_typed[]?] | length),
             status: ([$files[].quota_typed[]?] | tally(.status)),
             reuse: ([$files[].quota_typed[]?] | tally(.reuse)),
             cache_bounds_at_result: ([$files[].quota_typed[]?] | tally(.cache_bounds)),
             by_provider: ([$files[].quota_typed[]?] | group_by(.provider) | map({key: .[0].provider, value: {status: tally(.status), reuse: tally(.reuse), cache_bounds_at_result: tally(.cache_bounds)}}) | from_entries),
             discard_cause: {available: false, reason: "Typed result reports status, not an explicit publication-discard cause."}},
           typed_result_linkage: {available: false, reason: "Custom quota metrics have no tool-call identity; custom and typed result populations are separate, never nearest-paired."},
           note: "Cache hit or low age does not establish freshness. Producer-reported status and cache bounds are separate; within TTL does not prove provider/account freshness. Unknown provenance is not a miss."}
      ),
      future_evidence: {
        policy_receipts: {
          source: "task-outcome-activation schemaVersion 1",
          valid: ([$files[].activation.valid // 0] | add // 0),
          invalid: ([$files[].activation.invalid // 0] | add // 0),
          sources: sum_counts([$files[].activation.sources // {}]),
          extension_hash_present: ([$files[].activation.extension_hash_present // 0] | add // 0),
          policy_hash_present: ([$files[].activation.policy_hash_present // 0] | add // 0),
          note: "Observed file hashes do not prove executed bytes or policy consumption; missing hashes are unknown."
        },
        accepted_board_task_cost: accepted_cost($files),
        checkpoint_parent_identity: checkpoint_identity($files)
      },
      observability: {
        direct_codemode_tool_calls: ([$files[].codemode_calls // 0] | add // 0),
        direct_structured_unattended_checkpoint_attempts: ([$files[].checkpoints[]] | add // 0),
        nested_typed_calls: (reduce ($files[].nested_calls // {} | to_entries[]) as $e ({};
          .[$e.key].calls += $e.value.calls | .[$e.key].timed += ($e.value.timed // 0) | .[$e.key].duration_ms += ($e.value.duration_ms // 0) | .[$e.key].errors += ($e.value.errors // 0))),
        note: "Direct counts are separate from allowlisted typed nestedCalls metadata; nested arguments and code are not parsed. Durations and errors reflect only recorded metadata."
      },
      scan_reconciliation: (
        ([$files[] | select(.classification != null)] | length) as $classified
        | {
            candidates: $candidates,
            scanned: ($scanned | length),
            session_files_with_window_activity: $active,
            session_files_without_window_activity: (($files | length) - $active),
            headerless_nonempty: ([$valid[] | select(.has_header == false and .nonblank > 0)] | length),
            headerless_empty: $empty,
            unreadable: $unreadable,
            classified_main_fork_worker: $classified,
            candidates_match_scanned: ($candidates == ($scanned | length)),
            unexpected_summary_shape: $odd,
            partition_balanced: (($scanned | length) == (($files | length) + ([$valid[] | select(.has_header == false)] | length) + $unreadable + $odd)),
            classification_balanced: ($classified == $active),
            partition_residual: (($scanned | length) - (($files | length) + ([$valid[] | select(.has_header == false)] | length) + $unreadable + $odd)),
            candidate_partition: (
              ([$valid[] | select(.has_header == false and .nonblank > 0 and .nonblank > .malformed_lines)] | length) as $h_events
              | ([$valid[] | select(.has_header == false and .nonblank > 0 and .nonblank == .malformed_lines)] | length) as $h_bad
              | {
                  session_with_window_activity: $active,
                  session_without_window_activity: (($files | length) - $active),
                  headerless_with_parsed_events: $h_events,
                  headerless_all_lines_malformed: $h_bad,
                  headerless_empty: $empty,
                  unreadable: $unreadable,
                  unexpected_summary_shape: $odd,
                  informational_subsets: {session_header_only: ([$files[] | select(.nonblank_events_header_only == true)] | length)},
                  explained_total: ($files | length) + $h_events + $h_bad + $empty + $unreadable + $odd,
                  fully_explained: ((($files | length) + $h_events + $h_bad + $empty + $unreadable + $odd) == ($scanned | length))
                }),
            error_categories_match_errors: (([$files[].errors[]] | add // 0) == ([$files[].auth_categories[]] | add // 0))
          }
      ),
      limitations: [
        "Direct tool-call metrics exclude nested calls; recognized typed nestedCalls metadata is reported separately. Files last modified before --since are skipped.",
        "Worker overlap is a first/last logged-span proxy, not actual execution concurrency or a guaranteed lifecycle upper bound.",
        "Terminal statuses come from notifications logged in the parent session, so they are counted per unique notification, not attributed to individual worker sessions or models. Model metrics count assistant messages; missing usage fields count as 0.",
        "No nested codemode code or argument parsing or tool-definition counting. Checkpoint calls are attempts, not saved files or accepted outcomes; done is not acceptance.",
        "Handoffs count only custom/custom_message unattended-handoff and compaction-handoff entries (state writes are not necessarily handoffs). Model changes are observed selections/transitions, not automatic fallbacks.",
        "Headerless JSONL is excluded from session metrics. Malformed/skipped lines include invalid JSON/unicode and raw replacement characters; scan counters cover entire candidate files, not timed events.",
        "Model selection classification uses preceding logged model_change/assistant metadata; missing history can make the first observed selection initial.",
        "Task outcomes come only from valid coordinator-written task-outcome-receipt entries (latest verdict per task per coordinator file; rework counted from history); they are not actual-runtime proof, and no receipts means unavailable, not zero quality. Check artifacts are only counted, never read.",
        "task_evidence joins notification/subagents:record task IDs to worker session_info Type#first8(taskId) only for a unique prefix within the same parent session; actual model requires exactly one assistant provider/model in the worker file, otherwise it is mixed/unmatched. Requested model/effort come from the direct Agent tool call matching the notification tool-use-id in the same file; runtime effort is unknown and reported (receipt) model is separate.",
        "Raw termination labels are a fixed enum of the notification <status> text or subagents:record status (task_evidence.raw_termination*); the normalized status counts are unchanged, so wrapped_up/aborted/steered/explicit turn-cap labels all still collapse into normalized turn_limit there. Steered notifications appear only in raw notification counts. Raw labels are never a cause proof.",
        "Continuation linkage is conservative same-file ordering (or exact parent id when present) between a successful continue checkpoint result and the next unattended-continuation entry; unlinked entries are notices or unprovable. Linkage is not acceptance or usefulness: no task id exists on continuation entries. Cost per accepted task and applied continuation/effort provenance need a new event producer and are unavailable. Terminal tasks without a valid same-file outcome receipt are counted in task_outcomes.coverage.",
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
        non_session_jsonl_files: ([$valid[] | select(.has_header == false)] | length),
        skipped_lines: ([$valid[] | .malformed_lines // 0] | add // 0),
        malformed_lines: ([ $valid[] | .malformed_lines // 0 ] | add // 0),
        unreadable_files: ([$scanned[] | select(type == "object" and ._unreadable == true)] | length)
      }
    };

if $mode == "time" then $time | epoch
elif $mode == "aggregate" then aggregate
else scan_file end
