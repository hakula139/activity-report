# Design

`activity-report digest` normalizes assistant transcripts into turns, links delegated work into units, and estimates daily human and agent time. The [output reference](../../skills/activity-report/references/output.md) owns the field definitions, time formulas, and evidence-selection rules.

## Reading stores

The digest reads assistant stores without modifying them. Its TOML inputs are documented under [Configuration](../../README.md#configuration).

A transcript is JSON lines, optionally compressed. A live session may leave a partial last line, so the reader retries parsing without it. NUL-only records are skipped with a warning.

The reader starts with transcripts modified since the first requested local midnight, then loads their parent sessions recursively, including older parents. Plain and compressed copies count once. Filter dates after linking sessions so recent delegates retain their original prompts.

## Linking turns

Adapters distinguish human prompts, automatic triggers, replies, cancellations, and other model output. The common reader inserts pauses for idle gaps. Canceled turns cannot borrow a later reply, and local commands with no model output do not create agent work.

A delegate's turn joins the parent turn running at its start and follows that turn's owning prompt. Turns without an attended prompt form a run. Attended prompts share one timeline across sessions so the next prompt cuts human credit even when it comes from another session.

Timing uses the first reply, while evidence keeps the last reply within each prompt or trigger interval. Steering prompts can share a time boundary, but only the latest prompt owns the reply text. Parallel delegates each add their own agent time.

## Repository attribution

Resolve session directories to their main checkout. Preserve resolution of deleted sibling worktrees under `<name>__worktrees` before falling back to the nearest existing ancestor, so historical work keeps its repository after cleanup.

The skill attributes tasks to projects from conversation and supporting evidence. Unit sources retain other contributing sessions' directories, while code owns the daily estimates and their boundaries.
