# Nushell

The command and its tests are Nushell. General Nushell conventions and traps live in the [`nushell` skill](https://github.com/hakula139/plugins/blob/main/plugins/hakula-languages/skills/nushell/SKILL.md) in hakula139/plugins, and this page covers the layout and the rules specific to activity-report.

## Scripts

- **Entry point**: `src/activity-digest.nu` holds `def main` with typed parameters, and the tests drive it through `$nu.current-exe`. Until the split, its helpers sit in the same file, grouped by section.
- **Help**: the docstring on `main` documents the output shape and how hours are earned, since `activity-digest --help` is the only reference a user has beside the README.
- **Config**: `main` reads a JSON file passed with `--config`. The record holds `excludedDirs`, `labels`, the four time limits, and `assistantDirs`, and the tests build it as a record and save it as JSON.
- **External tools**: the command calls `git` at a directory and `zstd` on a compressed transcript. Both come from the package wrapper and the test check's `runtimeInputs`, so a test that adds another external tool must add it there too.
- **Quote style**: use double quotes, switching to single quotes when the text holds a literal backslash or double quote.

## Testing

The tests live in `src/activity-digest.test.nu` and use devkit's `nu-test` runner through `dk.nuTests`.

- **One process per test**: the runner collects `test <behavior>` commands and runs each with a fresh `TMPDIR`, so a test builds its stores inside the directory that `mktemp --directory` returns.
- **Stores as fixtures**: helpers build transcript records and write them as JSON lines. A repository is a real `git init` with a committed `.gitignore`, because the digest resolves repositories with `git`.
- **Timestamps**: fixtures use a fixed day and UTC, and `digest-run` sets `TZ` for the child process, so a local-time computation does not depend on the runner's zone.
- **Assertions**: compare the whole shape a test owns, such as a prompt's `at`, `hours`, `agent`, and `repos`, rather than one field that could pass while the rest drifts.

## Linting

`nix develop -c run-hooks` runs `nu-check` over every script, and `editorconfig-checker` owns indentation. Don't use `nufmt`, which reindents to four spaces.
