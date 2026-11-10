# Security policy

## Supported versions

Security fixes go into `main` and ship with the next release. Report vulnerabilities against the latest release or current `main`.

## Reporting a vulnerability

Report vulnerabilities privately through a [GitHub security advisory](https://github.com/hakula139/activity-report/security/advisories/new), not in public issues. Include:

- The release tag or commit you run, and your platform
- The command, its flags, and the assistant versions whose state it read
- Steps to reproduce or a proof of concept
- The impact and any mitigations you know of

The maintainer acknowledges a report within 7 days and shares an assessment within 14 days. For a confirmed vulnerability, the maintainer aims to release a fix within 30 days, coordinates disclosure with the reporter, and publishes the advisory once the fix is released.

## Sensitive data

`activity-digest` reads the local state of three coding assistants. That state contains full conversation text, tool input and output, file paths, and the repositories a session touched, and it can include secrets a session printed or a tool read. The command prints excerpts of that text, and the skill turns them into a report.

- **Standard output** holds the requested excerpt of each prompt and reply. Treat a digest and a report as private, and redact paths, tokens, and conversation text before sharing either.
- **The command writes no state.** It reads assistant stores and the config file, and prints JSON.

A bug can expose more text than the configured excerpt or report activity from a directory the user expected to stay out of the range. The command holds no credentials, opens no network connections, and runs no commands from the assistant stores.

## Trust model

The command runs with the permissions of the user who starts it and reads that user's assistant stores. It trusts the store formats of the assistants it supports, listed in the [README](README.md#tested-with).

The [agent skill](skills/activity-report/SKILL.md) asks the assistant to run `git`, `gh`, `glab`, `vdirsyncer`, and `khal`. Those commands read the same machine and reach the forge the user is signed in to, so install the skill only where that access is intended.
