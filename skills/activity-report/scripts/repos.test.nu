#!/usr/bin/env nu

# ==================================================================================================
# Activity Report: Repositories Tests
# ==================================================================================================

use std/assert

use ./lib/fixtures.testlib.nu *

def "test repositories resolve subdirectories and worktrees, and missing paths resolve to none" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  mkdir ($app | path join "src")
  let linked = ($dir | path join "app-wt/fix")
  (
    ^git
      -C $app
      worktree add $linked
        --detach
        --quiet
  )
  let live = ($dir | path join "app__worktrees/fix")
  (
    ^git
      -C $app
      worktree add $live
        --detach
        --quiet
  )
  mkdir ($dir | path join "scratch")
  let cases = [
    {
      name: "sub"
      clock: "10:00"
      cwd: ($app | path join "src")
      file: ($app | path join "src/a.nu")
      repo: "app"
      repos: {app: 1.0}
    }
    {
      name: "linked"
      clock: "10:01"
      cwd: $linked
      file: ($linked | path join "src/b.nu")
      repo: "app"
      repos: {app: 1.0}
    }
    {
      name: "live"
      clock: "10:02"
      cwd: $live
      file: ($live | path join "c.nu")
      repo: "app"
      repos: {app: 1.0}
    }
    {
      name: "gone"
      clock: "10:03"
      cwd: ($dir | path join "app__worktrees/gone")
      file: ($dir | path join "app__worktrees/gone/d.nu")
      repo: "app"
      repos: {app: 1.0}
    }
    {
      name: "scratch"
      clock: "10:04"
      cwd: ($dir | path join "scratch")
      file: ($dir | path join "scratch/e.nu")
      repo: null
      repos: {}
    }
    {
      name: "gone-wt"
      clock: "10:05"
      cwd: ($dir | path join "app-wt/gone")
      file: ($dir | path join "app-wt/gone/f.nu")
      repo: null
      repos: {}
    }
  ]
  for c in $cases {
    transcript $dir ["claude/projects" $c.name $"($c.name).jsonl"] [
      (claude-prompt $c.cwd $c.clock "write it")
      (claude-tool $c.cwd $c.clock "Write" {file_path: $c.file, content: "x"})
    ]
  }

  let output = (digest-output $dir)
  let day = $output.days.0

  assert equal ($day.sessions | each {|s| {repo: $s.repo, repos: $s.prompts.0.repos} }) (
    $cases | each {|c| {repo: $c.repo, repos: $c.repos} }
  )
  assert equal $output.repositories {app: $app}
}

def "test a symlink outside a repository credits the repository it points into" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lib = (git-repo $dir "lib")
  mkdir ($lib | path join "src")
  mkdir ($dir | path join "elsewhere")
  ^ln -s ($lib | path join "src") ($dir | path join "elsewhere/mem")
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt $app "10:00" "write to the linked tree")
    (claude-tool $app "10:01" "Write" {
      file_path: ($dir | path join "elsewhere/mem/a.nu")
      content: "x"
    })
  ]

  let output = (digest-output $dir)

  assert equal ($output.days.0.sessions.0.prompts | get repos) [{lib: 1.0}]
  assert equal $output.repositories.lib $lib
}

def "test writes to git-ignored paths never count" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let lib = (git-repo $dir "lib")
  mkdir ($app | path join "src")
  mkdir ($lib | path join ".claude/agent-memory-local/r")
  let live = ($dir | path join "app__worktrees/live")
  (
    ^git
      -C $app
      worktree add $live
        --detach
        --quiet
  )
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt $app "10:00" "write files")
    (claude-tool $app "10:01" "Write" {file_path: ($app | path join "src/a.nu"), content: "x"})
    (claude-tool $app "10:02" "Write" {
      file_path: ($app | path join ".claude/agent-memory-local/gone/src/b.nu")
      content: "x"
    })
    (claude-tool $app "10:03" "Write" {
      file_path: ($lib | path join ".claude/agent-memory-local/r/m.md")
      content: "x"
    })
    (claude-tool $app "10:03" "Write" {
      file_path: ($lib | path join ".claude/agent-memory-local/r/周报.md")
      content: "x"
    })
    (claude-tool $app "10:04" "Write" {file_path: ($lib | path join "README.md"), content: "x"})
    (claude-tool $app "10:05" "Write" {
      file_path: ($live | path join ".claude/agent-memory-local/gone/c.md")
      content: "x"
    })
  ]

  let day = (digest-day $dir)

  assert equal $day.sessions.0.prompts.0.repos {app: 0.5, lib: 0.5}
}

def "test a checkout behind a symlinked parent keeps its writes except ignored ones" [] {
  let dir = (mktemp --directory)
  mkdir ($dir | path join "real")
  let app = (git-repo ($dir | path join "real") "app")
  mkdir ($app | path join "src")
  ^ln -s "real" ($dir | path join "lnk")
  let linked = ($dir | path join "lnk/app")
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt $linked "10:00" "ship it")
    (claude-tool $linked "10:01" "Write" {
      file_path: ($linked | path join "src/a.nu")
      content: "x"
    })
    (claude-prompt $linked "10:05" "then the removed directory")
    (claude-tool $linked "10:06" "Write" {
      file_path: ($linked | path join ".claude/agent-memory-local/gone/b.nu")
      content: "x"
    })
  ]

  let output = (digest-output $dir)
  let day = $output.days.0

  assert equal $day.sessions.0.repo "app"
  assert equal ($day.sessions.0.prompts | get repos) [{app: 1.0} {}]
  assert equal $output.repositories {app: $app}
}

def "test sessions report their repository, and the digest lists labels and repository paths" [] {
  let dir = (mktemp --directory)
  let app = (git-repo $dir "app")
  let cfg = (git-repo $dir "dotfiles")
  mkdir ($app | path join "src")
  mkdir ($dir | path join "scratch")
  transcript $dir ["claude/projects/app/a.jsonl"] [
    (claude-prompt $app "10:00" "ship")
    (claude-tool $app "10:01" "Write" {file_path: ($app | path join "src/a.nu"), content: "x"})
  ]
  transcript $dir ["claude/projects/cfg/b.jsonl"] [
    (claude-prompt $cfg "11:00" "tidy")
    (claude-tool $cfg "11:01" "Write" {file_path: ($cfg | path join "README.md"), content: "x"})
  ]
  transcript $dir ["claude/projects/scratch/c.jsonl"] [
    (claude-prompt ($dir | path join "scratch") "12:00" "file")
  ]

  let output = (digest-output $dir)
  let day = $output.days.0

  assert equal ($output | reject days) {
    labels: {default: ["work"], projects: {dotfiles: ["personal"]}}
    repositories: {app: $app, dotfiles: $cfg}
  }
  assert equal ($day.sessions | select repo cwd) [
    {repo: "app", cwd: $app}
    {repo: "dotfiles", cwd: $cfg}
    {repo: null, cwd: ($dir | path join "scratch")}
  ]
  assert equal ($day.sessions.0 | columns) [
    "tool"
    "session"
    "cwd"
    "repo"
    "prompts"
    "replies"
    "continued"
  ]
}
