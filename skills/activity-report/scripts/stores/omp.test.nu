#!/usr/bin/env nu

# ==================================================================================================
# Activity Report: OMP Tests
# ==================================================================================================

use std/assert

use ../lib/fixtures.testlib.nu *

def "test OMP prompts and replies keep their text" [] {
  let dir = (mktemp --directory)
  transcript $dir ["omp/sessions/app/a.jsonl"] [
    {type: "session", id: "omp", cwd: "/work/app"}
    (omp-user "10:00" "plan the parser")
    (omp-reply "10:20" "planned it")
  ]

  let day = (digest-day $dir)

  assert equal ($day.sessions.0.prompts | select at text) [{at: "10:00", text: "plan the parser"}]
  assert equal $day.sessions.0.replies [{at: "10:20", text: "planned it"}]
}

def "test an OMP read call is not a write" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lib = (git-repo $dir "lib")
  transcript $dir ["omp/sessions/app/a.jsonl"] [
    {type: "session", id: "omp", cwd: $app}
    (omp-user "10:00" "port the parser")
    (omp-tool "10:01" [
      {type: "toolCall", id: "r", name: "read", arguments: {path: ($lib | path join "a.ts")}}
      {type: "toolCall", id: "w", name: "write", arguments: {path: "a.ts", content: "a"}}
    ])
    (omp-result "10:02" "w")
    (omp-reply "10:05")
  ]

  let day = (digest-day $dir)

  assert equal $day.sessions.0.prompts.0.repos {app: 1.0}
}
