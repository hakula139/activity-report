# Nushell

The command and its tests are Nushell. General Nushell conventions and traps live in the [`nushell` skill](https://github.com/hakula139/plugins/blob/main/plugins/hakula-languages/skills/nushell/SKILL.md) in hakula139/plugins, and this page covers the layout and the rules specific to activity-report.

## Scripts

- **Entry point**: `src/activity-digest.nu` holds `def main` and its helpers, grouped by section, and the tests drive it through `$nu.current-exe`.
- **Config**: the tests build the config as a record and save it as JSON.
- **External tools**: the command calls `git` at a directory and `zstd` on a compressed transcript.
- **Quote style**: use double quotes, switching to single quotes when the text holds a literal backslash or double quote.

## Testing

The tests live in `src/activity-digest.test.nu` and use devkit's `nu-test` runner through `dk.nuTests`.

- **Stores as fixtures**: helpers build transcript records and write them as JSON lines. A repository is a real `git init` with a committed `.gitignore`, because the digest resolves repositories with `git`.
- **Timestamps**: fixtures use a fixed day and UTC, and `digest-run` sets `TZ` for the child process, so a local-time computation does not depend on the runner's zone.
- **Assertions**: compare the whole shape a test owns.

## Linting

Don't use `nufmt`, which reindents to four spaces.
