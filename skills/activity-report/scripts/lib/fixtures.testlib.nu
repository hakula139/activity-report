# ==================================================================================================
# Activity Report: Fixtures
# ==================================================================================================
# Builders shared by the test files, and the digest's invocation on a fixture home.
# ==================================================================================================

use std/assert

const SCRIPT = path self "../activity-report.nu"

export const DAY = "2026-10-15"
const HUMAN = {origin: {kind: "human"}}

# A clock time on the reported day, or a full date and time.
export def at [clock: string]: nothing -> string {
  if ($clock | str contains "T") {
    $"($clock):00.000Z"
  } else {
    $"($DAY)T($clock):00.000Z"
  }
}

export def transcript [dir: string, path: list<string>, records: list]: nothing -> nothing {
  let file = ($dir | path join ...$path)
  mkdir ($file | path dirname)

  $records
  | each { to json --raw }
  | str join "\n"
  | save $file
}

# A repository whose checkout the digest can find, ignoring agent scratch like the real ones.
export def git-repo [dir: string, name: string]: nothing -> string {
  let path = ($dir | path join $name)
  mkdir $path

  (
    ^git
      -C $path
      init --quiet
  )

  ".claude/agent-memory-local/\n" | save ($path | path join ".gitignore")
  ^git -C $path add ".gitignore"

  (
    ^git
      -C $path
      -c "user.name=test"
      -c "user.email=test@test"
      commit
        --quiet
        -m "init"
  )

  $path | path expand
}

export def claude-user [
  cwd: string
  clock: string
  text: string
  extra: record = {}
]: nothing -> record {
  {type: "user", cwd: $cwd, timestamp: (at $clock), message: {role: "user", content: $text}}
  | merge $extra
}

export def claude-prompt [cwd: string, clock: string, text: string]: nothing -> record {
  claude-user $cwd $clock $text $HUMAN
}

export def claude-queued [
  cwd: string
  clock: string
  text: string
  kind: string = "human"
]: nothing -> record {
  let attachment = {type: "queued_command", origin: {kind: $kind}, prompt: $text}
  {type: "attachment", cwd: $cwd, timestamp: (at $clock), attachment: $attachment}
}

export def claude-notification [cwd: string, clock: string]: nothing -> record {
  claude-user $cwd $clock "<task-notification>" {origin: {kind: "task-notification"}}
}

# An AskUserQuestion result carries the answers the person gave, keyed by question.
export def claude-answered [cwd: string, clock: string, answers: record]: nothing -> record {
  let content = [{type: "tool_result", content: "The user answered.", tool_use_id: "tool"}]
  let result = {questions: [], answers: $answers, annotations: {}}
  let message = {role: "user", content: $content}
  {type: "user", cwd: $cwd, timestamp: (at $clock), isSidechain: false, message: $message}
  | insert toolUseResult $result
}

# An unanswered question carries no answers, and names the timeout that ended it.
export def claude-timed-out [cwd: string, clock: string]: nothing -> record {
  let content = [{type: "tool_result", content: "No response after 300s.", tool_use_id: "tool"}]
  let result = {questions: [], answers: {}, afkTimeoutMs: 300000, annotations: {}}
  let message = {role: "user", content: $content}
  {type: "user", cwd: $cwd, timestamp: (at $clock), isSidechain: false, message: $message}
  | insert toolUseResult $result
}

export def claude-reply [cwd: string, clock: string, text: string = "done"]: nothing -> record {
  let message = {stop_reason: "end_turn", content: [{type: "text", text: $text}]}
  {type: "assistant", cwd: $cwd, timestamp: (at $clock), message: $message}
}

# Assistant records through a turn, since a gap longer than 30 minutes ends its span.
export def claude-active [cwd: string, clocks: list<string>]: nothing -> list<record> {
  $clocks
  | each {|clock|
    let message = {stop_reason: null, content: [{type: "thinking", thinking: ""}]}
    {type: "assistant", cwd: $cwd, timestamp: (at $clock), message: $message}
  }
}

export def claude-tool [
  cwd: string
  clock: string
  name: string
  input: record
]: nothing -> record {
  let content = [{type: "tool_use", id: "tool", name: $name, input: $input}]
  let message = {role: "assistant", stop_reason: "tool_use", content: $content}
  {type: "assistant", cwd: $cwd, timestamp: (at $clock), message: $message}
}

export def claude-subagent [
  dir: string
  project: string
  lead: string
  id: string
  meta: record
  records: list
]: nothing -> nothing {
  transcript $dir ["claude/projects" $project $lead "subagents" $"agent-($id).jsonl"] $records

  let path = [$dir "claude/projects" $project $lead "subagents" $"agent-($id).meta.json"]
  $meta
  | to json
  | save --force ($path | path join)
}

