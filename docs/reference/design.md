# Design

`activity-digest` turns the transcripts of Claude Code, Codex, and OMP into one JSON document per range of local dates. It reads assistant state, projects each session into turns, links those turns into units owned by a prompt, and measures the human and agent time each unit earned. This page records the invariants behind that projection.

## Inputs

A run reads a JSON config with three inputs beyond the time limits: `assistantDirs`, `labels`, and `excludedDirs`. Each assistant directory holds the same store the assistant writes. The digest never writes to any of them.

| Assistant   | Sessions read from                                        |
| ----------- | --------------------------------------------------------- |
| Claude Code | `projects/*/*.jsonl` and `projects/*/*/subagents/*.jsonl` |
| Codex       | `sessions/*/*/*/*.jsonl[.zst]` and `archived_sessions/*`  |
| OMP         | `sessions/**/*.jsonl`                                     |

A transcript is JSON lines, optionally compressed. When parsing fails, the reader retries without the transcript's first line, and a record that is only NUL bytes is skipped.

## Sessions and turns

Each transcript becomes a session with `id`, `cwd`, `attended`, `parent`, and `events`. The tool's reader maps its own record kinds to events:

- **prompt**: a person's message, including an answer to a question and a queued command.
- **trigger**: a turn started by the tool rather than by the person.
- **reply**: the model's answer for a turn.
- **abort**: a canceled turn, which cannot borrow a later reply.
- **write**: the files a record wrote.
- **model**: any model output, which ends a turn that never replied.
- **pause**: a gap between records longer than `agentIdleMinutes`, inserted by the session reader.

A turn starts at a prompt or trigger, ends at its first reply or its last model output, and collects the writes that follow its start. Every turn adds its own time, so a parallel delegate spends its own time.

`attended` is false for headless runs (`codex exec`, MCP, SDK entrypoints) and sidechains, and false when `cwd` matches an entry in `excludedDirs`. Only an attended session's prompts earn human hours.

## Units

A unit is one prompt plus every delegate turn it started. A session's `parent` names the transcript that delegated to it, and a delegate's turn joins the parent turn running at its start. Turns with no prompt behind them form a run, such as a worker, a headless run, or the start of a session before its first prompt.

## Hours

- **Human credit**: a prompt earns the time until its turn ends, plus `readingMinutes`, cut short by the next prompt in any session and capped at `maxMinutes`.
- **Agent time**: a unit's turns add the time from each turn's start to the earliest of its end, its start plus `agentMaxMinutes`, and its idle cut. Agent time is counted on the day its turn started, even when the turn continues past midnight.

Hours are rounded to four decimals internally. The skill rounds the report itself.

## Repositories and shares

Every written path and every session `cwd` is resolved to the repository holding it with `git rev-parse`. A linked worktree resolves to its main checkout, and a deleted sibling worktree resolves to its main checkout before falling back to the nearest existing ancestor. git-ignored files are excluded from shares, except when their directory no longer exists.

A unit's `repos` splits its distinct written files among the repositories, largest share first. A prompt with no writes keeps an empty `repos`, and the skill falls back to its session's `repo`.

## Days and output

A day covers `[00:00, next 00:00)` in local time and lists:

- **sessions**: each session with prompts credited that day, the replies of turns started that day, and prompts from earlier days whose turns started that day.
- **runs**: agent work that no prompt started, with turns started that day.

The top level repeats `labels`, maps each repository name in the output to its root in `repositories`, and holds one entry per date in `days`. A repeated directory name keeps the first root found.

`main`'s docstring is the field reference a user sees in `--help`, so it changes with the output.
