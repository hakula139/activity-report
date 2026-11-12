# activity-report

[![CI](https://github.com/hakula139/activity-report/actions/workflows/ci.yml/badge.svg)](https://github.com/hakula139/activity-report/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Reconstruct what you worked on over a date range, with human and agent hours per project and task, from the transcripts that [Claude Code](https://claude.com/claude-code), [Codex](https://openai.com/codex/), and [OMP](https://omp.sh) keep on your machine.

## The problem

Coding agents already record what happened. Each session stores its working directory, every prompt and answer, the files it wrote, and which subagents or workers it started. That record is spread across three stores with different formats, and it holds no notion of a project or a task. Turning it into an activity report by hand means reading every transcript and guessing how its turns divide.

`activity-report digest` reads those stores and prints one JSON document for a range of local dates. For each day it lists the sessions, their prompts, the reply each prompt produced, work that no prompt started, and the repositories those turns wrote. The [agent skill](#agent-skill) turns that evidence into an hours-by-project and hours-by-task report.

## Install

### Nix

Run it without installing:

```bash
nix run github:hakula139/activity-report -- digest 2026-10-12
```

Or install it into your profile:

```bash
nix profile install github:hakula139/activity-report
```

The package wraps the command with `git` and `zstd`, so both are on its `PATH`. It covers `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`. Flakes must be enabled, as in `nix --extra-experimental-features 'nix-command flakes' run ...` on a stock install.

The first run may ask to allow the project's Cachix cache. Declining is fine, since the package builds from cache.nixos.org.

Home Manager users add the flake input and import the module:

```nix
inputs.activity-report.url = "github:hakula139/activity-report";

# In the Home Manager configuration
imports = [ inputs.activity-report.homeModules.default ];

programs.activity-report.enable = true;
```

The module installs the command and links the skill into `~/.agents/skills` and `~/.claude/skills`. Set `programs.activity-report.skillDirectories` to change the list. Its `settings` option writes the [configuration](#configuration) below to `activity-report/config.toml`.

## Configuration

The command reads `${XDG_CONFIG_HOME:-~/.config}/activity-report/config.toml`, and `--config` names another file. A missing file at the default path means the built-in defaults, while a missing `--config` file is an error. Tables deep-merge over the defaults, and lists replace them.

```toml
[hours]
reading_minutes = 15
max_minutes = 90

[labels]
default = ["work"]

[labels.projects]
my-project = ["personal"]
```

| Key                        | Default                                | Meaning                                                                                          |
| -------------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `excluded_dirs`            | `[]`                                   | Regexes matching session directories whose prompts earn no human hours, such as worker worktrees |
| `assistants.claude`        | `$CLAUDE_CONFIG_DIR`, else `~/.claude` | Claude Code's state directory                                                                    |
| `assistants.codex`         | `$CODEX_HOME`, else `~/.codex`         | Codex's state directory                                                                          |
| `assistants.omp`           | `~/.omp/agent`                         | OMP's state directory                                                                            |
| `hours.reading_minutes`    | `10`                                   | Minutes a prompt earns after its agent turn ends, for reading the reply                          |
| `hours.max_minutes`        | `60`                                   | Most minutes a single prompt can earn                                                            |
| `hours.agent_max_minutes`  | `120`                                  | Most agent minutes a single turn can earn                                                        |
| `hours.agent_idle_minutes` | `30`                                   | Longest gap in minutes between a turn's records before the rest of the turn earns no time        |
| `labels.default`           | `[]`                                   | Labels given to a project without an entry in `labels.projects`. An empty list covers every task |
| `labels.projects`          | `{}`                                   | Labels of each project by repository directory name                                              |

## Usage

```bash
activity-report config
activity-report digest 2026-10-12
activity-report digest 2026-10-12 2026-10-16
activity-report digest --config ./config.toml --excerpt-chars 0 2026-10-12
```

Dates are local `YYYY-MM-DD` dates. Omitting the second date reports that day alone, and the second date must not precede the first. `--excerpt-chars` keeps the first N characters of each prompt and reply, and `0` keeps the text whole, which is useful when a whole transcript must be inspected.

## Output

`activity-report digest` prints one JSON document for the requested range. [Output fields](skills/activity-report/references/output.md) documents every field, its unit, and how hours are earned. `activity-report config` prints the resolved configuration as JSON.

## Privacy

Treat a digest and a report as private, and redact paths, tokens, and conversation text before sharing either.

The command writes no state. It holds no credentials, opens no network connections, and runs no commands from the assistant stores. `excluded_dirs` removes human hours from matching sessions, while their agent work remains in the digest, as a run or under the prompt that delegated to it.

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

The skill runs `activity-report digest`, which reads the configuration above.

Link or copy the whole directory, never `SKILL.md` alone, because Codex skips a `SKILL.md` that is itself a symlink. Start a new assistant session after linking.

## Development

[`AGENTS.md`](AGENTS.md) is the contributor entry point for people and coding agents alike.

## License

Copyright (c) 2026 [Hakula](https://hakula.xyz). Licensed under the [MIT License](LICENSE).
