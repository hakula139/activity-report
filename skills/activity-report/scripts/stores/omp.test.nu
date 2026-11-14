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
