# AGENTS.md: activity-report

`activity-report` is a Nushell command and an agent skill that reconstruct what a person worked on over a date range, with human and agent hours per project and task, from the local transcripts of Claude Code, Codex, and OMP.

## Read before you edit

| When the change touches                 | Read                                                                        |
| --------------------------------------- | --------------------------------------------------------------------------- |
| A `.nu` file or a `.test.nu` file       | [Nushell](docs/conventions/nushell.md)                                      |
| CI or a workflow                        | [devkit's CI guide](https://github.com/hakula139/devkit/blob/v3/docs/ci.md) |
| Digest behavior, hours, or output shape | [Design](docs/reference/design.md)                                          |
| A release                               | [RELEASING.md](RELEASING.md)                                                |

## Rules for every change

- Run the pre-commit hooks on every commit. In each new checkout or worktree, run `nix develop -c true` once to install them. Never bypass the hooks with `--no-verify` or `PRE_COMMIT_ALLOW_NO_CONFIG`, and fix the cause whenever a hook, test, or CI job fails.
- Wrap code and comments at 100 columns, counting the indent, end section banners at column 100, and keep a single-line string literal whole at any length.
- Update whatever the change makes stale: the README's usage and configuration, the reference page, the field reference at `skills/activity-report/references/output.md`, and `skills/activity-report/SKILL.md`.
- Issues, pull requests, and their comments link only public material. Never reference local working notes, private paths, or private repositories. Transcripts hold conversation text, paths, and occasionally secrets, so redact all three from anything you paste.

## Verification

```bash
nix flake check --all-systems
nix develop -c run-hooks
nix run . -- --help
```

## Documentation maintenance

Each rule has one home, which other pages link to. Add to this file or `docs/` only a constraint that is invisible, destructive, or already cost someone a debugging session, and leave out whatever a model can read off the flake or the tests.

- `README.md` is for a user evaluating or running the tool: the problem it solves, prerequisites, install, configuration, usage, and output. Keep internal progress out.
- `AGENTS.md` and `docs/` are for whoever changes the code.
- `docs/reference/` explains how the digest measures activity, while `skills/activity-report/SKILL.md` follows a reader through collecting evidence and writing the report. The skill restates only what an agent needs to run and recover a procedure, since skill-directory installs carry only `skills/activity-report/`.

## Code review

Review the change and its affected callers against the convention docs, and check the tests in particular for a claim the fixtures do not exercise. A turn, a unit, and a day each have one owner, so a change that computes hours in two places needs a reason.
