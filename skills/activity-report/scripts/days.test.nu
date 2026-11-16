#!/usr/bin/env nu

# ==================================================================================================
# Activity Report: Days Tests
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

  assert equal ($day | where kind == "prompt") []
  assert equal (($day | where kind == "run") | select tool repo agent text) $cases
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

  assert equal ($day | where kind == "run" | first).agent 2.0
}

def "test a day keeps its final replies past midnight until the next prompt" [] {
  let dir = (mktemp --directory)
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt "/work/app" "10:00" "start")
    (claude-reply "/work/app" "10:05" "working")
    ...(claude-active "/work/app" ["10:06"])
    (claude-notification "/work/app" "10:08")
    (claude-reply "/work/app" "10:12" "started")
    (claude-prompt "/work/app" "10:15" "ship it")
    (claude-reply "/work/app" "2026-10-16T00:30" "merged")
    (claude-prompt "/work/app" "2026-10-16T09:00" "next")
    (claude-reply "/work/app" "2026-10-16T09:05" "tomorrow")
  ]

  let day = (digest-day $dir)

  assert equal ($day | get replies | flatten | select at text) [
    {at: "2026-10-15T10:05:00+00:00", text: "working"}
    {at: "2026-10-15T10:12:00+00:00", text: "started"}
    {at: "2026-10-16T00:30:00+00:00", text: "merged"}
  ]
}

def "test a delegate turn on a later day continues its prompt there" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lead = "aaaabbbb-0000-4000-8000-000000000003"
  transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
    (claude-prompt $app "22:00" "P")
    (claude-reply $app "22:20" "first")
    (claude-prompt $app "2026-10-16T09:00" "Q")
    (claude-reply $app "2026-10-16T09:30" "second")
  ]
  claude-subagent $dir "app" $lead "a" {agentType: "implementer", toolUseId: "t", spawnDepth: 1} [
    (claude-user $app "22:30" "task" {isSidechain: true})
    ...(claude-active $app ["23:00"])
    (claude-tool $app "23:00" "SubagentHandback" {})
    (claude-user $app "2026-10-16T00:10" "continue" {isSidechain: true})
    ...(claude-active $app ["2026-10-16T00:40"])
    (claude-tool $app "2026-10-16T00:50" "SubagentHandback" {})
  ]

  let output = (digest-output $dir --to "2026-10-16")
  let first = ($output | day-entries)
  let second = ($output | day-entries 1)

  assert equal $first.0.agent 0.8333
  assert equal $second.1.agent 0.5
  assert equal ($second | where hours == 0 | select from text agent) [
    {from: "2026-10-15T22:00:00+00:00", text: "P", agent: 0.6667}
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

  assert equal ($output | day-entries | first | get agent) 0.5
  assert equal ($output | day-entries 1 | select from text agent) [
    {from: "2026-10-15T18:00:00+08:00", text: "P", agent: 0.5}
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

  assert equal ($output | day-entries 1 | get text) ["a long..."]
}

def "test a continuation-only day reuses the older prompt and its evidence" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lead = "aaaabbbb-0000-4000-8000-000000000004"
  transcript $dir ["claude/projects/app" $"($lead).jsonl"] [
    (claude-prompt $app "22:00" "P")
    (claude-reply $app "22:20" "first")
  ]
  claude-subagent $dir "app" $lead "a" {agentType: "implementer", toolUseId: "t", spawnDepth: 1} [
    (claude-user $app "2026-10-16T00:10" "continue" {isSidechain: true})
    ...(claude-active $app ["2026-10-16T00:40"])
    (claude-tool $app "2026-10-16T00:50" "SubagentHandback" {})
  ]

  let output = (digest-output $dir --from "2026-10-16" --to "2026-10-16")

  assert equal $output.days.0.entries [{unit: 0, hours: 0, agent: 0.6667}]
  assert equal ($output.units | select session from text replies) [{
    session: $lead
    from: "2026-10-15T22:00:00+00:00"
    text: "P"
    replies: [{at: "2026-10-15T22:20:00+00:00", text: "first"}]
  }]
  assert equal $output.repositories {app: $app}
}

