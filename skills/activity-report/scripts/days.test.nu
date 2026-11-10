#!/usr/bin/env nu

# ==================================================================================================
# Activity Digest: Days Tests
# ==================================================================================================

use std/assert

use ./lib/fixtures.testlib.nu *

def "test turns no prompt started become runs" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lib = (git-repo $dir "lib")
  let worker = ($dir | path join "app__worktrees/workmux-fix")
  let lead = "aaaabbbb-0000-4000-8000-000000000002"
  transcript $dir ["claude/projects/app/team.jsonl"] [
    (claude-user $app "10:00" "relay" {teamName: "t", agentName: "fix"})
    ...(claude-active $app ["10:15"])
    (claude-reply $app "10:30")
  ]
  claude-subagent $dir "app" $lead "orphan" {
    agentType: "implementer"
    toolUseId: "t"
    spawnDepth: 1
  } [
    (claude-user $app "10:10" "task" {isSidechain: true})
    ...(claude-active $app ["10:25"])
    (claude-reply $app "10:40")
  ]
  transcript $dir ["claude/projects/lib/headless.jsonl"] [
    (claude-user $lib "10:20" "Reply with exactly: OK" {entrypoint: "sdk-cli"})
    (claude-reply $lib "10:30")
  ]
  codex-transcript $dir {id: "exec", cwd: $lib, thread_source: "user", source: "exec"} (
    codex-turn "10:40" "probe" --done "10:50"
  )
  codex-transcript $dir {id: "sub", cwd: $lib, thread_source: "subagent"} (
    codex-turn "11:00" "review" --done "11:10"
  )
  transcript $dir ["claude/projects/workmux/w.jsonl"] [
    (claude-prompt $worker "11:20" "# Task: fix it")
    (claude-reply $worker "11:40")
  ]
  codex-transcript $dir {id: "resumed", cwd: $lib, thread_source: "user", source: "exec"} (
    ((codex-turn "12:00" --done "12:05") ++ [(codex-model "12:02")])
    ++ (codex-turn "12:10" "second" --done "12:20")
  )

  let cases = [
    {tool: "claude", repo: "app", agent: 0.5, text: "relay"}
    {tool: "claude", repo: "app", agent: 0.5, text: "task"}
    {tool: "claude", repo: "lib", agent: 0.1667, text: "Reply with exactly: OK"}
    {tool: "codex", repo: "lib", agent: 0.1664, text: "probe"}
    {tool: "codex", repo: "lib", agent: 0.1664, text: "review"}
    {tool: "claude", repo: "app", agent: 0.3333, text: "# Task: fix it"}
    {tool: "codex", repo: "lib", agent: 0.2497, text: "second"}
  ]

  let day = (digest-day $dir)

  assert equal $day.sessions []
  assert equal ($day.runs | select tool repo agent text) $cases
}

def "test agent time belongs to the day its turn started" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-notification "/work/app" "2026-10-14T23:30")
    ...(claude-active "/work/app" ["2026-10-14T23:45" "2026-10-15T00:15"])
    (claude-reply "/work/app" "00:30")
    (claude-notification "/work/app" "23:00")
    ...(claude-active "/work/app" [
      "23:20" "23:40" "2026-10-16T00:00" "2026-10-16T00:20" "2026-10-16T00:40"
    ])
    (claude-reply "/work/app" "2026-10-16T01:00")
  ]

  let day = (digest-day $dir)

  assert equal $day.runs.0.agent 2.0
}

def "test a day keeps its final replies past midnight until the next prompt" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt "/work/app" "10:00" "start")
    (claude-reply "/work/app" "10:05" "working")
    (claude-tool "/work/app" "10:06" "Edit" {
      file_path: "/work/app/a.nu"
      old_string: "a"
      new_string: "b"
      replace_all: false
    })
    (claude-notification "/work/app" "10:08")
    (claude-reply "/work/app" "10:12" "started")
    (claude-prompt "/work/app" "10:15" "ship it")
    (claude-reply "/work/app" "2026-10-16T00:30" "merged")
    (claude-prompt "/work/app" "2026-10-16T09:00" "next")
    (claude-reply "/work/app" "2026-10-16T09:05" "tomorrow")
  ]

  let day = (digest-day $dir)

  assert equal ($day.sessions.0.replies | select at text) [
    {at: "10:12", text: "started"}
    {at: "00:30", text: "merged"}
  ]
}

