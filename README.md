# activity-report

[![CI](https://github.com/hakula139/activity-report/actions/workflows/ci.yml/badge.svg)](https://github.com/hakula139/activity-report/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Reconstruct what you worked on over a date range, with human and agent hours per project and task, from the transcripts that [Claude Code](https://claude.com/claude-code), [Codex](https://openai.com/codex/), and [OMP](https://omp.sh) keep on your machine.

## The problem

Coding agents already record what happened. Each session stores its working directory, every prompt and answer, the files it wrote, and which subagents or workers it started. That record is spread across three stores with different formats, and it holds no notion of a project or a task. Turning it into an activity report by hand means reading every transcript and guessing how its turns divide.

`activity-digest` reads those stores and prints one JSON document for a range of local dates. For each day it lists the sessions, their prompts, the reply each prompt produced, work that no prompt started, and the repositories those turns wrote. The [agent skill](#agent-skill) turns that evidence into an hours-by-project and hours-by-task report.

## Install

### Nix

Run it without installing:

```bash
nix run github:hakula139/activity-report -- --config ./config.json 2026-10-12
```

Or install it into your profile:

```bash
nix profile install github:hakula139/activity-report
```

The package wraps the command with `git` and `zstd`, so both are on its `PATH`. It covers `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`. Flakes must be enabled, as in `nix --extra-experimental-features 'nix-command flakes' run ...` on a stock install.

The first run may ask to allow the project's Cachix cache. Declining is fine, since the package builds from cache.nixos.org.

## Configuration

The command takes a JSON config file through `--config`:

```json
{
  "excludedDirs": [],
  "labels": {
    "default": ["work"],
    "projects": { "my-project": ["personal"] }
  },
  "readingMinutes": 10,
  "maxMinutes": 60,
  "agentMaxMinutes": 120,
  "agentIdleMinutes": 30,
  "assistantDirs": {
    "claude": "/home/you/.claude",
    "codex": "/home/you/.codex",
    "omp": "/home/you/.omp/agent"
  }
}
```

| Field              | Meaning                                                                                          |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| `excludedDirs`     | Regexes matching session directories whose prompts earn no human hours, such as worker worktrees |
| `labels.default`   | Labels given to a project without an entry in `labels.projects`                                  |
| `labels.projects`  | Labels of each project by repository directory name                                              |
| `readingMinutes`   | Minutes a prompt earns after its agent turn ends, for reading the reply                          |
| `maxMinutes`       | Most minutes a single prompt can earn                                                            |
| `agentMaxMinutes`  | Most agent minutes a single turn can earn                                                        |
| `agentIdleMinutes` | Longest gap in minutes between a turn's records before the rest of the turn earns no time        |
| `assistantDirs`    | Absolute state directories for `claude`, `codex`, and `omp`                                      |

Set `assistantDirs` to each assistant's state directory, as an absolute path:

| Assistant   | State directory                       |
| ----------- | ------------------------------------- |
| Claude Code | `CLAUDE_CONFIG_DIR`, else `~/.claude` |
| Codex       | `CODEX_HOME`, else `~/.codex`         |
| OMP         | `~/.omp/agent`                        |

## Usage

```bash
activity-digest --config ./config.json 2026-10-12
activity-digest --config ./config.json 2026-10-12 2026-10-16
activity-digest --config ./config.json --excerpt-chars 0 2026-10-12
```

Dates are local `YYYY-MM-DD` dates. Omitting the second date reports that day alone, and the second date must not precede the first. `--excerpt-chars` keeps the first N characters of each prompt and reply, and `0` keeps the text whole, which is useful when a whole transcript must be inspected.

## Output

The command prints one JSON document for the requested range. [Output fields](skills/activity-report/references/output.md) documents every field, its unit, and how hours are earned.

## Privacy

Treat a digest and a report as private, and redact paths, tokens, and conversation text before sharing either.

The command writes no state. It holds no credentials, opens no network connections, and runs no commands from the assistant stores. `excludedDirs` removes human hours from matching sessions, while their agent work remains in the digest, as a run or under the prompt that delegated to it.

The [agent skill](skills/activity-report/SKILL.md) asks the assistant to run `git`, `gh`, `glab`, `vdirsyncer`, and `khal`. Those commands read the same machine and reach the forge and calendar the user is signed in to, so install the skill only where that access is intended.

## Tested with

The transcript formats change without notice. The digest is tested on Linux against these versions:

| Assistant   | Tested  |
| ----------- | ------- |
| Claude Code | 2.1.319 |
| Codex       | 0.167.0 |
| OMP         | 18.18.1 |

A newer assistant can add a record kind this command ignores, so that activity then goes uncounted. If a report misses work you know happened, open an issue with the release tag or commit you run and the assistant's version.

## Releases

Releases follow the [versioning policy](RELEASING.md#versioning), and stable releases keep the [stability surface](RELEASING.md#stability-surface) compatible within a minor version.

## Agent skill

The repository ships an [Agent Skill](skills/activity-report/SKILL.md) that reads the digest, gathers repository, forge, calendar, and screen-history evidence, and writes the report.

The skill assumes the command discovers its configuration, which arrives in a later release.

Link or copy the whole directory, never `SKILL.md` alone, because Codex skips a `SKILL.md` that is itself a symlink. Start a new assistant session after linking.

## Development

[`AGENTS.md`](AGENTS.md) is the contributor entry point for people and coding agents alike.

## License

Copyright (c) 2026 [Hakula](https://hakula.xyz). Licensed under the [MIT License](LICENSE).
