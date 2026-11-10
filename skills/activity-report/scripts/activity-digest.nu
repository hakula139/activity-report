#!/usr/bin/env nu

# ==================================================================================================
# Activity Digest
# ==================================================================================================
# Prints each day's agent sessions on this host as JSON for the activity-report skill.
# ==================================================================================================

use ./days.nu [day]
use ./repos.nu [ignored-paths repo-name repositories repository-map]
use ./stores/claude.nu
use ./stores/codex.nu
use ./stores/omp.nu
use ./units.nu [continuations credit-prompts link unit-shares]

# --------------------------------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------------------------------

# Print the agent sessions on this host for a range of local dates as JSON.
#
# The output's fields are documented under Output in the README:
# https://github.com/hakula139/activity-report#output
def main [
  from: string # First local date, as YYYY-MM-DD
  to?: string # Last local date, as YYYY-MM-DD, the first date by default
  --config: path # JSON with the host's labels, policy, and source directories
  --excerpt-chars: int = 400 # Characters kept per prompt and reply, or 0 for the whole text
]: nothing -> nothing {
  let cfg = (open $config)
  let to = ($to | default $from)

  if $to < $from {
    error make {msg: $"Last date ($to) precedes first date ($from)"}
  }

  if $excerpt_chars < 0 {
    error make {msg: $"Excerpt length ($excerpt_chars) must be 0 or greater"}
  }

  let days = (seq date --begin-date $from --end-date $to | each { into datetime })
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

  let paths = ($turns | get -o paths | flatten | uniq)
  let dirs = (($paths | each {|path| $path | path dirname }) ++ ($linked | get cwd) | uniq)
  let repos = (repository-map $dirs)
  let ignored = (ignored-paths $repos $paths)
  let linked = ($linked | each {|s| $s | insert repo (repo-name ($repos | get -o $s.cwd)) })

  let units = ($turns | group-by unit)
  let shares = ($units | unit-shares $repos $ignored)
  let credited = (
    $linked
    | credit-prompts $cfg $units
    | each {|p| $p | insert repos ($shares | get $p.unit) }
  )
  let continuations = ($credited | continuations $cfg $units $repos $ignored $excerpt_chars)
  let prompt_units = ($credited | get unit | uniq)

  let days = (
    $days
    | each {|start|
      (
        day $cfg $start $linked $credited $units $prompt_units $continuations $repos $ignored
          $excerpt_chars
      )
    }
  )

  let names = (
    (
      ($days | each {|day| $day.sessions | each {|s| $s.repo } })
      ++ ($days | each {|day| $day.sessions | each {|s| $s.prompts | get repos | columns } })
      ++ ($days | each {|day| $day.sessions | each {|s| $s.continued | get repos | columns } })
      ++ ($days | each {|day| $day.runs | each {|r| $r.repo } })
      ++ ($days | each {|day| $day.runs | each {|r| $r.repos | columns } })
    )
    | flatten
    | flatten
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
