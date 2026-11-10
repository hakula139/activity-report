# Releasing

Use the [release skill](https://github.com/hakula139/plugins/blob/main/plugins/hakula-workflow/skills/release/SKILL.md) with the contract below.

## Versioning

- **Before 1.0**: tag `v0.N.0` whenever a user-visible batch lands, and `v0.N.M` for a fix to shipped behavior. A change to the stability surface bumps the minor version and is listed under Breaking changes.
- **After 1.0**: a breaking change to the [stability surface](#stability-surface) bumps the major version, a user-visible addition or change bumps the minor version, and a fix bumps the patch version.

### Stability surface

Within a minor version, stable releases keep these compatible:

- Flags, positional dates, subcommands, and exit codes
- The config file's path, keys, and defaults
- The flake's `packages`, `overlays.default`, and `homeModules.default` outputs
- The digest's JSON output, covering the `days`, `labels`, and `repositories` keys and the fields under them
- The skill's report layout, covering the Projects table, the Days lines, the 0.5-hour rounding, and the labels selection

Transcript formats follow each assistant's own releases, so an assistant release can change what the digest reads. The [README](README.md#tested-with) lists the versions tested with this tool.

## Preparation and verification

Set `version` in `flake.nix` to the release number, update the changelog, and run the [verification block](AGENTS.md#verification). Mark changes to the stability surface with `!` in the conventional commit title.

After publication, verify that `nix run github:hakula139/activity-report/vX.Y.Z -- --help` starts and prints the command's help.
