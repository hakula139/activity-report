#!/usr/bin/env nu

# ==================================================================================================
# Activity Digest: OMP Tests
# ==================================================================================================

use std/assert

use ../lib/fixtures.testlib.nu *

def "test OMP subagents and advisors credit the prompt that started them" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lib = (git-repo $dir "lib")
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
    (omp-reply "12:05")
  ]
  transcript $dir ["omp/sessions/app/parent/__advisor.jsonl"] [
    {type: "session", id: "advisor", cwd: $app, parentSession: "parent"}
    (omp-user "12:06" "advise" --agent)
    (omp-reply "12:30")
  ]

  let day = (digest-day $dir)

  assert equal $day.sessions.0.prompts.0.repos {lib: 1.0}
  assert equal $day.sessions.0.prompts.0.agent 0.6167
  assert equal ($day.sessions | length) 1
  assert equal $day.runs []
}
