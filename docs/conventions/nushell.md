# Nushell

The command and its tests are Nushell. General Nushell conventions and traps live in the [`nushell` skill](https://github.com/hakula139/plugins/blob/main/plugins/hakula-languages/skills/nushell/SKILL.md) in hakula139/plugins, and this page covers the layout and the rules specific to activity-report.

## Scripts

- **Entry point**: `skills/activity-report/scripts/activity-digest.nu` holds `def main`, checks its arguments, and orders the pipeline, and the tests drive it through `$nu.current-exe`.
- **Modules**: `transcripts.nu` reads transcripts and projects turns, `repos.nu` resolves repositories and shares, `units.nu` computes credit and agent time, `days.nu` shapes a day, `lib/text.nu` holds message text and excerpts, and `stores/{claude,codex,omp}.nu` map one assistant's records to events. A module exports what its callers use and keeps every other helper private.
- **Dependencies**: `stores/*` import `transcripts` and `lib/text`, `transcripts` imports `repos`, `units` imports `repos` and `lib/text`, and `days` imports `units`, `repos`, and `lib/text`. The entry imports the stores, `repos`, `units`, and `days`.
- **Order**: order a module's sections as the pipeline first reaches them, and within a section put callees before callers.
- **Config**: the tests build the config as a record and save it as JSON.
- **External tools**: the command calls `git` at a directory and `zstd` on a compressed transcript.
- **Quote style**: use double quotes, switching to single quotes when the text holds a literal backslash or double quote.

## Testing

The tests sit beside the module or entry they test as `<module>.test.nu` and use devkit's `nu-test` runner through `dk.nuTests`.

- **Order**: order tests as the code runs, starting with the first behavior the entry exercises.
- **Builders**: `lib/fixtures.testlib.nu` holds the shared builders, and each test file imports it.
- **Stores as fixtures**: helpers build transcript records and write them as JSON lines. A repository is a real `git init` with a committed `.gitignore`, because the digest resolves repositories with `git`.
- **Timestamps**: fixtures use a fixed day and UTC, and `digest-run` sets `TZ` for the child process, so a local-time computation does not depend on the runner's zone.
- **Assertions**: compare the whole shape a test owns.

## Linting

Don't use `nufmt`, which reindents to four spaces.
