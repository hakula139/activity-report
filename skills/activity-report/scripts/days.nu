# ==================================================================================================
# Activity Report: Days
# ==================================================================================================
# Daily credit for each unit.
# ==================================================================================================

use ./units.nu [agent-hours]

export def day [
  cfg: record
  start: datetime
  end: datetime
  credited: list
  units: record
]: nothing -> record {
  let prompts = ($credited | where ts >= $start and ts < $end)
  let entries = (
    $units
    | transpose unit turns
    | each {|unit|
      let turns = ($unit.turns | where ts >= $start and ts < $end | sort-by ts)
      if ($turns | is-not-empty) {
        {
          unit: $unit.unit
          ts: $turns.0.ts
          hours: ($prompts | where unit == $unit.unit | get hours | append 0 | math sum)
          agent: ($turns | agent-hours $cfg)
        }
      }
    }
    | compact
    | sort-by ts
    | reject ts
  )

  {
    date: ($start | format date "%Y-%m-%d")
    weekday: ($start | format date "%a")
    entries: $entries
  }
}
