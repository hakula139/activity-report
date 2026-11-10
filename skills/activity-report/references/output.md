# Output fields

`activity-digest` prints one JSON document for the requested range of local dates. Each record below lists its fields, their type or unit, and what each one means.

## Top level

| Field          | Type   | Meaning                                                         |
| -------------- | ------ | --------------------------------------------------------------- |
| `labels`       | record | The label configuration, described below.                       |
| `repositories` | record | Each repository named in the document, mapped to its root path. |
| `days`         | list   | One entry per local date in the range, in date order.           |

When two repositories share a directory name, `repositories` keeps the first root found. A linked worktree reports its main checkout.

`labels` holds two keys:

| Key        | Type   | Meaning                                                 |
| ---------- | ------ | ------------------------------------------------------- |
| `default`  | list   | Labels of a repository without an entry in `projects`.  |
| `projects` | record | Labels of each repository, keyed by its directory name. |

## Days

Each day entry has these fields:

| Field      | Type   | Meaning                                            |
| ---------- | ------ | -------------------------------------------------- |
| `date`     | string | Local date, as `YYYY-MM-DD`.                       |
| `weekday`  | string | Abbreviated weekday, such as `Thu`.                |
| `sessions` | list   | Sessions with a prompt or a continuation that day. |
| `runs`     | list   | Agent work that no prompt started.                 |

## Sessions

Each session entry has these fields:

| Field       | Type           | Meaning                                                                           |
| ----------- | -------------- | --------------------------------------------------------------------------------- |
| `tool`      | string         | `claude`, `codex`, or `omp`.                                                      |
| `session`   | string         | The transcript's id.                                                              |
| `cwd`       | string         | The working directory the session recorded.                                       |
| `repo`      | string or null | The directory name of the repository holding `cwd`, or null outside a repository. |
| `prompts`   | list           | Prompts a person typed or answered that day.                                      |
| `replies`   | list           | Final replies for the day.                                                        |
| `continued` | list           | Prompts from earlier days whose turns started that day.                           |

A session's `replies` run from its first prompt that day until its next prompt on a later day. A session listed only through `continued` has an empty list.

## Prompts

Each prompt entry has these fields:

| Field   | Type or unit        | Meaning                                                                                      |
| ------- | ------------------- | -------------------------------------------------------------------------------------------- |
| `at`    | `HH:MM`             | Local clock time.                                                                            |
| `hours` | hours               | Human credit, rounded to four decimal places.                                                |
| `agent` | hours               | Agent time, rounded to four decimal places.                                                  |
| `repos` | record of fractions | Repository shares of the files its turns and delegates wrote. Empty when they wrote nothing. |
| `text`  | string              | Prompt text, cut to `--excerpt-chars` characters, or whole when the option is 0.             |

Human credit is the time from the prompt to the end of its turn, plus `readingMinutes`, cut short by the next prompt in any session and capped at `maxMinutes`. Only attended sessions list prompts. Messages from these sessions appear under `runs`, or join the prompt that delegated to them:

- a headless session
- a sidechain session
- a session whose directory matches `excludedDirs`

A turn the person did not start earns no human credit.

Agent time is the time the prompt's turn and every delegate it started spent, such as:

- a subagent
- a teammate
- a Codex subagent thread
- an OMP advisor

A turn runs from its start to its first reply or last model output, is capped at `agentMaxMinutes`, and stops at its last record before a gap longer than `agentIdleMinutes`. Agent time is counted on the day its turn started, even when the turn continues past midnight. Every transcript adds its own time, so parallel delegates each add to the prompt they followed.

A prompt's `repos` counts the distinct files its turns and delegates wrote, groups them by repository, and gives each repository its fraction of the total, rounded to two decimals and ordered largest first. git-ignored files never count when they resolve inside a checkout, including a file under a directory that no longer exists inside that checkout. A file in a deleted sibling worktree under `<name>__worktrees` counts, because its repository attribution resolves to the main checkout while the path lies outside it. A prompt whose turns wrote no files has an empty record.

## Replies

Each reply entry has `at` and `text`, with the same meaning as a prompt's fields. A reply is the last answer before the next prompt, and it may fall after midnight. A reply with empty text is dropped.

## Continuations

Each continuation entry records a prompt from an earlier day whose turns started that day:

| Field   | Type or unit        | Meaning                                                                                                        |
| ------- | ------------------- | -------------------------------------------------------------------------------------------------------------- |
| `from`  | `YYYY-MM-DD HH:MM`  | The prompt's local date and time.                                                                              |
| `text`  | string              | The prompt's excerpt.                                                                                          |
| `agent` | hours               | Agent time for the turns that started that day.                                                                |
| `repos` | record of fractions | Shares of the files those turns wrote, as above, falling back to the prompt's `repos` when they wrote nothing. |

## Runs

Each run entry describes agent work that no prompt started:

- a Workmux worker
- a headless run
- the start of a session before its first prompt

| Field                            | Type or unit        | Meaning                                                                                                         |
| -------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------- |
| `tool`, `session`, `cwd`, `repo` |                     | The same fields as a session.                                                                                   |
| `at`                             | `HH:MM`             | Local clock time of the run's first turn that day.                                                              |
| `agent`                          | hours               | Agent time for the run's turns that started that day, measured as above.                                        |
| `repos`                          | record of fractions | Repository shares of the files those turns wrote, as above.                                                     |
| `text`                           | string              | The first non-empty text among those turns, cut to `--excerpt-chars` characters, or whole when the option is 0. |
