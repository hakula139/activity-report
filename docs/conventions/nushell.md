# Nushell

The command and its tests are Nushell. General Nushell conventions and traps live in the [`nushell` skill](https://github.com/hakula139/plugins/blob/main/plugins/hakula-languages/skills/nushell/SKILL.md) in hakula139/plugins, and this page covers the layout and the rules specific to activity-report.

## Scripts

- **Entry point**: `skills/activity-report/scripts/activity-digest.nu` holds `def main`, checks its arguments, orders the pipeline, and imports the stores, `repos`, `units`, and `days`.
- **Config**: the tests build the config as a record and save it as JSON.
- **External tools**: the command calls `git` at a directory and `zstd` on a compressed transcript.

| Module                         | Holds                                 | Imports                      |
| ------------------------------ | ------------------------------------- | ---------------------------- |
| `transcripts.nu`               | Reads transcripts and projects turns  | `repos`, `lib/text`          |
| `repos.nu`                     | Resolves repositories and shares      |                              |
| `units.nu`                     | Computes credit and agent time        | `repos`, `lib/text`          |
| `days.nu`                      | Shapes a day                          | `units`, `repos`, `lib/text` |
| `lib/text.nu`                  | Holds message text and excerpts       |                              |
| `stores/{claude,codex,omp}.nu` | Map one assistant's records to events | `transcripts`, `lib/text`    |

## Testing

The flake runs the tests through `dk.nuTests`.

- **Builders**: `lib/fixtures.testlib.nu` holds the shared builders, and each test file imports it.
- **Stores as fixtures**: helpers build transcript records and write them as JSON lines. A repository is a real `git init` with a committed `.gitignore`, because the digest resolves repositories with `git`.
- **Timestamps**: `digest-run` sets `TZ` for the child process.
