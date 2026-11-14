#!/usr/bin/env nu

# ==================================================================================================
# Activity Report: Units Tests
# ==================================================================================================

use std/assert

use ./lib/fixtures.testlib.nu *

def "test a prompt queued while a question waits keeps its own unit" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt "/work/app" "10:00" "start")
    (claude-answered "/work/app" "10:05" {"Which repo?": "app"})
    (claude-queued "/work/app" "10:03" "also run the tests")
    (claude-reply "/work/app" "10:20" "done")
  ]

  let day = (digest-day $dir --excerpt-chars 0)

  assert equal (($day | where kind == "prompt") | select from agent) [
    {from: "2026-10-15T10:00:00+00:00", agent: 0.05}
    {from: "2026-10-15T10:03:00+00:00", agent: 0.0333}
    {from: "2026-10-15T10:05:00+00:00", agent: 0.25}
  ]
}

def "test Claude subagents, forks, and teammates credit the prompt whose turn started them" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lib = (git-repo $dir "lib")
  mkdir ($app | path join "src")
  let lead = "1a2b3c4d-0000-4000-8000-000000000001"
  transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
    (claude-prompt $app "10:00" "P1")
    (claude-reply $app "10:10" "first")
    (claude-prompt $app "10:20" "P2")
    (claude-reply $app "10:25" "second")
  ]
  claude-subagent $dir "app" $lead "a" {agentType: "implementer", toolUseId: "t", spawnDepth: 1} [
    (claude-user $lib "10:01" "task" {isSidechain: true})
    ...(claude-active $app ["10:03"])
    (claude-user $app "10:15" "relay" {isSidechain: true, isMeta: true, origin: {kind: "human"}})
    ...(claude-active $app ["10:21"])
    (claude-tool $app "10:22" "SubagentHandback" {})
    (claude-user $app "10:26" "continue" {isSidechain: true})
    ...(claude-active $app ["10:27"])
    (claude-tool $app "10:28" "SubagentHandback" {})
  ]
  claude-subagent $dir "app" $lead "f" {
    agentType: "fork"
    isFork: true
    parentAgentId: "a"
    spawnDepth: 2
  } [
    (claude-user $app "10:21" "fork" {isSidechain: true})
    ...(claude-active $app ["10:21"])
    (claude-tool $app "10:23" "SubagentHandback" {})
  ]
  let teammate = '<teammate-message teammate_id="team-lead">work</teammate-message>'
  transcript $dir ["claude/projects/app/99999999-0000-4000-8000-000000000001.jsonl"] [
    (claude-user $app "10:05" $teammate {teamName: "session-1a2b3c4d", agentName: "fix"})
    ...(claude-active $app ["10:06"])
    (claude-reply $app "10:07" "done")
  ]

  let day = (digest-day $dir)

  assert equal $day.0.agent 0.5833
  assert equal $day.1.agent 0.1167
  assert equal ($day.0.sources | where cwd == $lib) [
    {tool: "claude", session: "agent-a", cwd: $lib, repo: "lib"}
  ]
  assert equal ($day | where kind == "run") []
}

def "test Codex subagents and guardian reviews credit the prompt that started them" [] {
  for compressed in [false true] {
    let dir = (mktemp --directory)
    let app = (git-repo $dir "app")
    let form = if $compressed { "compressed" } else { "plain" }
    codex-transcript $dir {id: "lead", cwd: $app, thread_source: "user"} (
      codex-turn "11:00" "review it" --done "11:10"
    ) --compressed=$compressed
    let spawn = {parent_thread_id: "lead", depth: 1, agent_nickname: "x", agent_role: "y"}
    let sub_records = (codex-turn "11:02" "fix it" --done "11:06")
    codex-transcript $dir {
      id: "sub"
      session_id: "lead"
      parent_thread_id: "lead"
      cwd: $app
      thread_source: "subagent"
      source: {subagent: {thread_spawn: $spawn}}
    } $sub_records --compressed=$compressed
    let guardian_records = (
      (codex-turn "11:05" --done "11:20")
      ++ [(codex-model "11:15")]
    )
    codex-transcript $dir {
      id: "guardian"
      session_id: "sub"
      parent_thread_id: "sub"
      cwd: $app
      thread_source: "guardian_review"
      source: {subagent: {other: "guardian"}}
    } $guardian_records --compressed=$compressed

    let day = (digest-day $dir)

    assert equal $day.0.agent 0.4828 $form
    assert equal ($day | where kind == "run") [] $form
  }
}