def "test a delegate turn on a later day continues its prompt there" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lib = (git-repo $dir "lib")
  let lead = "aaaabbbb-0000-4000-8000-000000000003"
  transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
    (claude-prompt $app "22:00" "P")
    (claude-reply $app "22:20" "first")
    (claude-prompt $app "2026-10-16T09:00" "Q")
    (claude-reply $app "2026-10-16T09:30" "second")
  ]
  claude-subagent $dir "app" $lead "a" {agentType: "implementer", toolUseId: "t", spawnDepth: 1} [
    (claude-user $app "22:30" "task" {isSidechain: true})
    (claude-tool $app "23:00" "Write" {file_path: ($app | path join "src/x.nu"), content: "x"})
    (claude-tool $app "23:00" "SubagentHandback" {})
    (claude-user $app "2026-10-16T00:10" "continue" {isSidechain: true})
    (claude-tool $app "2026-10-16T00:40" "Write" {
      file_path: ($lib | path join "y.nu")
      content: "y"
    })
    (claude-tool $app "2026-10-16T00:50" "SubagentHandback" {})
  ]

  let output = (digest-output $dir --to "2026-10-16")
  let first = ($output.days | where date == $DAY | get 0)
  let second = ($output.days | where date == "2026-10-16" | get 0)

  assert equal $first.sessions.0.prompts.0.agent 0.8333
  assert equal $first.sessions.0.prompts.0.repos {app: 0.5, lib: 0.5}
  assert equal $second.sessions.0.prompts.0.agent 0.5
  assert equal $second.sessions.0.continued [
    {from: "2026-10-15 22:00", text: "P", agent: 0.6667, repos: {lib: 1.0}}
  ]
}

def "test a continuation books its turn on the local day" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lead = "aaaabbbb-0000-4000-8000-000000000008"
  transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
    (claude-prompt $app "10:00" "P")
    (claude-reply $app "10:30" "first")
  ]
  claude-subagent $dir "app" $lead "a" {agentType: "implementer", toolUseId: "t", spawnDepth: 1} [
    (claude-user $app "2026-10-15T16:30" "continue" {isSidechain: true})
    (claude-tool $app "2026-10-15T17:00" "SubagentHandback" {})
  ]

  let output = (digest-output $dir --to "2026-10-16" --tz "CST-8")

  assert equal $output.days.0.sessions.0.prompts.0.agent 0.5
  assert equal $output.days.1.sessions.0.continued [
    {from: "2026-10-15 18:00", text: "P", agent: 0.5, repos: {}}
  ]
}

def "test a continuation text is excerpted" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lead = "aaaabbbb-0000-4000-8000-00000000000e"
  transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
    (claude-prompt $app "22:00" "a long prompt")
    (claude-reply $app "22:20" "first")
  ]
  claude-subagent $dir "app" $lead "a" {agentType: "implementer", toolUseId: "t", spawnDepth: 1} [
    (claude-user $app "2026-10-16T00:10" "continue" {isSidechain: true})
    (claude-tool $app "2026-10-16T00:50" "SubagentHandback" {})
  ]

  let output = (digest-output $dir --to "2026-10-16" --excerpt-chars 6)

  assert equal ($output.days.1.sessions.0.continued | get text) ["a long..."]
}

