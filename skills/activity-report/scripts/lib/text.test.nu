#!/usr/bin/env nu

# ==================================================================================================
# Activity Digest: Text Tests
# ==================================================================================================

use std/assert
use std-rfc/str

use ./fixtures.testlib.nu *

def "test the excerpt length keeps whole text at zero and cuts at a custom limit" [] {
  let dir = (mktemp --directory)
  let long = (
    $"
    first
    ("" | fill --character "a" --width 450)
    "
    | str dedent
  )
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt "/work/app" "10:00" $long)
    (claude-reply "/work/app" "10:30" $long)
  ]

  let excerpted = (digest-day $dir)
  let short = (digest-day $dir --excerpt-chars 10)
  let full = (digest-day $dir --excerpt-chars 0)

  let excerpt = $"first ("" | fill --character "a" --width 394)..."
  let short_excerpt = "first aaaa..."
  let projected = {|day|
    $day.sessions | each {|s| {prompt: $s.prompts.0.text, reply: $s.replies.0.text} }
  }
  assert equal (do $projected $excerpted) [{prompt: $excerpt, reply: $excerpt}]
  assert equal (do $projected $short) [{prompt: $short_excerpt, reply: $short_excerpt}]
  assert equal (do $projected $full) [{prompt: $long, reply: $long}]
}
