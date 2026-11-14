#!/usr/bin/env nu

# ==================================================================================================
# Activity Report: Confirmed Write Tests
# ==================================================================================================

use std/assert

use ../lib/fixtures.testlib.nu *

def "test write credit requires a matching successful result and keeps request ownership" [] {
  for tool in ["claude" "omp" "codex"] {
    let dir = (mktemp --directory)
    let app = (git-repo $dir "app")
    let lib = (git-repo $dir "lib")
    let paths = (["success.nu" "failed.nu" "missing.nu" "unmatched.nu"] ++ (
      if $tool == "claude" {
        ["second-success.nu"]
      } else {
        []
      }
    ))
    let calls = ($paths | enumerate | each {|p|
      let root = if $p.index == 0 { $lib } else { $app }
      if $tool == "claude" {
        {
          type: "tool_use"
          id: $"call-($p.index)"
          name: "Write"
          input: {
            file_path: ($root | path join $p.item)
            content: "x"
          }
        }
      } else {
        {
          type: "toolCall"
          id: $"call-($p.index)"
          name: "write"
          arguments: {
            path: ($root | path join $p.item)
            content: "x"
          }
        }
      }
    })
    if $tool == "claude" {
      let request = (claude-tool $app "10:01" "Write" {}
        | update message.content ([{
          type: "text"
          text: "working"
        }] ++ $calls))
      let result = (claude-result $app "10:03" "call-0"
        | reject message.content.0.is_error
        | update message.content {|r|
          [
            {
              type: "text"
              text: "tool output"
            }
            ...(claude-result $app "10:03" "call-1" --error | get message.content)
            ...$r.message.content
            ...(claude-result $app "10:03" "call-4" | get message.content)
            ...(claude-result $app "10:03" "unrelated" | get message.content)
          ]
        })
      transcript $dir ["claude/projects/app/a.jsonl"] [
        (claude-prompt $app "10:00" "original")
        $request
        (claude-queued $app "10:02" "steering")
        $result
        (claude-reply $app "10:04")
      ]
    } else if $tool == "omp" {
      transcript $dir ["omp/sessions/app/a.jsonl"] [
        {
          type: "session"
          id: "a"
          cwd: $app
        }
        (omp-user "10:00" "original")
        (omp-tool "10:01" ([{
          type: "text"
          text: "working"
        }] ++ $calls))
        (omp-user "10:02" "steering")
        (omp-result "10:03" "call-1" --error)
        (omp-result "10:03" "unrelated")
        (omp-result "10:03" "call-3" | reject message.isError)
        (omp-result "10:03" "call-0")
        (omp-reply "10:04")
      ]
    } else {
      let changes = ($paths | enumerate | each {|p|
        let status = (["completed" "failed" "in_progress" "declined"] | get $p.index)
        let root = if $p.index == 0 { $lib } else { $app }
        codex-file-change "10:01" ({} | insert ($root | path join $p.item) {type: "add"})
        | update payload.item.status $status
      })
      let missing = (codex-file-change "10:01" {
        "missing-status.nu": {type: "add"}
      } | reject payload.item.status)
      codex-transcript $dir {
        id: "a"
        cwd: $app
        thread_source: "user"
      } [
        ...(codex-turn "10:00" "original")
        ...$changes
        $missing
        ...(codex-turn "10:02" "steering" --done "10:04")
      ]
    }

    let day = (digest-day $dir)

    assert equal ($day.sessions.0.prompts | select text repos) [
      {
        text: "original"
        repos: (if $tool == "claude" {
          {
            lib: 0.5
            app: 0.5
          }
        } else {
          {lib: 1.0}
        })
      }
      {
        text: "steering"
        repos: {}
      }
    ] $tool
    assert equal $day.runs [] $tool
  }
}
