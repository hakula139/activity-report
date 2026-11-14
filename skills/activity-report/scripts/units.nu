# ==================================================================================================
# Activity Report: Units
# ==================================================================================================
# Units, their agent time, human credit, and evidence.
# ==================================================================================================

use ./lib/text.nu [excerpt]

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
# Agent time
# --------------------------------------------------------------------------------------------------

# Time the turns spent, each capped and cut at its `idle` record, the last one before a long gap
# or the next turn's start. Every turn adds, so a parallel delegate spends its own time.
export def agent-hours [cfg: record]: list<record> -> float {
  let spent = (
    $in
    | reduce --fold 0sec {|t, acc|
      let cap = (
        [$t.end ($t.ts + $cfg.hours.agent_max_minutes * 1min) $t.idle]
        | compact
        | math min
      )
      $acc + ($cap - $t.ts)
    }
  )
  ($spent / 1hr) | math round --precision 4
}

# --------------------------------------------------------------------------------------------------
# Credit
# --------------------------------------------------------------------------------------------------

# Each prompt with earned human hours, rounded to 0.0001.
export def credit-prompts [cfg: record]: list -> list<record> {
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
      ($p.item.end + $cfg.hours.reading_minutes * 1min)
      ($p.item.ts + $cfg.hours.max_minutes * 1min)
      ($timeline | get -o ($p.index + 1) | get -o ts)
    ]
    let hours = ((($until | compact | math min) - $p.item.ts) / 1hr)
    $p.item
    | insert hours ($hours | math round --precision 4)
  }
}

# --------------------------------------------------------------------------------------------------
# Evidence
# --------------------------------------------------------------------------------------------------

# Text is stored once per unit, including an older prompt that owns recent delegated work.
export def evidence [
  sessions: list
  credited: list
  since: datetime
  until: datetime
  excerpt_chars: int
]: record -> list<record> {
  $in
  | transpose unit turns
  | each {|unit|
    let prompt = ($credited | where unit == $unit.unit | first)
    let owner = ($prompt.transcript? | default $unit.unit)
    let session = ($sessions | where transcript == $owner | first)
    let recent = ($unit.turns | where ts >= $since and ts < $until | sort-by ts)
    let origin = ($prompt | default $recent.0)
    let text = if $prompt != null {
      $prompt.text
    } else {
      $recent | where text != "" | get -o 0.text | default ""
    }
    let turns = (
      $session.turns
      | where unit == $unit.unit
      | where {|t|
        ($t.ts >= $since and $t.ts < $until) or ($prompt != null and $t.ts == $prompt.ts)
      }
    )
    let sources = ($recent | get transcript | uniq | where $it != $owner)
    {
      kind: (if $prompt != null { "prompt" } else { "run" })
      tool: $session.tool
      session: $session.id
      cwd: $session.cwd
      repo: $session.repo
      from: ($origin.ts | format date "%+")
      text: ($text | excerpt $excerpt_chars)
      replies: (
        $turns
        | get -o reply
        | compact
        | where text != ""
        | each {|r| {at: ($r.ts | format date "%+"), text: ($r.text | excerpt $excerpt_chars)} }
      )
      sources: (
        $sources
        | each {|source|
          $sessions
          | where transcript == $source
          | first
          | select tool id cwd repo
          | rename tool session cwd repo
        }
      )
    }
  }
}
