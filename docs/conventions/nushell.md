# Nushell

The command and its tests are Nushell. General conventions and traps live in the [`nushell` skill](https://github.com/hakula139/plugins/blob/main/plugins/hakula-languages/skills/nushell/SKILL.md) in hakula139/plugins. This page covers activity-report's test constraints.

## Testing

The checks live in `tests/`. The `tests` check runs the tests through `dk.nuTests`.

- **Builders**: `lib/fixtures.testlib.nu` holds the shared builders, and each test file imports it.
- **Stores as fixtures**: helpers build transcript records and write them as JSON lines. A repository is a real `git init` with an initial commit, because the digest resolves repositories with `git` and tests create worktrees.
- **Timestamps**: `digest-run` sets `TZ` for the child process.
