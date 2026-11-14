# ==================================================================================================
# Activity Report: Claude Code
# ==================================================================================================
# Maps Claude Code transcript records to events.
# ==================================================================================================

use ../lib/text.nu [content-text]
use ../transcripts.nu [read-sessions]

def human [r: record]: nothing -> bool {
  $r.origin?.kind? == "human"
}

# A question's answers become a prompt, one `question: answer` line per entry.
def question [r: record]: nothing -> any {
  let result = $r.toolUseResult?

  if not ($result | describe | str starts-with "record") {
    return null
  }

  let answers = ($result | get -o answers | default {})

  if ($answers | is-empty) {
    null
  } else {
    let text = (
      $answers
      | items {|question, answer| $"($question): ($answer)" }
      | str join "\n"
    )
    {kind: "prompt", ts: $r.timestamp, text: $text}
  }
}

# Absolute paths a Claude record wrote: Edit and Write name a file, NotebookEdit a notebook.
def writes [r: record, succeeded: list]: nothing -> list<string> {
  if ($r.message.content | describe --detailed | get type) != "list" {
    return []
  }

  $r.message.content
  | where {|part|
    (
      $part.type? == "tool_use"
      and $part.name? in ["Edit" "Write" "NotebookEdit"]
      and $part.id? in $succeeded
    )
  }
  | each {|part|
    if $part.name == "NotebookEdit" {
      $part.input.notebook_path?
    } else {
      $part.input.file_path?
    }
  }
  | compact
}

# Subagents end their run with a SubagentHandback call in place of a final text reply.
def reply [r: record]: nothing -> bool {
  $r.message.stop_reason? == "end_turn" or "SubagentHandback" in ($r.message.content | get -o name)
}

# The transcript of the session that delegated to a Claude session, or null. A subagent names its
# parent agent, and otherwise its lead. A teammate names its lead's session id.
def parent [cfg: record, records: list, file: string]: nothing -> any {
  let dir = ($file | path dirname)

  if ($dir | path basename) == "subagents" {
    let meta_file = ($file | str replace --regex '\.jsonl$' ".meta.json")
    let meta = (open --raw $meta_file | from json)
    let parent_agent = ($meta | get -o parentAgentId)
    if $parent_agent != null {
      $dir | path join $"agent-($parent_agent).jsonl"
    } else {
      $"($dir | path dirname).jsonl"
    }
  } else {
    let team = ($records | get -o teamName | compact | get -o 0)

    if $team == null or not ($team | str starts-with "session-") {
      null
    } else {
      let id = ($team | str replace "session-" "")
      glob $"($cfg.assistants.claude)/projects/*/($id)*.jsonl" | get -o 0
    }
  }
}

export def sessions [cfg: record, since: datetime]: nothing -> list {
  let globs = ["projects/*/*.jsonl" "projects/*/*/subagents/*.jsonl"]

  read-sessions $cfg $since "claude" $globs {|records, file|
    let cwd = ($records | get -o cwd | compact | get -o 0)

    if $cwd == null {
      return null
    }

    let succeeded = (
      $records
      | each {|r|
        if ($r.message?.content? | describe --detailed | get type) == "list" {
          $r.message.content
          | where {|part| $part.type? == "tool_result" and $part.is_error? != true }
          | get -o tool_use_id
        }
      }
      | flatten
      | compact
    )
    let events = (
      $records
      | each {|r|
        let event = if $r.isCompactSummary? == true {
          null
        } else if (
          $r.type == "user"
          and $r.toolUseResult? == null
          and not (
            ($r.message.content? | describe --detailed | get type) == "list"
            and ($r.message.content | any {|part| $part.type? == "tool_result" })
          )
        ) {
          let kind = if (human $r) { "prompt" } else { "trigger" }
          {kind: $kind, ts: $r.timestamp, text: ($r.message.content | content-text)}
        } else if (
          $r.type == "attachment"
          and $r.attachment.type? == "queued_command"
          and (human $r.attachment)
        ) {
          {kind: "prompt", ts: $r.timestamp, text: ($r.attachment.prompt | content-text)}
        } else if $r.type == "user" {
          question $r
        } else if $r.type == "assistant" {
          if (reply $r) {
            {kind: "reply", ts: $r.timestamp, text: ($r.message.content | content-text)}
          }
        }

        let model = if $r.type == "assistant" or $r.isCompactSummary? == true {
          {kind: "model", ts: $r.timestamp}
        }

        let write = if $r.type == "assistant" {
          let paths = (writes $r $succeeded)
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

    let id = ($file | path parse | get stem)
    let entrypoint = ($records | get -o entrypoint | compact | get -o 0 | default "")
    let headless = ($entrypoint | str starts-with "sdk")
    let attended = ((not $headless) and ($records.0.isSidechain? != true))
    {
      id: $id
      cwd: $cwd
      attended: $attended
      parent: (parent $cfg $records $file)
      events: $events
    }
  }
}
