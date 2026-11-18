#!/usr/bin/env nu

# ==================================================================================================
# Activity Report
# ==================================================================================================
# Prints each day's agent sessions on this host as JSON for the activity-report skill, and the
# resolved configuration.
# ==================================================================================================

use ./config.nu [load]
use ./days.nu [day]
use ./repos.nu [repositories repository-map]
use ./stores/claude.nu
use ./stores/codex.nu
use ./stores/omp.nu
use ./units.nu [credit-prompts evidence link]

# --------------------------------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------------------------------

def parse-date [date: string]: nothing -> string {
  let invalid = {msg: $"Invalid date ($date), expected YYYY-MM-DD"}
  if $date !~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$' { error make $invalid }

  try {
    $date | into datetime --format "%Y-%m-%d" | format date "%Y-%m-%d"
  } catch {
    error make $invalid
  }
}

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
# Output field reference
# https://github.com/hakula139/activity-report/blob/main/skills/activity-report/references/output.md
def "main digest" [
  from: string # First local date, as YYYY-MM-DD
  to?: string # Last local date, as YYYY-MM-DD, the first date by default
  --config: path # TOML config, default ${XDG_CONFIG_HOME:-~/.config}/activity-report/config.toml
  --excerpt-chars: int = 400 # Characters kept per prompt and reply, or 0 for the whole text
]: nothing -> nothing {
  let cfg = (load $config)
  let from = (parse-date $from)
  let to = (parse-date ($to | default $from))

  if $to < $from {
    error make {msg: $"Last date ($to) precedes first date ($from)"}
  }

  if $excerpt_chars < 0 {
    error make {msg: $"Excerpt length ($excerpt_chars) must be 0 or greater"}
  }

  let dates = (seq date --begin-date $from --end-date $to)
  let boundaries = (
    seq date --begin-date $from --days (($dates | length) + 1)
    | each { into datetime }
  )
  let since = ($boundaries | first)
  let until = ($boundaries | last)
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
  let linked = (
    $linked
    | each {|s|
      let root = ($repos | get -o $s.cwd)
      $s | insert repo (if $root != null { $root | path basename })
    }
  )

  let units = ($turns | group-by unit)
  let credited = ($linked | credit-prompts $cfg)

  let days = (
    $boundaries
    | window 2
    | each {|w| day $cfg $w.0 $w.1 $credited $units }
  )
  let selected = ($days | get entries | flatten | get unit | uniq)
  let indices = ($selected | enumerate | each {|u| [$u.item $u.index] } | into record)
  let chosen = if ($selected | is-empty) { {} } else { $units | select ...$selected }
  let units = ($chosen | evidence $linked $credited $since $until $excerpt_chars)
  let names = (
    ($units | get repo) ++ ($units | get sources | flatten | get -o repo)
    | compact
    | uniq
  )

  {
    labels: $cfg.labels
    repositories: (repositories $repos $names)
    units: $units
    days: ($days | update entries { each {|e| $e | update unit ($indices | get $e.unit) } })
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
