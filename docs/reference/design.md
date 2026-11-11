# Design

`activity-digest` turns the transcripts of Claude Code, Codex, and OMP into one JSON document per range of local dates:

1. Reads assistant state.
2. Projects each session into turns.
3. Links those turns into units owned by a prompt.
4. Measures the human and agent time each unit earned.

This page records the invariants behind that projection.

## Inputs

A run reads a JSON config with three inputs beyond the time limits: `assistantDirs`, `labels`, and `excludedDirs`. Each assistant directory holds the same store the assistant writes. The digest never writes to any of them.

| Assistant   | Sessions read from                                        |
| ----------- | --------------------------------------------------------- |
| Claude Code | `projects/*/*.jsonl` and `projects/*/*/subagents/*.jsonl` |
| Codex       | `sessions/*/*/*/*.jsonl[.zst]` and `archived_sessions/*`  |
| OMP         | `sessions/**/*.jsonl`                                     |

A transcript is JSON lines, optionally compressed. When parsing fails, the reader retries without the transcript's last line, which a running session may have left partial, and a record that is only NUL bytes is skipped.

## Sessions and turns

Each transcript becomes a session with `id`, `cwd`, `attended`, `parent`, and `events`. The tool's reader maps its own record kinds to events:

- **prompt**: a person's message, including an answer to a question and a queued command.
- **trigger**: a turn the tool started.
- **reply**: the model's answer for a turn.
- **abort**: a canceled turn, which cannot borrow a later reply.
- **write**: the files a record wrote.
- **model**: any model output, which ends a turn that never replied.
- **pause**: a gap between records longer than `agentIdleMinutes`, inserted by the session reader.

A turn starts at a prompt or trigger, ends at its first reply or its last model output, and collects the writes that follow its start. Every turn adds its own time, so a parallel delegate spends its own time.

`attended` is false for:

- headless runs (`codex exec`, MCP, SDK entrypoints)
- sidechains
- Codex sessions whose `thread_source` is not `user`
- sessions whose `cwd` matches an entry in `excludedDirs`

Only an attended session's prompts earn human hours.

## Units

A unit is one prompt plus every delegate turn it started. A session's `parent` names the transcript that delegated to it, and a delegate's turn joins the parent turn running at its start. Turns with no prompt behind them form a run, such as a worker, a headless run, or the start of a session before its first prompt.

## Hours

- **Human credit**: a prompt earns the time until its turn ends, plus `readingMinutes`, cut short by the next prompt in any session and capped at `maxMinutes`.
- **Agent time**: a unit's turns add the time from each turn's start to the earliest of its end, its start plus `agentMaxMinutes`, and its idle cut. Agent time is counted on the day its turn started, even when the turn continues past midnight.

Hours are rounded to four decimals internally. The skill rounds the report itself.

## Repositories and shares

Every written path and every session `cwd` is resolved to the repository holding it with `git rev-parse`. A linked worktree resolves to its main checkout, and a deleted sibling worktree resolves to its main checkout before falling back to the nearest existing ancestor. git-ignored files are excluded from shares when they resolve inside a checkout, including files under a directory that no longer exists inside it. A file in a deleted sibling worktree under `<name>__worktrees` counts, because its repository resolves to the main checkout while the path lies outside it.

A unit's `repos` splits its distinct written files among the repositories, rounded to two decimals and ordered largest first. A prompt with no writes keeps an empty `repos`.

## Days and output

A day covers `[00:00, next 00:00)` in local time and lists:

- **sessions**: each session with a prompt credited that day or a continuation that day, holding:

  - its prompts for the day
  - the final replies from its first prompt that day until its next prompt on a later day
  - its continuations

  A session listed only through a continuation has no prompts and no replies.

- **runs**: agent work that no prompt started, with turns started that day.

The top level:

- repeats `labels`
- maps each repository name in the output to its root in `repositories`, keeping the first root found when two repositories share a directory name
- holds one entry per date in `days`

The field reference lives in `skills/activity-report/references/output.md`, so it changes with the output.
