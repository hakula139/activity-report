# ==================================================================================================
# Activity Digest: Codex
# ==================================================================================================
# Maps Codex transcript records to events.
# ==================================================================================================

use ../lib/text.nu [content-text]
use ../transcripts.nu [read-sessions]

# Mirrors how Codex Desktop extracts the request from a prompt.
const REQUEST_HEADING = "## My request( for Codex)?:"

def strip-request-prefix []: string -> string {
  let text = $in
  let parts = ($text | split row --regex $REQUEST_HEADING)

  if ($parts | length) == 1 {
    $text
  } else {
    $parts | last | str trim
  }
}

# The transcript of the thread that delegated to a Codex session, or null. Subagents and guardian
# reviews both carry `parent_thread_id` at the top level of the session metadata.
def codex-parent [cfg: record, meta: record]: nothing -> any {
  let id = ($meta | get -o parent_thread_id)

  if $id == null {
    null
  } else {
    let base = $cfg.assistantDirs.codex

    (
      (glob $"($base)/sessions/*/*/*/rollout-*-($id).jsonl")
      ++ (glob $"($base)/sessions/*/*/*/rollout-*-($id).jsonl.zst")
      ++ (glob $"($base)/archived_sessions/rollout-*-($id).jsonl")
      ++ (glob $"($base)/archived_sessions/rollout-*-($id).jsonl.zst")
    )
    | get -o 0
  }
}

export def sessions [cfg: record, since: datetime]: nothing -> list {
  read-sessions $cfg $since "codex" [
    "sessions/*/*/*/*.jsonl"
    "sessions/*/*/*/*.jsonl.zst"
    "archived_sessions/*.jsonl"
    "archived_sessions/*.jsonl.zst"
  ] {|records|
    let meta = ($records | get -o 0.payload)

    # Codex Desktop imports of other assistants' sessions carry no thread source.
    if $meta.thread_source? == null {
      return null
    }

    let events = (
      $records
      | each {|r|
        let event = if $r.type != "event_msg" {
          null
        } else {
          let p = $r.payload

          if $p.type == "task_started" {
            {kind: "trigger", ts: $r.timestamp, text: ""}
          } else if $p.type == "turn_aborted" {
            {kind: "abort", ts: $r.timestamp}
          } else if $p.type == "item_completed" and $p.item.type? == "UserMessage" {
            let text = (
              $p.item.content
              | content-text
              | strip-request-prefix
            )

            {kind: "prompt", ts: $r.timestamp, text: $text}
          } else if $p.type == "item_completed" and $p.item.type? == "FileChange" {
            {kind: "write", ts: $r.timestamp, paths: ($p.item.changes? | default {} | columns)}
          } else if $p.type == "task_complete" and $p.last_agent_message? != null {
            {kind: "reply", ts: $r.timestamp, text: $p.last_agent_message}
          }
        }

        let model = if (
          $r.type == "response_item"
          and (
            $r.payload.type? in ["agent_message" "reasoning" "function_call" "custom_tool_call"]
            or $r.payload.type? == "compaction"
            or $r.payload.role? == "assistant"
          )
        ) {
          {kind: "model", ts: $r.timestamp}
        }

        [$event $model]
      }
      | flatten
      | compact
    )

    # Subagents and reviewers carry other thread sources. `codex exec` and MCP runs are headless.
    let attended = ($meta.thread_source == "user" and $meta.source? not-in ["exec" "mcp"])

    {
      id: $meta.id
      cwd: $meta.cwd
      attended: $attended
      parent: (codex-parent $cfg $meta)
      events: $events
    }
  }
}
