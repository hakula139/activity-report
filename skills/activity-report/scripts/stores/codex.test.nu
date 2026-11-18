#!/usr/bin/env nu

# ==================================================================================================
# Activity Report: Codex Tests
# ==================================================================================================

use std/assert
use std-rfc/str

use ../lib/fixtures.testlib.nu *

def "test native Codex sources retain agent work and conservative human credit" [] {
  let cases = [
    {
      meta: {source: "vscode", thread_source: null}
      kind: "run"
      hours: 0.0
    }
    {
      meta: {source: "vscode"}
      kind: "run"
      hours: 0.0
    }
    {
      meta: {source: "vscode", thread_source: "user"}
      kind: "prompt"
      hours: 0.3331
    }
    {
      meta: {source: "exec", thread_source: "user"}
      kind: "run"
      hours: 0.0
    }
    {
      meta: {source: "mcp", thread_source: "user"}
      kind: "run"
      hours: 0.0
    }
  ]
  for c in $cases {
    let dir = (mktemp --directory)
    let meta = ({id: "native", cwd: "/work/app"} | merge $c.meta)
    codex-transcript $dir $meta [
      ...(codex-turn "11:00" "review it")
      (codex-model "11:05")
      (codex-event "11:10" {type: "task_complete", last_agent_message: "native reply"})
    ]

    let day = (digest-day $dir)

    assert equal ($day | select kind from text hours agent replies) [
      {
        kind: $c.kind
        from: "2026-10-15T11:00:01+00:00"
        text: "review it"
        hours: $c.hours
        agent: 0.1664
        replies: [{at: "2026-10-15T11:10:00+00:00", text: "native reply"}]
      }
    ] ($c.meta | to json --raw)
  }
}

def "test imported Codex turns do not duplicate work or hide native continuations" [] {
  let imported = (codex-import "09:00" "09:10")
  let appended = [
    (codex-model "09:15")
    (codex-event "09:20" {type: "task_complete", last_agent_message: "appended reply"})
    ...(codex-import "10:00" "10:10" | where payload.type != "agent_message")
  ]
  let native = [
    ...(codex-turn "11:00" "external-import-turn- is quoted text")
    (codex-model "11:05")
    (codex-event "11:10" {type: "task_complete", last_agent_message: "native reply"})
  ]
  let cases = [
    {
      name: "import only"
      records: $imported
      native: false
    }
    {
      name: "appended import without another marker"
      records: ($imported ++ $appended)
      native: false
    }
    {
      name: "native continuation"
      records: ($imported ++ $appended ++ $native)
      native: true
    }
    {
      name: "later import"
      records: ($native ++ (codex-import "12:00" "12:10"))
      native: true
    }
    {
      name: "prefix in prompt text"
      records: $native
      native: true
    }
  ]
  for c in $cases {
    let dir = (mktemp --directory)
    let meta = {
      id: "mixed"
      cwd: "/work/app"
      source: "vscode"
      thread_source: null
    }
    codex-transcript $dir $meta $c.records

    let day = (digest-day $dir)

    let expected = if $c.native {
      [
        {
          kind: "run"
          from: "2026-10-15T11:00:01+00:00"
          text: "external-import-turn- is quoted text"
          hours: 0.0
          agent: 0.1664
          replies: [{at: "2026-10-15T11:10:00+00:00", text: "native reply"}]
        }
      ]
    } else {
      []
    }
    assert equal ($day | select kind from text hours agent replies) $expected $c.name
  }
}

def "test Codex request headings are stripped from prompts" [] {
  let dir = (mktemp --directory)
  let cases = [
    {
      name: "Desktop browser context"
      clock: "11:00"
      done: "11:30"
      input: (
        '
        <in-app-browser-context source="ambient-ui-state">
        page text
        ## My request:
        quoted earlier transcript
        </in-app-browser-context>
        ## My request:
        summarize it
        '
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
  let prompts = ($day | get text)

  for c in ($cases | enumerate) {
    assert equal ($prompts | get $c.index) $c.item.expected $c.item.name
  }
}

def "test a Codex subagent finds its parent in archived sessions" [] {
  for compressed in [false true] {
    let dir = (mktemp --directory)
    let app = (git-repo $dir "app")
    let form = if $compressed { "compressed" } else { "plain" }
    codex-transcript $dir {id: "lead", cwd: $app, thread_source: "user"} (
      codex-turn "11:00" "review it" --done "11:10"
    ) --archived --compressed=$compressed
    let archived = (glob ($dir | path join "codex/archived_sessions/*") | first)
    with-env {TZ: "UTC"} {
      ^touch -t 202601010000 $archived
    }
    codex-transcript $dir {
      id: "sub"
      cwd: $app
      thread_source: "subagent"
      parent_thread_id: "lead"
    } (codex-turn "11:02" "fix it" --done "11:06")

    let day = (digest-day $dir)

    assert equal $day.0.agent 0.2328 $form
    assert equal ($day | where kind == "run") [] $form
  }
}

def "test both forms of an archived Codex session read once" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let meta = {
    id: "both"
    cwd: $app
    thread_source: "user"
  }
  let records = (codex-turn "11:00" "review it" --done "11:10")
  codex-transcript $dir $meta $records --archived --compressed
  codex-transcript $dir $meta $records --archived

  let day = (digest-day $dir)

  assert equal (($day | where kind == "prompt") | length) 1
  assert equal $day.0.agent 0.1664
}
