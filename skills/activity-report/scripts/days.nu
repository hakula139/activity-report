# ==================================================================================================
# Activity Digest: Days
# ==================================================================================================
# One day's sessions and runs.
# ==================================================================================================

use ./lib/text.nu [excerpt]
use ./repos.nu [shares]
use ./units.nu [agent-hours]

# --------------------------------------------------------------------------------------------------
# Events
# --------------------------------------------------------------------------------------------------

def stamp [excerpt_chars: int]: record -> record {
  let event = $in
  {
    at: ($event.ts | format date "%H:%M")
    text: ($event.text | excerpt $excerpt_chars)
  }
}

# A turn's final reply is the last one before the next prompt.
def final-replies []: list -> list {
  let events = ($in | where kind in ["prompt" "reply"])
  $events
  | enumerate
  | where {|e|
    $e.item.kind == "reply" and ($events | get -o ($e.index + 1) | get -o kind) != "reply"
  }
  | get item
}

# --------------------------------------------------------------------------------------------------
# Runs
# --------------------------------------------------------------------------------------------------

# A run is agent work no prompt started: a worker, a headless run, or a session before its first
# prompt. Each day lists the runs with turns started that day and their agent time that day.
def agent-run [
  cfg: record
  start: datetime
  session: record
  turns: list
  repos: record
  ignored: list<string>
  excerpt_chars: int
]: nothing -> any {
  let end = ($start + 1day)
  let today = ($turns | where ts >= $start and ts < $end)

  if ($today | is-empty) {
    null
  } else {
    let paths = ($today | get -o paths | flatten)
    let text = (
      $today
      | each {|t| $t.text }
      | where {|t| $t != "" }
      | get -o 0
      | default ""
    )
    {
      tool: $session.tool
      session: $session.id
      cwd: $session.cwd
      repo: $session.repo
      at: ($today.0.ts | format date "%H:%M")
      agent: ($today | agent-hours $cfg)
      repos: ($paths | shares $repos $ignored)
      text: ($text | excerpt $excerpt_chars)
    }
  }
}

# --------------------------------------------------------------------------------------------------
# Days
# --------------------------------------------------------------------------------------------------

export def day [
  cfg: record
  start: datetime
  sessions: list
  credited: list
  units: record
  prompt_units: list<string>
  continuations: list
  repos: record
  ignored: list<string>
  excerpt_chars: int
]: nothing -> record {
  let end = ($start + 1day)
  let today = ($credited | where ts >= $start and ts < $end)
  let later = ($continuations | where ts >= $start and ts < $end)
  let runs = (
    $units
    | transpose unit turns
    | where {|unit| $unit.unit not-in $prompt_units }
    | each {|unit|
      let session = ($sessions | where transcript == $unit.unit | first)
      agent-run $cfg $start $session $unit.turns $repos $ignored $excerpt_chars
    }
    | compact
    | sort-by at
  )

  let sessions = (
    (($today | get transcript) ++ ($later | get transcript))
    | uniq
    | each {|transcript|
      let s = ($sessions | where transcript == $transcript | first)
      let prompts = ($today | where transcript == $transcript)
      let events = if ($prompts | is-empty) {
        []
      } else {
        # Turns started today keep their replies past midnight, until the next prompt.
        let first = ($prompts | first | get ts)
        let next = ($s.turns | where kind == "prompt" and ts >= $end | get -o 0.ts)
        $s.events | where {|e| $e.ts >= $first and ($next == null or $e.ts < $next) }
      }

      {
        tool: $s.tool
        session: $s.id
        cwd: $s.cwd
        repo: $s.repo
        prompts: (
          $prompts
          | each {|p|
            {
              at: ($p.ts | format date "%H:%M")
              hours: $p.hours
              agent: $p.agent
              repos: $p.repos
              text: ($p.text | excerpt $excerpt_chars)
            }
          }
        )
        replies: ($events | final-replies | each { stamp $excerpt_chars } | where text != "")
        continued: (
          $later
          | where transcript == $transcript
          | select from text agent repos
        )
      }
    }
  )

  {
    date: ($start | format date "%Y-%m-%d")
    weekday: ($start | format date "%a")
    sessions: $sessions
    runs: $runs
  }
}
