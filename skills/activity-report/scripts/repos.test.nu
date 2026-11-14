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
    {name: "sub", clock: "10:00", cwd: ($app | path join "src"), repo: "app"}
    {name: "linked", clock: "10:01", cwd: $linked, repo: "app"}
    {name: "live", clock: "10:02", cwd: $live, repo: "app"}
    {name: "gone", clock: "10:03", cwd: ($dir | path join "app__worktrees/gone"), repo: "app"}
    {name: "scratch", clock: "10:04", cwd: ($dir | path join "scratch"), repo: null}
    {name: "gone-wt", clock: "10:05", cwd: ($dir | path join "app-wt/gone"), repo: null}
  ]
  for c in $cases {
    transcript $dir ["claude/projects" $c.name $"($c.name).jsonl"] [
      (claude-prompt $c.cwd $c.clock "write it")
    ]
  }

  let output = (digest-output $dir)
  let day = ($output | day-entries)

  assert equal (($day | where kind == "prompt") | get repo) ($cases | get repo)
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
    ...(claude-active $app ["10:01"])
  ]
  transcript $dir ["claude/projects/cfg/b.jsonl"] [
    (claude-prompt $cfg "11:00" "tidy")
    ...(claude-active $cfg ["11:01"])
  ]
  transcript $dir ["claude/projects/scratch/c.jsonl"] [
    (claude-prompt ($dir | path join "scratch") "12:00" "file")
  ]

  let output = (digest-output $dir)
  let day = ($output | day-entries)

  assert equal ($output | select labels repositories) {
    labels: {default: ["work"], projects: {dotfiles: ["personal"]}}
    repositories: {app: $app, dotfiles: $cfg}
  }
  assert equal (($day | where kind == "prompt") | select repo cwd) [
    {repo: "app", cwd: $app}
    {repo: "dotfiles", cwd: $cfg}
    {repo: null, cwd: ($dir | path join "scratch")}
  ]
  assert equal ($output.units.0 | columns) [
    "kind"
    "tool"
    "session"
    "cwd"
    "repo"
    "from"
    "text"
    "replies"
    "sources"
  ]
}
