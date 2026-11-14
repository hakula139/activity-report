# Design

`activity-report digest` turns the transcripts of Claude Code, Codex, and OMP into one JSON document per range of local dates. It reads assistant state, projects each session into turns, links those turns into units owned by a prompt, and measures the human and agent time each unit earned. This page records the invariants behind that projection.

## Inputs

A run reads a TOML config with four inputs: `assistants`, `labels`, `excluded_dirs`, and `hours`. Each assistant directory holds the same store the assistant writes. The digest never writes to any of them.

| Assistant   | Sessions read from                                        |
| ----------- | --------------------------------------------------------- |
| Claude Code | `projects/*/*.jsonl` and `projects/*/*/subagents/*.jsonl` |
| Codex       | `sessions/*/*/*/*.jsonl[.zst]` and `archived_sessions/*`  |
| OMP         | `sessions/**/*.jsonl`                                     |

A transcript is JSON lines, optionally compressed. When parsing fails, the reader retries without the transcript's last line, which a running session may have left partial, and a record that is only NUL bytes is skipped.

The reader starts with transcripts modified since the first requested local midnight, then loads their parent sessions recursively, including older parents. Plain and compressed copies of one transcript count once. Date filtering happens after sessions are linked, so a recent delegate can continue an older prompt.

## Sessions and turns

Each transcript becomes a session with `id`, `cwd`, `attended`, `parent`, and `events`. The tool's reader maps its own record kinds to events:

- **prompt**: a person's message, including an answer to a question and a queued command.
- **trigger**: a turn the tool started.
- **reply**: the model's answer for a turn.
- **abort**: a canceled turn, which cannot borrow a later reply.
- **model**: any model output, which ends a turn that never replied.
- **pause**: a gap between records longer than `hours.agent_idle_minutes`, inserted by the session reader.

A turn starts at a prompt or trigger, ends at its first reply or its last model output. Every turn adds its own time, so a parallel delegate spends its own time.

`attended` is false for headless runs (`codex exec`, MCP, SDK entrypoints), sidechains, Codex sessions whose `thread_source` is not `user`, and sessions whose `cwd` matches an entry in `excluded_dirs`. Only an attended session's prompts earn human hours.

## Units

A unit is one prompt plus every delegate turn it started. A session's `parent` names the transcript that delegated to it, and a delegate's turn joins the parent turn running at its start. Turns with no prompt behind them form a run, such as a worker, a headless run, or the start of a session before its first prompt.

## Hours

- **Human credit**: a prompt earns the time until its turn ends, plus `hours.reading_minutes`, cut short by the next prompt in any session and capped at `hours.max_minutes`.
- **Agent time**: a unit's turns add the time from each turn's start to the earliest of its end, its start plus `hours.agent_max_minutes`, and its idle cut. Agent time is counted on the day its turn started, even when the turn continues past midnight.

Hours are rounded to four decimals internally. The skill rounds the report itself.

## Repositories

Each session's `cwd` is resolved to its repository with `git rev-parse`. A linked worktree resolves to its main checkout, and a deleted sibling worktree resolves to its main checkout before falling back to the nearest existing ancestor. The skill attributes tasks to projects using the conversation and supporting evidence.

## Days and output

A day covers `[00:00, next 00:00)` in local time. Each entry gives a unit index, human credit, and agent time. Units keep their owner, prompt or run text, final owner replies, and contributing sessions once for the range. The same unit can have entries on several days.

Only referenced units are emitted. Prompt evidence includes its original anchor turn and owner turns started in range. Runs use their first in-range start and owner turns in range. A selected turn's reply can follow midnight or the range's end. Each prompt or trigger interval keeps its last reply, while the first reply still determines the turn's end for time estimation.

The top level repeats `labels`, maps each repository in the units and their sources to its root in `repositories`, and holds the `units` and `days` lists. Sources include only other sessions contributing turns in range. Repeated repository directory names keep the first root found.

The field reference lives in `skills/activity-report/references/output.md`, so it changes with the output.
