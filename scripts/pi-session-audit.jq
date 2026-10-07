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
  | if $name == "get_subagent_result" then
      (if ($block.id | type) == "string" then .calls[$block.id] = $args.agent_id else . end)
      | if $in_window then .retrieval.attempts += 1 else . end
    elif $in_window and $name == "Agent" then dispatch($args)
    elif $in_window and ($name == "bash" or $name == "Bash") then
      .bash.calls += 1
      | if ($args | has("timeout")) and $args.timeout != null then .bash.timeout_argument_present += 1 else . end
      | if ($args.timeout | type) == "number" and $args.timeout > 3600 then .bash.timeout_over_3600s += 1 else . end
      | .bash.by_value |= bump(timeout_label($args))
    else . end;

def process_event($event):
  ($event.timestamp | epoch) as $timestamp
  | ($timestamp != null and $timestamp >= $cutoff) as $in_window
  | if $event.type == "session" then
      .created = (if .created == null then $timestamp else .created end)
      | if ($event.parentSession | type) == "string" then .parent_session = $event.parentSession else . end
    else . end
  | if $event.type == "session_info" and ($event.name | type) == "string"
      and ($event.name | test("^[^#\\s]+#[A-Za-z0-9_-]{8}$")) then
      .worker_name = ($event.name | split("#")[0] | safe_label)
    else . end
  | if $timestamp != null then
      .earliest = (if .earliest == null then $timestamp else ([.earliest, $timestamp] | min) end)
      | if $in_window then
          .recent = true
          | .first_recent = (if .first_recent == null then $timestamp else ([.first_recent, $timestamp] | min) end)
          | .last_recent = (if .last_recent == null then $timestamp else ([.last_recent, $timestamp] | max) end)
        else . end
    else . end
  | if $in_window and $event.customType == "subagent-notification" then
      ($event.content | terminal_status) as $status
      | if $status == null then . else
          (if ($event.content | type) == "string" then
             (try ($event.content | capture("<task-id>(?<value>[^<]{0,128})</task-id>"; "i").value) catch $event.id)
           else $event.id end) as $identity
          | (if ($identity | type) == "string" or ($identity | type) == "number" or ($identity | type) == "boolean" then $identity else .line_number end) as $identity
          | .notifications |= (. + [([$path, $identity, $status] | tojson)] | unique)
        end
    else . end
  | if ($event.message | type) != "object" then .
    elif $event.message.role == "assistant" and ($event.message.content | type) == "array" then
      reduce $event.message.content[] as $block (.;
        if ($block | type) == "object" and $block.type == "toolCall" then handle_block($block; $in_window) else . end
      )
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
      line_number: 0, malformed_lines: 0, created: null, parent_session: null, worker_name: null,
      earliest: null, first_recent: null, last_recent: null, recent: false,
      bash: {calls: 0, timeout_argument_present: 0, timeout_over_3600s: 0, by_value: {}},
      dispatch: {max_turns: {}, model: {}, thinking: {}, background: {}, resume: {}},
      notifications: [], calls: {}, retrieval: {attempts: 0, results: 0, misses: 0, targets: []}
    };
    .line_number += 1
    | if ($line | test("^\\s*$")) then .
      else (try {ok: true, event: ($line | fromjson)} catch {ok: false}) as $parsed
      | if ($parsed.ok | not) or ($parsed.event | type) != "object" then .malformed_lines += 1
        else process_event($parsed.event)
        end
      end
  )
  | . as $summary
  | {
      recent: $summary.recent,
      malformed_lines: $summary.malformed_lines,
      bash: $summary.bash,
      dispatch: $summary.dispatch,
      notifications: $summary.notifications,
      retrieval: $summary.retrieval
    }
  + (if $summary.recent then
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

def aggregate:
  . as $files
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
  | {
      window_start_local: $window_start_local,
      limitations: [
        "Counts direct tool calls only; nested codemode calls are uncounted. Files last modified before --since are skipped.",
        "Worker overlap is a first/last logged-span proxy, not actual execution concurrency or a guaranteed lifecycle upper bound."
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
        duplicate_misses: ([ $files[] | .retrieval.misses // 0 ] | add // 0) - $unique_misses
      },
      scan: {
        files: ($files | length),
        malformed_lines: ([ $files[] | .malformed_lines // 0 ] | add // 0),
        unreadable_files: ([$files[] | select(._unreadable == true)] | length)
      }
    };

if $mode == "time" then $time | epoch
elif $mode == "aggregate" then aggregate
else scan_file end
