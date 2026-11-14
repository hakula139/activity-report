# ==================================================================================================
# Activity Report: Transcripts
# ==================================================================================================
# Reading transcripts, idle pauses, and the event-to-turn projection.
# ==================================================================================================

use ./lib/dates.nu [local-time]
use ./repos.nu [physical]

# A transcript may end in a partial line while its session is still being written.
def read-transcript [file: string]: nothing -> list {
  let raw = if ($file | str ends-with ".zst") {
    ^zstd -dc $file
  } else {
    open --raw $file
  }

  let text = if ($raw | str contains "\u{0}") {
    let lines = ($raw | lines)
    let corrupt = ($lines | where $it =~ '^\x00+$' | length)

    if $corrupt > 0 {
      print --stderr $"Skipped NUL-only transcript records in ($file): ($corrupt)"
    }

    $lines
    | where $it !~ '^\x00+$'
    | str join "\n"
  } else {
    $raw
  }

  try {
    $text | from json --objects
  } catch {
    $text
    | lines
    | drop 1
    | str join "\n"
    | from json --objects
  }
}

# Give each start its first subsequent reply, or its last model output before the next start, and
# collect the files written until that start. A write therefore belongs to the latest start before
# it in its own session. A turn holds a prompt or model output, so a start with only a local
# command is dropped, and a turn with neither reply nor model output ends where it started.
def turns []: list -> list {
  $in
  | reverse
  | generate {|event, state: record = {
      reply: null
      start: null
      paths: []
      cut: null
      model: null
    }|
    match $event.kind {
      "reply" => {next: ($state | update reply $event.ts)}

      "abort" => {next: ($state | update reply null)}

      "write" => {next: ($state | update paths { append $event.paths })}

      "model" => {next: ($state | update model ($state.model | default $event.ts))}

      "pause" => {next: ($state | update cut $event.ts)}

      _ => {
        let turn = ($event | merge {
          end: ($state.reply | default $state.model | default $event.ts)
          paths: $state.paths
          idle: ($state.cut | default $state.start)
        })
        let kept = ($event.kind == "prompt" or $state.model != null)
        let next = {
          reply: $state.reply
          start: $event.ts
          paths: []
          cut: null
          model: null
        }

        if $kept {
          {out: $turn, next: $next}
        } else {
          {next: $next}
        }
      }
    }
  }
  | reverse
}

def read-session [cfg: record, tool: string, parse: closure, file: string]: nothing -> any {
  let records = (read-transcript $file)
  let session = (do $parse $records $file)

  if $session == null {
    return null
  }

  let gap = ($cfg.hours.agent_idle_minutes * 1min)
  let pauses = (
    $records
    | get -o timestamp
    | compact
    | into datetime
    | sort
    | window 2
    | where {|w| ($w.1 - $w.0) > $gap }
    | each {|w| {kind: "pause", ts: $w.0} }
  )
  let events = (
    $session.events
    | append $pauses
    | update ts { local-time }
    | sort-by ts
    | each {|e|
      if $e.kind == "write" {
        $e | update paths { each {|path| physical $path } }
      } else {
        $e
      }
    }
  )
  $session | merge {
    transcript: $file
    tool: $tool
    attended: ($session.attended and ($cfg.excluded_dirs | all {|p| $session.cwd !~ $p }))
    events: $events
    turns: ($events | turns)
  }
}

def transcript-stem [file: string]: nothing -> string {
  $file | str replace --regex '\.zst$' ""
}

# Read recent transcripts and their ancestor closure. The parser maps records and a file to
# `id`, `cwd`, `attended`, `parent`, and `events`, or null to skip it.
export def read-sessions [
  cfg: record
  since: datetime
  tool: string
  globs: list<string>
  parse: closure
]: nothing -> list {
  let files = (
    $globs
    | each {|pattern| glob ($cfg.assistants | get $tool | path join $pattern) }
    | flatten
    | each {|file|
      {
        file: $file
        stem: (transcript-stem $file)
        modified: (ls $file | get 0.modified)
      }
    }
  )
  mut pending = ($files | where modified >= $since | uniq-by stem | get file)
  mut seen = []
  mut sessions = []

  while ($pending | is-not-empty) {
    $seen = ($seen ++ ($pending | each {|file| transcript-stem $file }))
    let loaded = (
      $pending
      | par-each --keep-order {|file| read-session $cfg $tool $parse $file }
      | compact
    )
    $sessions = ($sessions ++ $loaded)
    $pending = (
      $loaded
      | get -o parent
      | compact
      | each {|file| transcript-stem $file }
      | uniq
      | where {|stem| $stem not-in $seen }
      | each {|stem| $files | where stem == $stem | get -o 0.file }
      | compact
    )
  }

  let loaded = $sessions
  $loaded | update parent {
    let parent = $in
    if $parent == null {
      null
    } else {
      let stem = (transcript-stem $parent)
      $loaded | where {|s| (transcript-stem $s.transcript) == $stem } | get -o 0.transcript
    }
  }
}
