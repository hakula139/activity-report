#!/usr/bin/env nu

# ==================================================================================================
# Activity Report
# ==================================================================================================
# Prints each day's agent sessions on this host as JSON for the activity-report skill, and the
# resolved configuration.
# ==================================================================================================

use ./config.nu [load]
use ./days.nu [day]
use ./lib/dates.nu [day-start]
use ./repos.nu [repo-name repositories repository-map]
use ./stores/claude.nu
use ./stores/codex.nu
use ./stores/omp.nu
use ./units.nu [continuations credit-prompts link]

# --------------------------------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------------------------------

# Print the agent sessions on this host as JSON, or the resolved config.
def main [...rest: string] {
  if ($rest | is-empty) {
    print (help main)
    return
  }

  error make --unspanned {
    msg: $"Unknown subcommand ($rest | first)"
    help: "Run 'activity-report --help' to list the commands."
  }
}

# Print the agent sessions on this host for a range of local dates as JSON.
#
# The output's fields are documented under Output in the README:
# https://github.com/hakula139/activity-report#output
def "main digest" [
  from: string # First local date, as YYYY-MM-DD
  to?: string # Last local date, as YYYY-MM-DD, the first date by default
  --config: path # TOML config, default ${XDG_CONFIG_HOME:-~/.config}/activity-report/config.toml
  --excerpt-chars: int = 400 # Characters kept per prompt and reply, or 0 for the whole text
]: nothing -> nothing {
  let cfg = (load $config)
  let to = ($to | default $from)

  if $to < $from {
    error make {msg: $"Last date ($to) precedes first date ($from)"}
  }

  if $excerpt_chars < 0 {
    error make {msg: $"Excerpt length ($excerpt_chars) must be 0 or greater"}
  }

  let days = (seq date --begin-date $from --end-date $to | each { day-start })
  let since = ($days | first)
  let sessions = (
    (claude sessions $cfg $since) ++ (codex sessions $cfg $since) ++ (omp sessions $cfg $since)
  )

  let linked = ($sessions | link)
  let turns = (
    $linked
    | each {|s| $s.turns | insert transcript $s.transcript }
    | flatten
  )

  let dirs = ($linked | get cwd | uniq)
  let repos = (repository-map $dirs)
  let linked = ($linked | each {|s| $s | insert repo (repo-name ($repos | get -o $s.cwd)) })

  let units = ($turns | group-by unit)
  let credited = ($linked | credit-prompts $cfg $units)
  let continuations = ($credited | continuations $cfg $units $excerpt_chars)
  let prompt_units = ($credited | get unit | uniq)

  let days = (
    $days
    | each {|start|
      day $cfg $start $linked $credited $units $prompt_units $continuations $excerpt_chars
    }
  )

  let names = (
    (
      ($days | each {|day| $day.sessions | each {|s| $s.repo } })
      ++ ($days | each {|day| $day.runs | each {|r| $r.repo } })
    )
    | flatten
    | compact
    | uniq
  )

  {
    labels: $cfg.labels
    repositories: (repositories $repos $names)
    days: $days
  }
  | to json
  | print
}

# Print the resolved configuration as JSON.
def "main config" [
  --config: path # TOML config, default ${XDG_CONFIG_HOME:-~/.config}/activity-report/config.toml
]: nothing -> nothing {
  load $config | to json | print
}
