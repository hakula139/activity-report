#!/usr/bin/env nu

# ==================================================================================================
# Activity Digest: Transcript Tests
# ==================================================================================================

use std/assert

use ./lib/fixtures.testlib.nu *

def "test NUL-only transcript records warn and preserve the remaining activity" [] {
  for tool in ["claude" "codex"] {
    let dir = (mktemp --directory)

    let file = if $tool == "claude" {
      let path = ["claude/projects/app/a.jsonl"]
      transcript $dir $path [
        (claude-prompt "/work/app" "10:00" "first task")
        (claude-reply "/work/app" "10:30" "first result")
        (claude-prompt "/work/app" "11:00" "second task")
        (claude-reply "/work/app" "11:30" "second result")
      ]

      $dir | path join ...$path
    } else {
      codex-transcript $dir {id: "a", cwd: "/work/app", thread_source: "user"} [
        ...(codex-turn "10:00" "first task" --done "10:30")
        ...(codex-turn "11:00" "second task" --done "11:30")
      ]
      let path = ["codex/sessions" ...($DAY | split row "-") $"rollout-($DAY)T00-00-00-a.jsonl"]

      $dir | path join ...$path
    }
    let expected = (digest-output $dir)

    let lines = (open --raw $file | lines)
    [($lines | first) "\u{0}\u{0}" ...($lines | skip 1)]
    | str join "\n"
    | save --force $file

    if $tool == "codex" {
      (
        ^zstd $file
          --quiet
          --force
          --rm
      )
    }

    let run = (digest-run $dir)
    assert equal $run.exit_code 0 $"($tool): ($run.stderr)"

    assert equal ($run.stdout | from json) $expected $tool
    assert str contains $run.stderr $"Skipped NUL-only transcript records in ($file)" $tool
    assert str contains $run.stderr ": 1" $tool
  }
}

def "test records written out of order keep their time order" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt "/work/app" "10:00" "first")
    (claude-reply "/work/app" "10:20" "done")
    (claude-prompt "/work/app" "10:05" "second")
  ]

  let day = (digest-day $dir --excerpt-chars 0)

  assert equal ($day.sessions.0.prompts | select at text agent) [
    {at: "10:00", text: "first", agent: 0.0833}
    {at: "10:05", text: "second", agent: 0.25}
  ]
  assert equal $day.sessions.0.replies [{at: "10:20", text: "done"}]
}

def "test steering prompts and triggers share the first reply" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt "/work/app" "10:00" "start")
    (claude-queued "/work/app" "10:05" "also check tests")
    (claude-notification "/work/app" "10:08")
    (claude-reply "/work/app" "10:30")
  ]

  let day = (digest-day $dir)

  assert equal $day.sessions.0.replies [{at: "10:30", text: "done"}]
  assert equal ($day.sessions.0.prompts | select at text) [
    {at: "10:00", text: "start"}
    {at: "10:05", text: "also check tests"}
  ]
  assert equal ($day.sessions.0.prompts | get hours) [0.0833 0.5833]
  assert equal ($day.sessions.0.prompts | get agent) [0.0833 0.4167]
}

def "test a reply-less turn ends at its last model record" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt "/work/app" "10:00" "P")
    ...(claude-active "/work/app" ["10:10" "10:20"])
    (claude-prompt "/work/app" "10:25" "Q")
  ]

  let day = (digest-day $dir)

  assert equal ($day.sessions.0.prompts | select at agent) [
    {at: "10:00", agent: 0.3333}
    {at: "10:25", agent: 0}
  ]
}

def "test a turn with no model output earns nothing" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt "/work/app" "10:00" "P")
    (claude-prompt "/work/app" "10:05" "Q")
  ]

  let day = (digest-day $dir)

  assert equal ($day.sessions.0.prompts | select at agent) [
    {at: "10:00", agent: 0}
    {at: "10:05", agent: 0}
  ]
}

