# ==================================================================================================
# Activity Report: OMP
# ==================================================================================================
# Maps OMP transcript records to events.
# ==================================================================================================

use ../lib/text.nu [content-text]
use ../transcripts.nu [read-sessions]

# An OMP call writes one path, and its patch form names a path per `[<path>#<hash>]` header.
def call-paths [cwd: string, call: record]: nothing -> list<string> {
  let args = ($call.arguments | default {})
  let paths = (
    [($args.path?)]
    ++ (
      if $args.input? == null {
        []
      } else {
        $args.input
        | lines
        | parse --regex '^\[\s*(?<path>.+?)#\w+\s*\]$'
        | get path
      }
    )
  )
  $paths
  | compact
  | each {|path| $cwd | path join $path | path expand --no-symlink }
}

export def sessions [cfg: record, since: datetime]: nothing -> list {
  read-sessions $cfg $since "omp" ["sessions/**/*.jsonl"] {|records, file|
    let meta = ($records | where type == "session" | first)
    let cwd = $meta.cwd
    let succeeded = (
      $records
      | where {|r|
        (
          $r.type == "message"
          and $r.message.role? == "toolResult"
          and $r.message.isError? == false
        )
      }
      | get -o message.toolCallId
      | compact
    )
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

        let write = if (
          $r.type == "message"
          and $r.message.role? == "assistant"
          and ($r.message.content | describe --detailed | get type) == "list"
        ) {
          let paths = (
            $r.message.content
            | where {|part|
              (
                $part.type? == "toolCall"
                and $part.name? in ["write" "edit"]
                and $part.id? in $succeeded
              )
            }
            | each {|part| call-paths $cwd $part }
            | flatten
          )
          if ($paths | is-not-empty) {
            {
              kind: "write"
              ts: $r.timestamp
              paths: $paths
            }
          }
        }

        [$event $model $write]
      }
      | flatten
      | compact
    )

    {
      id: $meta.id
      cwd: $cwd
      attended: true
      parent: $"($file | path dirname).jsonl"
      events: $events
    }
  }
}
