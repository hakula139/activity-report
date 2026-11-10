# ==================================================================================================
# Activity Digest: Transcripts
# ==================================================================================================
# Reading transcripts, idle pauses, and the event-to-turn projection.
# ==================================================================================================

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

# Read the tool's transcripts that match the globs and changed since the date as sessions. The
# parser maps a transcript's records and file to `id`, `cwd`, `attended`, `parent`, and `events`,
# or to null to skip it. A turn's span stops at its last record before a gap longer than
# `agentIdleMinutes`, or at its next start. Only an attended session's prompts earn human hours.
export def read-sessions [
  cfg: record
  since: datetime
  tool: string
  globs: list<string>
  parse: closure
]: nothing -> list {
  $globs
  | each {|pattern| glob ($cfg.assistantDirs | get $tool | path join $pattern) }
  | flatten
  | where {|file| (ls $file | get 0.modified) >= $since }
  | each {|file| {file: $file, stem: ($file | str replace --regex '\.zst$' "")} }
  | uniq-by stem
  | get file
  | par-each --keep-order {|file|
    let records = (read-transcript $file)
    let session = (do $parse $records $file)

    if $session == null {
      null
    } else {
      let gap = ($cfg.agentIdleMinutes * 1min)
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

      $session
      | insert transcript $file
      | update events { append $pauses }
    }
  }
  | par-each --keep-order {|s|
    let events = (
      $s.events
      | update ts { into datetime | date to-timezone "local" }
      | sort-by ts
      | each {|e|
        if $e.kind == "write" {
          $e | update paths { each {|path| physical $path } }
        } else {
          $e
        }
      }
    )

    $s | merge {
      tool: $tool
      attended: ($s.attended and ($cfg.excludedDirs | all {|pattern| $s.cwd !~ $pattern }))
      events: $events
      turns: ($events | turns)
    }
  }
}
