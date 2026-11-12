#!/usr/bin/env nu

# ==================================================================================================
# Activity Report: Claude Code Tests
# ==================================================================================================

use std/assert
use std-rfc/str

use ../lib/fixtures.testlib.nu *

def "test only prompts a person typed count" [] {
  let dir = (mktemp --directory)
  let app = "/work/app"
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt $app "10:00" "fix the parser")
    (claude-user $app "11:00" "peer message" {origin: {kind: "peer"}, isMeta: true})
    (claude-user $app "12:00" "From the lead: continue" {teamName: "t"})
    (claude-user $app "13:00" "<command-name>/export</command-name>")
    (claude-user $app "13:30" "/compact")
    (claude-queued $app "13:45" "<task-notification>" "task-notification")
    (claude-prompt $app "14:00" "/review")
  ]
  codex-transcript $dir {id: "user", cwd: $app, thread_source: "user"} (
    codex-turn "16:00" "check CI"
  )
  codex-transcript $dir {id: "import", cwd: $app} (codex-turn "17:00" "imported")
  transcript $dir ["omp/sessions/app/a.jsonl"] [
    {type: "session", id: "omp", cwd: $app}
    (omp-user "18:00" "plan it")
  ]

  let day = (digest-day $dir)

  assert equal ($day.sessions | each {|s| {tool: $s.tool, prompts: ($s.prompts | get at)} }) [
    {tool: "claude", prompts: ["10:00" "14:00"]}
    {tool: "codex", prompts: ["16:00"]}
    {tool: "omp", prompts: ["18:00"]}
  ]
}

def "test an answered question earns a prompt and a timed-out one earns none" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-answered "/work/app" "10:00" {"Which repo?": "app", "Which branch?": "main"})
    (claude-reply "/work/app" "10:06" "shipped")
    (claude-timed-out "/work/app" "11:00")
    (claude-reply "/work/app" "11:06" "carried on")
  ]

  let day = (digest-day $dir --excerpt-chars 0)

  assert equal ($day.sessions.0.prompts | select text hours agent) [
    {
      text: (
        "
        Which repo?: app
        Which branch?: main
        "
        | str dedent
      )
      hours: 0.2667
      agent: 0.1
    }
  ]
}

def "test only a record tool result can be a question" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-user "/work/app" "09:58" "ran a command" {toolUseResult: "output"})
    (claude-user "/work/app" "09:59" "read a file" {toolUseResult: [{type: "text", text: "x"}]})
    (claude-prompt "/work/app" "10:00" "start")
    (claude-reply "/work/app" "10:10" "done")
  ]

  let day = (digest-day $dir)

  assert equal ($day.sessions.0.prompts | select at hours) [{at: "10:00", hours: 0.3333}]
}

def "test a renamed lead session keeps its prompts" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    {type: "agent-name", agentName: "design-log", sessionId: "a"}
    (claude-prompt "/work/app" "10:00" "start")
    (claude-reply "/work/app" "10:20" "done")
  ]

  let day = (digest-day $dir)

  assert equal ($day.sessions | each {|s| $s.prompts | select at hours }) [
    [{at: "10:00", hours: 0.5}]
  ]
  assert equal $day.runs []
}

def "test a compaction belongs to the turn it compacted" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt "/work/app" "10:00" "P")
    ...(claude-active "/work/app" ["10:05"])
    (claude-user "/work/app" "10:10" "summary" {isCompactSummary: true})
  ]
  transcript $dir ["claude/projects/app/b.jsonl"] [
    (claude-prompt "/work/app" "10:00" "P")
    ...(claude-active "/work/app" ["10:05"])
    (claude-user "/work/app" "10:10" "summary" {isCompactSummary: true})
    (claude-reply "/work/app" "10:20" "done")
  ]
  codex-transcript $dir {id: "c", cwd: "/work/app", thread_source: "user"} [
    ...(codex-turn "10:00" "P")
    (codex-model "10:05")
    {type: "response_item", timestamp: (at "10:10"), payload: {type: "compaction"}}
  ]

  let day = (digest-day $dir)

  assert equal (
    $day.sessions
    | select session prompts
    | each {|s| {session: $s.session, agent: $s.prompts.0.agent} }
    | sort-by session
  ) [
    {session: "a", agent: 0.1667}
    {session: "b", agent: 0.3333}
    {session: "c", agent: 0.1664}
  ]
  assert equal $day.runs []
}