def "test OMP subagents and advisors credit the prompt that started them" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  transcript $dir ["omp/sessions/app/parent.jsonl"] [
    {type: "session", id: "parent", cwd: $app}
    (omp-user "12:00" "review it")
    (omp-reply "12:10")
  ]
  transcript $dir ["omp/sessions/app/parent/Fix.jsonl"] [
    {type: "session", id: "fix", cwd: $app, parentSession: "parent"}
    (omp-user "12:02" "fix it" --agent)
    (omp-tool "12:02" [
      {
        type: "toolCall"
        id: "w"
        name: "write"
        arguments: {path: "../lib/y.ts", content: "y", i: ""}
      }
    ])
    (omp-result "12:03" "w")
    (omp-reply "12:05")
  ]
  transcript $dir ["omp/sessions/app/parent/__advisor.jsonl"] [
    {type: "session", id: "advisor", cwd: $app, parentSession: "parent"}
    (omp-user "12:06" "advise" --agent)
    (omp-reply "12:30")
  ]

  let day = (digest-day $dir)

  assert equal $day.0.agent 0.6167
  assert equal (($day | where kind == "prompt") | length) 1
  assert equal ($day | where kind == "run") []
}

def "test separate prompts and parallel delegates both add agent time" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lib = (git-repo $dir "lib")
  let lead = "aaaabbbb-0000-4000-8000-000000000001"
  transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
    (claude-prompt $app "10:00" "P")
    ...(claude-active $app ["10:20" "10:40"])
    (claude-reply $app "11:00" "first")
  ]
  claude-subagent $dir "app" $lead "a" {agentType: "implementer", toolUseId: "t", spawnDepth: 1} [
    (claude-user $app "10:10" "task" {isSidechain: true})
    ...(claude-active $app ["10:30"])
    (claude-tool $app "10:50" "SubagentHandback" {})
  ]
  claude-subagent $dir "app" $lead "b" {agentType: "implementer", toolUseId: "u", spawnDepth: 1} [
    (claude-user $app "10:20" "task" {isSidechain: true})
    ...(claude-active $app ["10:40" "11:00"])
    (claude-tool $app "11:30" "SubagentHandback" {})
  ]
  transcript $dir ["claude/projects/lib/q.jsonl"] [
    (claude-prompt $lib "10:30" "Q")
    ...(claude-active $lib ["10:45"])
    (claude-reply $lib "11:00" "second")
  ]

  let day = (digest-day $dir)

  assert equal (($day | where kind == "prompt") | where cwd == $app | get 0.agent) 2.8333
  assert equal (($day | where kind == "prompt") | where cwd == $lib | get 0.agent) 0.5
}

def "test an agent turn earns at most the cap" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-notification "/work/app" "10:00")
    ...(claude-active "/work/app" ["10:20" "10:40" "11:00" "11:20" "11:40" "12:00" "12:20" "12:40"])
    (claude-reply "/work/app" "13:00")
  ]

  let day = (digest-day $dir {hours: {agent_max_minutes: 90}})

  assert equal ($day | where kind == "run" | first).agent 1.5
}

def "test a prompt earns its turn and a reading allowance until the next prompt anywhere" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt "/work/app" "10:00" "release it, I'll watch")
    (claude-reply "/work/app" "11:30")
    (claude-prompt "/work/app" "12:00" "fix the test")
    (claude-reply "/work/app" "12:06")
    (claude-prompt "/work/app" "13:00" "refactor the parser")
    (claude-reply "/work/app" "13:45")
    (claude-prompt "/work/app" "14:00" "merge it")
    (claude-reply "/work/app" "14:06")
    (claude-notification "/work/app" "14:30")
    (claude-reply "/work/app" "14:50")
  ]
  transcript $dir ["claude/projects/lib/b.jsonl"] [
    (claude-prompt "/work/lib" "13:24" "review the API")
  ]

  let day = (digest-day $dir {hours: {reading_minutes: 12}})

  assert equal ($day | get hours) [1.0 0.3 0.4 0.2 0.3]
}

def "test a prompt is cut by a prompt from another session after midnight" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt "/work/app" "2026-10-15T23:30" "late")
    (claude-reply "/work/app" "2026-10-16T00:20")
  ]
  transcript $dir ["claude/projects/lib/b.jsonl"] [
    (claude-prompt "/work/lib" "2026-10-16T00:05" "early")
    (claude-reply "/work/lib" "2026-10-16T00:10")
  ]

  let day = (digest-day $dir)

  assert equal ($day | get hours) [0.5833]
}
