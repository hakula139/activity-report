# ==================================================================================================
# Activity Report: Dates Probe
# ==================================================================================================

use std/assert

use ./dates.nu [local-time day-start next-day]

def main [] {
  let cases = [
    {
      instant: "2026-03-08T05:00:00Z"
      local: "2026-03-08 00:00 -0500"
      start: "2026-03-08T05:00:00Z"
      next: "2026-03-09T04:00:00Z"
      length: 23hr
    }
    {
      instant: "2026-11-01T04:00:00Z"
      local: "2026-11-01 00:00 -0400"
      start: "2026-11-01T04:00:00Z"
      next: "2026-11-02T05:00:00Z"
      length: 25hr
    }
    {
      instant: "2026-11-01T05:30:00Z"
      local: "2026-11-01 01:30 -0400"
      start: "2026-11-01T04:00:00Z"
      next: "2026-11-02T05:00:00Z"
      length: 25hr
    }
    {
      instant: "2026-11-01T06:30:00Z"
      local: "2026-11-01 01:30 -0500"
      start: "2026-11-01T04:00:00Z"
      next: "2026-11-02T05:00:00Z"
      length: 25hr
    }
  ]
  for c in $cases {
    let local = ($c.instant | local-time)
    let start = ($local | day-start)
    let next = ($local | next-day)

    assert equal {
      local: ($local | format date "%Y-%m-%d %H:%M %z")
      start: ($start | into int)
      next: ($next | into int)
      length: ($next - $start)
    } {
      local: $c.local
      start: ($c.start | into datetime | into int)
      next: ($c.next | into datetime | into int)
      length: $c.length
    } $c.instant
  }
}