def "test canceled Codex turns cannot borrow a later reply" [] {
  let dir = (mktemp --directory)
  let prompt = {type: "UserMessage", content: [{type: "text", text: "start"}]}
  codex-transcript $dir {id: "canceled", cwd: "/work/app", thread_source: "user"} [
    (codex-event "10:00" {type: "task_started", turn_id: "first"})
    (codex-event "10:00" {type: "item_completed", item: $prompt, turn_id: "first"})
    (codex-event "10:01" {type: "turn_aborted", turn_id: "first"})
    (codex-event "13:00" {type: "task_started", turn_id: "second"})
    (codex-model "13:05")
    (codex-event "13:10" {type: "task_complete", last_agent_message: "done"})
    (codex-event "13:11" {type: "turn_aborted", turn_id: "second"})
    (codex-event "13:12" {type: "task_complete", last_agent_message: "final"})
  ]

  let day = (digest-day $dir)

  assert equal $day.sessions.0.prompts.0.hours 0.1667
  assert equal $day.sessions.0.prompts.0.agent 0.1667
  assert equal $day.sessions.0.replies [{at: "13:12", text: "final"}]
}

def "test a stalled delegate earns only the time before its gap" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lead = "aaaabbbb-0000-4000-8000-000000000009"
  transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
    (claude-prompt $app "09:55" "P")
    (claude-reply $app "10:00" "first")
  ]
  claude-subagent $dir "app" $lead "a" {agentType: "implementer", toolUseId: "t", spawnDepth: 1} [
    (claude-user $app "10:05" "task" {isSidechain: true})
    ...(claude-active $app ["10:25" "10:45"])
    (claude-tool $app "13:45" "SubagentHandback" {})
  ]

  let day = (digest-day $dir)

  assert equal $day.sessions.0.prompts.0.agent 0.75
}

def "test a gap of exactly the idle threshold keeps the turn span" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-notification "/work/app" "10:00")
    ...(claude-active "/work/app" ["10:30"])
    (claude-reply "/work/app" "11:00")
  ]

  let day = (digest-day $dir)

  assert equal $day.runs.0.agent 1
}

def "test a turn ends at its first long gap" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-notification "/work/app" "10:00")
    ...(claude-active "/work/app" ["10:10" "10:50" "11:00" "12:00"])
    (claude-reply "/work/app" "12:05")
  ]

  let day = (digest-day $dir)

  assert equal $day.runs.0.agent 0.1667
}

def "test a later turn gap does not cut an earlier turn" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-notification "/work/app" "10:00")
    ...(claude-active "/work/app" ["10:05"])
    (claude-notification "/work/app" "10:10")
    ...(claude-active "/work/app" ["10:15" "10:20"])
    (claude-reply "/work/app" "11:30")
  ]

  let day = (digest-day $dir)

  assert equal $day.runs.0.agent 0.3333
}

def "test each tool turn ends at its last record before a long gap" [] {
  let dir = (mktemp --directory)
  let item = {type: "UserMessage", content: [{type: "text", text: "go"}]}
  codex-transcript $dir {id: "codex", cwd: "/work/app", thread_source: "user", source: "exec"} [
    (codex-event "10:00" {type: "task_started", turn_id: "t"})
    (codex-event "10:00" {type: "item_completed", item: $item, turn_id: "t"})
    (codex-event "10:20" {type: "token_count"})
    (codex-event "11:30" {type: "task_complete", last_agent_message: "ok"})
  ]
  transcript $dir ["omp/sessions/app/a.jsonl"] [
    {type: "session", id: "omp", cwd: "/work/app"}
    (omp-user "12:00" "go" --agent)
    (omp-tool "12:20" [{type: "toolCall", id: "r", name: "read", arguments: {path: "x"}}])
    (omp-reply "13:30")
  ]

  let day = (digest-day $dir)

  assert equal ($day.runs | select tool agent) [
    {tool: "codex", agent: 0.3333}
    {tool: "omp", agent: 0.3333}
  ]
}
