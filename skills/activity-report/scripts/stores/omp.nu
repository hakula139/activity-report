# ==================================================================================================
# Activity Report: OMP
# ==================================================================================================
# Maps OMP transcript records to events.
# ==================================================================================================

use ../lib/text.nu [content-text]
use ../transcripts.nu [read-sessions]

export def sessions [cfg: record, since: datetime]: nothing -> list {
  let store = ($cfg.assistants.omp | path join "sessions")
  read-sessions $cfg $since "omp" ["sessions/**/*.jsonl"] {|records, file|
    let meta = ($records | where type? == "session" | first)

    if $meta == null or $meta.id? == null or $meta.cwd? == null {
      return null
    }

    let cwd = $meta.cwd
    let events = (
      $records
      | each {|r|
        let event = if $r.type != "message" {
          null
        } else {
          let m = $r.message

          if $m.role == "user" {
            let kind = if $m.attribution? == "user" { "prompt" } else { "trigger" }
            {kind: $kind, ts: $r.timestamp, text: ($m.content | content-text)}
          } else if $m.role == "assistant" and $m.stopReason? == "stop" {
            {kind: "reply", ts: $r.timestamp, text: ($m.content | content-text)}
          }
        }

        let model = if $r.type == "message" and $r.message.role? == "assistant" {
          {kind: "model", ts: $r.timestamp}
        }

        [$event $model]
      }
      | flatten
      | compact
    )

    let depth = ($file | path relative-to $store | path split | length)
    {
      id: $meta.id
      cwd: $cwd
      attended: true
      parent: (if $depth > 2 { $"($file | path dirname).jsonl" })
      events: $events
    }
  }
}