def "test a continuation that wrote nothing takes the prompt repositories" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lead = "aaaabbbb-0000-4000-8000-000000000007"
  transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
    (claude-prompt $app "22:00" "P")
    (claude-reply $app "22:20" "first")
  ]
  claude-subagent $dir "app" $lead "a" {agentType: "implementer", toolUseId: "t", spawnDepth: 1} [
    (claude-user $app "22:30" "task" {isSidechain: true})
    (claude-tool $app "23:00" "Write" {file_path: ($app | path join "src/x.nu"), content: "x"})
    (claude-tool $app "23:00" "SubagentHandback" {})
    (claude-user $app "2026-10-16T00:10" "continue" {isSidechain: true})
    (claude-reply $app "2026-10-16T00:40" "done")
  ]

  let output = (digest-output $dir --to "2026-10-16")

  assert equal $output.days.1.sessions.0.continued [
    {from: "2026-10-15 22:00", text: "P", agent: 0.5, repos: {app: 1.0}}
  ]
}

def "test a continuation-only day lists the lead session without prompts" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lib = (git-repo $dir "lib")
  let lead = "aaaabbbb-0000-4000-8000-000000000004"
  transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
    (claude-prompt $app "22:00" "P")
    (claude-reply $app "22:20" "first")
  ]
  claude-subagent $dir "app" $lead "a" {agentType: "implementer", toolUseId: "t", spawnDepth: 1} [
    (claude-user $app "2026-10-16T00:10" "continue" {isSidechain: true})
    (claude-tool $app "2026-10-16T00:40" "Write" {
      file_path: ($lib | path join "y.nu")
      content: "y"
    })
    (claude-tool $app "2026-10-16T00:50" "SubagentHandback" {})
  ]

  let output = (digest-output $dir --from "2026-10-16" --to "2026-10-16")

  assert equal ($output.days.0.sessions | length) 1
  assert equal $output.days.0.sessions.0.session $lead
  assert equal $output.days.0.sessions.0.prompts []
  assert equal $output.days.0.sessions.0.replies []
  assert equal $output.days.0.sessions.0.continued [
    {from: "2026-10-15 22:00", text: "P", agent: 0.6667, repos: {lib: 1.0}}
  ]
  assert equal ($output.repositories | columns | sort) ["app" "lib"]
}

def "test a local command on a later day leaves no continuation" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lead = "aaaabbbb-0000-4000-8000-000000000005"
  let exported = "<local-command-stdout>Conversation exported</local-command-stdout>"
  transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
    (claude-prompt $app "22:00" "P")
    (claude-reply $app "22:20" "first")
    (claude-user $app "2026-10-16T10:00" "<command-name>/export</command-name>")
    (claude-user $app "2026-10-16T10:00" $exported)
  ]

  let output = (digest-output $dir --to "2026-10-16")

  assert equal $output.days.1.sessions []
  assert equal $output.days.1.runs []
}

def "test a local command before more conversation leaves no continuation" [] {
  let cases = [
    {command: "/export", prompt: "10:05", reply: "10:30", agent: 0.4167}
    {command: "/model", prompt: "11:00", reply: "11:30", agent: 0.5}
  ]
  for c in $cases {
    let dir = (mktemp --directory)
    let app = (git-repo $dir "app")
    let lead = "aaaabbbb-0000-4000-8000-00000000000c"
    transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
      (claude-prompt $app "22:00" "P")
      (claude-reply $app "22:20" "first")
      (claude-user $app "2026-10-16T10:00" $"<command-name>($c.command)</command-name>")
      (claude-user $app "2026-10-16T10:00" "<local-command-stdout>done</local-command-stdout>")
      (claude-prompt $app $"2026-10-16T($c.prompt)" "Q")
      (claude-reply $app $"2026-10-16T($c.reply)" "second")
    ]

    let output = (digest-output $dir --to "2026-10-16")

    assert equal $output.days.1.sessions.0.continued [] $"($c.command) leaves no continuation"
    assert equal $output.days.1.sessions.0.prompts.0.agent $c.agent $"Q at ($c.prompt)"
    assert equal $output.days.1.runs [] $"($c.command) leaves no run"
  }
}
