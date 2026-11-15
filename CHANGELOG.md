# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
