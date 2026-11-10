#!/usr/bin/env nu

# ==================================================================================================
# Activity Report: Codex Tests
# ==================================================================================================

use std/assert
use std-rfc/str

use ../lib/fixtures.testlib.nu *

def "test Codex request headings are stripped from prompts" [] {
  let dir = (mktemp --directory)
  let cases = [
    {
      name: "Desktop browser context"
      clock: "11:00"
      done: "11:30"
      input: (
        "
        <in-app-browser-context source="ambient-ui-state">
        page text
        ## My request:
        quoted earlier transcript
        </in-app-browser-context>
        ## My request:
        summarize it
        "
        | str dedent
      )
      expected: "summarize it"
    }
    {
      name: "Desktop IDE context"
      clock: "12:00"
      done: "12:30"
      input: (
        "
        # Context from my IDE setup:
        ## Active file: /work/app/main.nu
        ## My request:
        short form
        "
        | str dedent
      )
      expected: "short form"
    }
    {
      name: "TUI IDE context"
      clock: "13:00"
      done: "13:30"
      input: (
        "
        # Context from my IDE setup:

        ## Active file: src/lib.rs

        ## My request for Codex:
        long form
        "
        | str dedent
      )
      expected: "long form"
    }
    {
      name: "no heading"
      clock: "14:00"
      done: "14:30"
      input: "no heading here"
      expected: "no heading here"
    }
    {
      name: "inline mention"
      clock: "15:00"
      done: "15:30"
      input: "quote ## My request: tail"
      expected: "tail"
    }
  ]
  let records = (
    $cases
    | each {|c| codex-turn $c.clock $c.input --done $c.done }
    | flatten
  )
  codex-transcript $dir {id: "request", cwd: "/work/app", thread_source: "user"} $records

  let day = (digest-day $dir --excerpt-chars 0)
  let prompts = ($day.sessions.0.prompts | get text)

  for c in ($cases | enumerate) {
    assert equal ($prompts | get $c.index) $c.item.expected $c.item.name
  }
}

def "test a Codex subagent finds its parent in archived sessions" [] {
  for compressed in [false true] {
    let dir = (mktemp --directory)
    let app = (git-repo $dir "app")
    let lib = (git-repo $dir "lib")
    let form = if $compressed { "compressed" } else { "plain" }
    codex-transcript $dir {id: "lead", cwd: $app, thread_source: "user"} (
      codex-turn "11:00" "review it" --done "11:10"
    ) --archived --compressed=$compressed
    let changes = (
      [($lib | path join "x.rs")]
      | reduce --fold {} {|path, acc| $acc | insert $path {type: "add"} }
    )
    codex-transcript $dir {
      id: "sub"
      cwd: $app
      thread_source: "subagent"
      parent_thread_id: "lead"
    } ((codex-turn "11:02" "fix it" --done "11:06") ++ [(codex-file-change "11:04" $changes)])

    let day = (digest-day $dir)

    assert equal $day.sessions.0.prompts.0.repos {lib: 1.0} $form
    assert equal $day.runs [] $form
  }
}

def "test both forms of an archived Codex session read once" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let meta = {id: "both", cwd: $app, thread_source: "user"}
  let records = (codex-turn "11:00" "review it" --done "11:10")
  codex-transcript $dir $meta $records --archived --compressed
  codex-transcript $dir $meta $records --archived

  let day = (digest-day $dir)

  assert equal ($day.sessions | length) 1
  assert equal $day.sessions.0.prompts.0.agent 0.1664
}

def "test a Codex turn starts at its prompt" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  codex-transcript $dir {id: "lead", cwd: $app, thread_source: "user"} (
    codex-turn "11:00" "review it" --done "11:10"
  )

  let day = (digest-day $dir)

  assert equal $day.runs []
  assert equal $day.sessions.0.prompts.0.agent 0.1664
}
