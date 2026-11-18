# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.2] - 2026-11-18

### Changed

- Accept single-digit months and days in date arguments ([#17](https://github.com/hakula139/activity-report/pull/17)).

### Fixed

- Use the same local midnight boundaries for daily entries and evidence across daylight-saving changes. When loading configuration, report invalid `excluded_dirs` regexes and honor in-process `HOME` overrides ([#16](https://github.com/hakula139/activity-report/pull/16), [#17](https://github.com/hakula139/activity-report/pull/17)).
- Find transcripts in store paths containing brackets or backslashes and preserve symlink paths when linking delegates. Validate Claude and Codex parent IDs and assign OMP parents only to nested sessions. Skip empty `.jsonl` transcripts and sessions with incomplete metadata, and tolerate truncated Claude subagent `.meta.json` files ([#16](https://github.com/hakula139/activity-report/pull/16), [#17](https://github.com/hakula139/activity-report/pull/17)).
- _(nix)_ Reuse the flake's locked package in `overlays.default` and `homeModules.default` on matching native platforms. Use the consumer's package set for alternate C libraries, static builds, and cross compilation ([#16](https://github.com/hakula139/activity-report/pull/16)).

[0.2.2]: https://github.com/hakula139/activity-report/compare/v0.2.1...v0.2.2

## [0.2.1] - 2026-11-15

### Fixed

- _(codex)_ Restore agent time for native sessions without `thread_source`, exclude imported history, and preserve native continuations ([#14](https://github.com/hakula139/activity-report/pull/14)).

[0.2.1]: https://github.com/hakula139/activity-report/compare/v0.2.0...v0.2.1

## [0.2.0] - 2026-11-15

### Breaking changes

- Replace daily sessions, runs, and continuations with shared units and daily entries. Preserve full local timestamps and contributing-session directories for project attribution ([#11](https://github.com/hakula139/activity-report/pull/11)).
- Remove file-count repository shares from prompts, continuations, and runs. The reporting skill attributes tasks to projects from conversation and repository evidence ([#10](https://github.com/hakula139/activity-report/pull/10)).

[0.2.0]: https://github.com/hakula139/activity-report/compare/v0.1.0...v0.2.0

## [0.1.0] - 2026-11-14

### Added

- Reconstruct human and agent hours by local day from Claude Code, Codex, and OMP transcripts, including delegated work and repository shares ([#1](https://github.com/hakula139/activity-report/pull/1)).
- Configure assistant stores, hour limits, exclusions, and project labels through TOML, inspect resolved settings with `config`, and install through Nix or Home Manager ([#5](https://github.com/hakula139/activity-report/pull/5)).
- Gather supporting repository, forge, calendar, and screen-history evidence with the bundled reporting skill ([#1](https://github.com/hakula139/activity-report/pull/1)).

[0.1.0]: https://github.com/hakula139/activity-report/releases/tag/v0.1.0