export def codex-event [clock: string, payload: record]: nothing -> record {
  {type: "event_msg", timestamp: (at $clock), payload: $payload}
}

export def codex-model [clock: string]: nothing -> record {
  let payload = {type: "message", role: "assistant", content: [{type: "output_text", text: ""}]}
  {type: "response_item", timestamp: (at $clock), payload: $payload}
}

# A turn's task start, its prompt a second later with `text`, and its completion at a `done` time.
export def codex-turn [clock: string, text?: string, --done: string]: nothing -> list<record> {
  let id = $"turn-($clock)"
  let item = {type: "UserMessage", content: [{type: "text", text: $text}]}
  let prompt_at = ((at $clock | into datetime) + 1sec | format date "%Y-%m-%dT%H:%M:%S%.3fZ")
  [
    (codex-event $clock {type: "task_started", turn_id: $id})
    (
      if $text != null {
        {
          type: "event_msg"
          timestamp: $prompt_at
          payload: {type: "item_completed", item: $item, turn_id: $id}
        }
      }
    )
    (if $done != null { codex-event $done {type: "task_complete", last_agent_message: "ok"} })
  ]
  | compact
}

export def codex-file-change [clock: string, changes: record]: nothing -> record {
  let item = {type: "FileChange", id: "change", status: "completed", changes: $changes}
  codex-event $clock {type: "item_completed", item: ($item | merge {stdout: "", stderr: ""})}
}

export def codex-transcript [
  dir: string
  meta: record
  records: list<record>
  --archived
  --compressed
]: nothing -> nothing {
  let path = if $archived {
    ["codex/archived_sessions" $"rollout-($DAY)T00-00-00-($meta.id).jsonl"]
  } else {
    ["codex/sessions" ...($DAY | split row "-") $"rollout-($DAY)T00-00-00-($meta.id).jsonl"]
  }

  transcript $dir $path ([{type: "session_meta", payload: $meta}] ++ $records)

  if $compressed {
    (
      ^zstd ($dir | path join ...$path)
        --quiet
        --force
        --rm
    )
  }
}

export def omp-user [clock: string, text: string, --agent]: nothing -> record {
  let attribution = if $agent { "agent" } else { "user" }
  let message = {role: "user", attribution: $attribution, content: $text}
  {type: "message", timestamp: (at $clock), message: $message}
}

export def omp-reply [clock: string, text: string = "done"]: nothing -> record {
  let message = {role: "assistant", stopReason: "stop", content: $text}
  {type: "message", timestamp: (at $clock), message: $message}
}

export def omp-tool [clock: string, calls: list]: nothing -> record {
  let message = {role: "assistant", stopReason: "toolUse", content: $calls}
  {type: "message", timestamp: (at $clock), message: $message}
}

export def digest-run [
  dir: string
  overrides: record = {}
  --excerpt-chars: int = 400
  --from: string
  --to: string
  --tz: string = "UTC"
]: nothing -> record {
  let config_file = ($dir | path join "config.toml")

  let config = (
    {
      excluded_dirs: ["/[^/]+__worktrees/workmux-"]
      labels: {default: ["work"], projects: {dotfiles: ["personal"]}}
      hours: {
        reading_minutes: 10
        max_minutes: 60
        agent_max_minutes: 120
        agent_idle_minutes: 30
      }
      assistants: {
        claude: ($dir | path join "claude")
        codex: ($dir | path join "codex")
        omp: ($dir | path join "omp")
      }
    }
    | merge deep --strategy overwrite $overrides
  )

  $config
  | to toml
  | save --force $config_file

  let args = (
    ([digest --config $config_file ($from | default $DAY) $to] | compact)
    ++ [$"--excerpt-chars=($excerpt_chars)"]
  )
  with-env {TZ: $tz} {
    (
      ^$nu.current-exe --no-config-file $SCRIPT ...$args
      | complete
    )
  }
}

export def digest-output [
  dir: string
  overrides: record = {}
  --excerpt-chars: int = 400
  --from: string
  --to: string
  --tz: string = "UTC"
]: nothing -> record {
  let run = (
    digest-run $dir $overrides --excerpt-chars=$excerpt_chars --from=$from --to=$to --tz=$tz
  )
  assert equal $run.exit_code 0 $run.stderr

  $run.stdout | from json
}

# Run the digest in UTC, so the fixtures' `Z` timestamps read as local times.
export def digest-day [
  dir: string
  overrides: record = {}
  --excerpt-chars: int = 400
]: nothing -> record {
  digest-output $dir $overrides --excerpt-chars=$excerpt_chars | get days.0
}
