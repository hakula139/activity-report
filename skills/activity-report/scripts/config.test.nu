#!/usr/bin/env nu

# ==================================================================================================
# Activity Digest: Config Tests
# ==================================================================================================

use std/assert

use ./config.nu [load]

const SCRIPT = path self "activity-report.nu"

# The configuration resolved without a file, with the assistant directories under `home`.
def resolved [home: string]: nothing -> record {
  {
    excluded_dirs: []
    assistants: {
      claude: ($home | path join ".claude")
      codex: ($home | path join ".codex")
      omp: ($home | path join ".omp/agent")
    }
    hours: {
      reading_minutes: 10
      max_minutes: 60
      agent_max_minutes: 120
      agent_idle_minutes: 30
    }
    labels: {default: [], projects: {}}
    sources: {enabled: [], gitlab: {host: ""}}
    report: {instructions: ""}
  }
}

# `config` saved as TOML in a fresh directory.
def save-config [config: record]: nothing -> string {
  let file = (mktemp --directory | path join "config.toml")
  $config | to toml | save $file
  $file
}

def "test without a config file the defaults resolve with assistant directories under home" [] {
  let dir = (mktemp --directory)
  hide-env --ignore-errors CLAUDE_CONFIG_DIR CODEX_HOME

  let config = (with-env {XDG_CONFIG_HOME: $dir} { load })

  assert equal $config (resolved $nu.home-dir)
}

def "test assistant directories come from the file, then a nonempty variable, then home" [] {
  let set = {CLAUDE_CONFIG_DIR: "/home/u/claude", CODEX_HOME: "/home/u/codex"}
  let empty = {CLAUDE_CONFIG_DIR: "", CODEX_HOME: ""}
  let from_env = {claude: "/home/u/claude", codex: "/home/u/codex"}
  let from_file = {claude: "/home/u/file", codex: "/home/u/codex"}
  let file_config = {assistants: {claude: "/home/u/file"}}
  let cases = [
    {name: "set", environment: $set, config: {}, assistants: $from_env}
    {name: "empty", environment: $empty, config: {}, assistants: {}}
    {name: "file", environment: $set, config: $file_config, assistants: $from_file}
  ]

  for c in $cases {
    let file = (save-config $c.config)
    let config = (with-env $c.environment { load $file })

    let expected = (resolved $nu.home-dir | update assistants { merge $c.assistants })
    assert equal $config $expected $c.name
  }
}

def "test invalid keys and values are rejected with their dotted key" [] {
  let cases = [
    {
      name: "unknown key"
      config: {colour: "blue"}
      message: "Unknown config key `colour`"
    }
    {
      name: "unknown nested key"
      config: {hours: {max: 90}}
      message: "Unknown config key `hours.max`"
    }
    {
      name: "leaf for a table"
      config: {hours: 90}
      message: "Config key `hours` must be record, but is int"
    }
    {
      name: "leaf type"
      config: {hours: {max_minutes: "90"}}
      message: "Config key `hours.max_minutes` must be int, but is string"
    }
    {
      name: "list type"
      config: {excluded_dirs: "/home/u"}
      message: "Config key `excluded_dirs` must be list, but is string"
    }
    {
      name: "projects type"
      config: {labels: {projects: ["work"]}}
      message: "Config key `labels.projects` must be record, but is list"
    }
    {
      name: "project type"
      config: {labels: {projects: {app: "work"}}}
      message: "Config key `labels.projects.app` must be list, but is string"
    }
    {
      name: "project labels"
      config: {labels: {projects: {app: ["work" 1]}}}
      message: "Config key `labels.projects.app` must be a list of strings"
    }
    {
      name: "unknown source"
      config: {sources: {enabled: ["github" "jira"]}}
      message: "Config key `sources.enabled` has unknown source `jira`, expected one of github, gitlab, calendar, computer-history"
    }
  ]

  for c in $cases {
    let file = (save-config $c.config)
    let message = (try { load $file } catch {|e| $e.msg })

    assert equal $message $c.message $c.name
  }
}

def "test a config file overrides nested keys and keeps their sibling defaults" [] {
  let sources = ["github" "gitlab" "calendar" "computer-history"]
  let file = (save-config {
    excluded_dirs: ["/home/u/scratch"]
    hours: {max_minutes: 90}
    labels: {projects: {app: ["work"]}}
    sources: {enabled: $sources}
    report: {instructions: "Be brief."}
  })
  hide-env --ignore-errors CLAUDE_CONFIG_DIR CODEX_HOME

  let config = (load $file)

  let expected = (
    resolved $nu.home-dir
    | update excluded_dirs ["/home/u/scratch"]
    | update hours.max_minutes 90
    | update labels.projects {app: ["work"]}
    | update sources.enabled $sources
    | update report.instructions "Be brief."
  )
  assert equal $config $expected
}

def "test without a path the file under the XDG config home is read, or under home when empty" [] {
  let dir = (mktemp --directory)
  let home = ($dir | path join "home")
  let xdg = ($dir | path join "xdg")
  let cases = [
    {name: "set", xdg: $xdg, root: $xdg, max_minutes: 90}
    {name: "empty", xdg: "", root: ($home | path join ".config"), max_minutes: 45}
  ]
  for c in $cases {
    let file = ($c.root | path join "activity-report/config.toml")
    mkdir ($file | path dirname)
    {hours: {max_minutes: $c.max_minutes}} | to toml | save $file
  }
  hide-env --ignore-errors CLAUDE_CONFIG_DIR CODEX_HOME

  for c in $cases {
    let run = (
      with-env {HOME: $home, XDG_CONFIG_HOME: $c.xdg} {
        ^$nu.current-exe --no-config-file $SCRIPT config
        | complete
      }
    )
    assert equal $run.exit_code 0 $run.stderr

    let expected = (resolved $home | update hours.max_minutes $c.max_minutes)
    assert equal ($run.stdout | from json) $expected $c.name
  }
}

def "test an explicit config path that does not exist is an error" [] {
  let file = (mktemp --directory | path join "config.toml")

  let message = (try { load $file } catch {|e| $e.msg })

  assert equal $message $"Config file `($file)` does not exist"
}

def "test assistant directories expand a leading tilde without resolving symlinks" [] {
  let dir = (mktemp --directory)
  mkdir ($dir | path join "real/codex")
  ^ln -s ($dir | path join "real") ($dir | path join "link")
  let codex = ($dir | path join "link/codex")
  let file = (save-config {assistants: {claude: "~/claude", codex: $codex}})

  let config = (load $file)

  let expected = (
    resolved $nu.home-dir
    | update assistants.claude ($nu.home-dir | path join "claude")
    | update assistants.codex $codex
  )
  assert equal $config $expected
}
