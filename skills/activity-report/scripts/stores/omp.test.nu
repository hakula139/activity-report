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

  assert equal (($day | where kind == "prompt") | select from text) [
    {from: "2026-10-15T10:00:00+00:00", text: "plan the parser"}
  ]
  assert equal ($day | get replies | flatten) [
    {at: "2026-10-15T10:20:00+00:00", text: "planned it"}
  ]
}

def "test a top-level OMP session has no parent named after its project" [] {
  let dir = (mktemp --directory)
  transcript $dir ["omp/sessions/app.jsonl"] [
    {type: "session", id: "other", cwd: "/work/other"}
    (omp-user "10:00" "other task")
    (omp-reply "10:10")
  ]
  transcript $dir ["omp/sessions/app/a.jsonl"] [
    {type: "session", id: "a", cwd: "/work/app"}
    (omp-user "10:01" "automatic task" --agent)
    (omp-reply "10:02")
  ]

  let day = (digest-day $dir)

  assert equal ($day | select session kind agent) [
    {session: "other", kind: "prompt", agent: 0.1667}
    {session: "a", kind: "run", agent: 0.0167}
  ]
}