def "test an old recursive ancestor still owns a recent continuation" [] {
  let dir = (mktemp --directory)
  transcript $dir ["omp/sessions/app/lead.jsonl"] [
    {
      type: "session"
      id: "lead"
      cwd: "/work/app"
    }
    (omp-user "22:00" "original task")
    (omp-reply "22:10")
  ]
  transcript $dir ["omp/sessions/app/lead/middle.jsonl"] [
    {
      type: "session"
      id: "middle"
      cwd: "/work/app"
    }
    (omp-user "23:00" "delegated task" --agent)
    (omp-reply "23:10")
  ]
  transcript $dir ["omp/sessions/app/lead/middle/leaf.jsonl"] [
    {
      type: "session"
      id: "leaf"
      cwd: "/work/app"
    }
    (omp-user "2026-10-16T00:10" "continue" --agent)
    (omp-reply "2026-10-16T00:40")
  ]
  for file in ["lead.jsonl" "lead/middle.jsonl"] {
    with-env {TZ: "UTC"} {
      ^touch -t 202601010000 ($dir | path join "omp/sessions/app" $file)
    }
  }
  with-env {TZ: "UTC"} {
    ^touch -t 202610160100 ($dir | path join "omp/sessions/app/lead/middle/leaf.jsonl")
  }

  let output = (digest-output $dir --from "2026-10-16" --to "2026-10-16")

  assert equal $output.days [{
    date: "2026-10-16"
    weekday: "Fri"
    entries: [{unit: 0, hours: 0, agent: 0.5}]
  }]
  assert equal $output.units [{
    kind: "prompt"
    tool: "omp"
    session: "lead"
    cwd: "/work/app"
    repo: null
    from: "2026-10-15T22:00:00+00:00"
    text: "original task"
    replies: [{at: "2026-10-15T22:10:00+00:00", text: "done"}]
    sources: [{tool: "omp", session: "leaf", cwd: "/work/app", repo: null}]
  }]
}

def "test DST days own midnight sides and repeated local clocks" [] {
  let timezone = ($env.TZDIR? | default "/usr/share/zoneinfo" | path join "America/New_York")
  let cases = [
    {
      from: "2026-03-07"
      to: "2026-03-09"
      clocks: ["2026-03-08T04:58" "2026-03-08T05:00" "2026-03-09T03:58" "2026-03-09T04:00"]
      dates: ["2026-03-07" "2026-03-08" "2026-03-08" "2026-03-09"]
      local: ["23:58" "00:00" "23:58" "00:00"]
    }
    {
      from: "2026-10-31"
      to: "2026-11-02"
      clocks: [
        "2026-11-01T03:58" "2026-11-01T04:00" "2026-11-01T05:30"
        "2026-11-01T06:30" "2026-11-02T04:58" "2026-11-02T05:00"
      ]
      dates: ["2026-10-31" "2026-11-01" "2026-11-01" "2026-11-01" "2026-11-01" "2026-11-02"]
      local: ["23:58" "00:00" "01:30" "01:30" "23:58" "00:00"]
    }
  ]
  for c in $cases {
    let dir = (mktemp --directory)
    for clock in ($c.clocks | enumerate) {
      let reply = (at $clock.item | into datetime | $in + 1min)
      transcript $dir ["claude/projects/app" $"($clock.index).jsonl"] [
        (claude-prompt "/work/app" $clock.item $"task ($clock.index)")
        (claude-reply "/work/app" $clock.item
          | update timestamp ($reply | format date "%Y-%m-%dT%H:%M:%SZ"))
      ]
    }

    let output = (digest-output $dir {hours: {reading_minutes: 0}}
      --from $c.from
      --to $c.to
      --tz $timezone
    )

    let actual = ($output.days | enumerate | each {|day|
      $output | day-entries $day.index | each {|unit|
        {
          date: $day.item.date
          at: ($unit.from | into datetime | format date "%H:%M")
          text: $unit.text
          hours: $unit.hours
          agent: $unit.agent
        }
      }
    } | flatten)
    let expected = ($c.clocks | enumerate | each {|clock|
      {
        date: ($c.dates | get $clock.index)
        at: ($c.local | get $clock.index)
        text: $"task ($clock.index)"
        hours: 0.0167
        agent: 0.0167
      }
    })
    assert equal $actual $expected $c.from
  }
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

  assert equal $output.days.1.entries []
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

    let entries = ($output | day-entries 1 | select text agent)
    assert equal $entries [{text: "Q", agent: $c.agent}] $c.command
  }
}

def "test run evidence keeps in-range intervals and their final replies" [] {
  let dir = (mktemp --directory)
  transcript $dir ["omp/sessions/app/run.jsonl"] [
    {type: "session", id: "run", cwd: "/work/app"}
    (omp-user "2026-10-14T09:00" "old task" --agent)
    (omp-reply "2026-10-14T09:10" "old result")
    (omp-user "10:00" "first task" --agent)
    (omp-reply "10:05" "interim")
    (omp-reply "10:10" "first result")
    (omp-user "23:50" "second task" --agent)
    (omp-reply "2026-10-16T00:10" "second result")
    (omp-user "2026-10-16T01:00" "future task" --agent)
    (omp-reply "2026-10-16T01:10" "future result")
  ]

  let output = (digest-output $dir)

  assert equal $output.units [{
    kind: "run"
    tool: "omp"
    session: "run"
    cwd: "/work/app"
    repo: null
    from: "2026-10-15T10:00:00+00:00"
    text: "first task"
    replies: [
      {at: "2026-10-15T10:10:00+00:00", text: "first result"}
      {at: "2026-10-16T00:10:00+00:00", text: "second result"}
    ]
    sources: []
  }]
  assert equal $output.days [{
    date: $DAY
    weekday: "Thu"
    entries: [{unit: 0, hours: 0, agent: 0.4167}]
  }]
}
