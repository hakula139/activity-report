# ==================================================================================================
# Activity Digest: Units
# ==================================================================================================
# Units, their repository shares and agent time, human credit, and continuations.
# ==================================================================================================

use ./lib/text.nu [excerpt]
use ./repos.nu [shares]

# --------------------------------------------------------------------------------------------------
# Linking
# --------------------------------------------------------------------------------------------------

# The depth of a session's parent chain, zero when no loaded session delegated to it.
def depth [parents: record, transcript: string, seen: list = []]: nothing -> int {
  let parent = ($parents | get -o $transcript)
  if $parent == null or $transcript in $seen {
    0
  } else {
    1 + (depth $parents $parent ($seen | append $transcript))
  }
}

# Give every turn the unit of the prompt whose turn started it, or of the run it belongs to. A
# delegate's turn follows the parent turn that was running, so parallel delegates join one prompt.
export def link []: list -> list {
  let sessions = $in
  let transcripts = ($sessions | get transcript)
  let parents = (
    $sessions
    | where {|s| $s.parent != null and $s.parent in $transcripts }
    | reduce --fold {} {|s, acc| $acc | insert $s.transcript $s.parent }
  )
  let ordered = ($sessions | sort-by {|s| depth $parents $s.transcript })
  let units = (
    $ordered
    | reduce --fold {} {|s, acc|
      let parent = if $s.parent == null {
        []
      } else {
        $acc | get -o $s.parent | default []
      }

      let prompts = if $s.attended {
        $s.turns | where kind == "prompt"
      } else {
        []
      }

      let turns = (
        $s.turns
        | each {|t|
          let own = ($prompts | where ts <= $t.ts | last)
          let anchor = if $own != null or ($parent | is-empty) {
            null
          } else {
            $parent | where ts <= $t.ts | last
          }

          let unit = if $own != null {
            $"($s.transcript)#($own.ts | into int)"
          } else if $anchor != null {
            $anchor.unit
          } else {
            $s.transcript
          }

          $t | insert unit $unit
        }
      )

      $acc | insert $s.transcript $turns
    }
  )

  $sessions | each {|s| $s | update turns ($units | get -o $s.transcript) }
}

# --------------------------------------------------------------------------------------------------
# Shares
# --------------------------------------------------------------------------------------------------

# Each unit's repository shares, from the distinct files it and its delegates wrote.
export def unit-shares [repos: record, ignored: list<string>]: record -> record {
  $in
  | transpose unit turns
  | reduce --fold {} {|unit, acc|
    let paths = ($unit.turns | get -o paths | flatten)
    $acc | insert $unit.unit ($paths | shares $repos $ignored)
  }
}

# --------------------------------------------------------------------------------------------------
# Agent time
# --------------------------------------------------------------------------------------------------

# Time the turns spent, each capped and cut at its `idle` record, the last one before a long gap
# or the next turn's start. Every turn adds, so a parallel delegate spends its own time.
export def agent-hours [cfg: record]: list<record> -> float {
  let spent = (
    $in
    | reduce --fold 0sec {|t, acc|
      $acc + (([$t.end ($t.ts + $cfg.agentMaxMinutes * 1min) $t.idle] | compact | math min) - $t.ts)
    }
  )
  ($spent / 1hr) | math round --precision 4
}

# --------------------------------------------------------------------------------------------------
# Credit
# --------------------------------------------------------------------------------------------------

# Each prompt with earned human hours and same-day unit agent time, rounded to 0.0001.
export def credit-prompts [cfg: record, units: record]: list -> list<record> {
  let timeline = (
    $in
    | where attended
    | each {|s| $s.turns | where kind == "prompt" | insert transcript $s.transcript }
    | flatten
    | sort-by ts
  )

  $timeline
  | enumerate
  | each {|p|
    let until = [
      ($p.item.end + $cfg.readingMinutes * 1min)
      ($p.item.ts + $cfg.maxMinutes * 1min)
      ($timeline | get -o ($p.index + 1) | get -o ts)
    ]
    let hours = ((($until | compact | math min) - $p.item.ts) / 1hr)
    let day = ($p.item.ts | format date "%Y-%m-%d" | into datetime)
    let agent = (
      ($units | get $p.item.unit)
      | where ts >= $day and ts < ($day + 1day)
      | agent-hours $cfg
    )
    $p.item
    | insert hours ($hours | math round --precision 4)
    | insert agent $agent
  }
}

# --------------------------------------------------------------------------------------------------
# Continuations
# --------------------------------------------------------------------------------------------------

# Each prompt's unit turns that started after the prompt's day, one entry per later day: the
# origin's date, time, and text, that day's agent time, and the repository shares of the files it
# wrote, or the prompt's shares when it wrote none.
export def continuations [
  cfg: record
  units: record
  repos: record
  ignored: list<string>
  excerpt_chars: int
]: list -> list<record> {
  $in
  | each {|p|
    let since = ($p.ts | format date "%Y-%m-%d" | into datetime)

    $units
    | get $p.unit
    | where ts >= ($since + 1day)
    | group-by {|t| $t.ts | format date "%Y-%m-%d" }
    | values
    | each {|turns|
      let wrote = (
        $turns
        | get -o paths
        | flatten
        | shares $repos $ignored
      )
      {
        transcript: $p.transcript
        ts: ($turns.0.ts | format date "%Y-%m-%d" | into datetime)
        from: ($p.ts | format date "%Y-%m-%d %H:%M")
        text: ($p.text | excerpt $excerpt_chars)
        agent: ($turns | agent-hours $cfg)
        repos: (if ($wrote | is-empty) { $p.repos } else { $wrote })
      }
    }
  }
  | flatten
}
