# Output fields

`activity-digest` prints one JSON document for the requested range of local dates.

## Top level

- `labels` repeats the label configuration. `default` holds the labels of a repository without an entry in `projects`, and `projects` maps each repository directory name to its labels.
- `repositories` maps each repository named anywhere in the document to its root path. When two repositories share a directory name, the first root found is kept. A linked worktree reports its main checkout.
- `days` holds one entry per local date in the range, in date order.

## Days

Each entry in `days` has these fields:

- `date`: the local date, as `YYYY-MM-DD`.
- `weekday`: the abbreviated weekday, such as `Thu`.
- `sessions`: the sessions with activity that day.
- `runs`: agent work that no prompt started.

## Sessions

Each session entry has these fields:

- `tool`: `claude`, `codex`, or `omp`.
- `session`: the transcript's id.
- `cwd`: the working directory the session recorded.
- `repo`: the directory name of the repository holding `cwd`, or null outside a repository.
- `prompts`: the prompts a person typed or answered that day.
- `replies`: the replies of turns that started that day.
- `continued`: prompts from earlier days whose turns started that day.

## Prompts

Each prompt entry has these fields:

- `at`: the local clock time, as `HH:MM`.
- `hours`: human credit in hours, rounded to four decimal places.
- `agent`: agent time in hours, rounded to four decimal places.
- `repos`: each repository's share of the files the prompt's turns and delegates wrote, as a fraction of the total. The record is empty when they wrote nothing.
- `text`: the prompt's text, cut to `--excerpt-chars` characters, or whole when the option is 0.

Human credit is the time from the prompt to the end of its turn, plus `readingMinutes`, cut short by the next prompt in any session and capped at `maxMinutes`. Only an attended session's prompts earn it, so a headless run, a sidechain, an excluded directory, or a turn the person did not start earns none.

Agent time is the time the prompt's turn and every delegate it started spent. A turn runs from its start to its first reply or last model output, is capped at `agentMaxMinutes`, and stops at its last record before a gap longer than `agentIdleMinutes`. Agent time is counted on the day its turn started, even when the turn continues past midnight. Every transcript adds its own time, so parallel delegates each add to the prompt they followed.

A prompt's `repos` counts the distinct files its turns and delegates wrote, groups them by repository, and gives each repository its fraction of the total. git-ignored files never count, except a path under a directory that no longer exists. A prompt whose turns wrote no files has an empty record, and the skill then credits its session's `repo`.

## Replies

Each reply entry has `at` and `text`, with the same meaning as a prompt's fields. A reply is the last answer before the next prompt, and it may fall after midnight.

## Continuations

Each continuation entry records a prompt from an earlier day whose turns started that day:

- `from`: the prompt's local date and time, as `YYYY-MM-DD HH:MM`.
- `text`: the prompt's excerpt.
- `agent`: agent time in hours for the turns that started that day.
- `repos`: the repository shares of the files those turns wrote, falling back to the prompt's `repos` when they wrote nothing.

## Runs

Each run entry describes agent work that no prompt started, such as a worker, a headless run, or the start of a session before its first prompt:

- `tool`, `session`, `cwd`, and `repo`: the same fields as a session.
- `at`: the local clock time of the run's first turn that day.
- `agent`: agent time in hours for the run's turns that started that day, measured as above.
- `repos`: the repository shares of the files those turns wrote.
- `text`: the first non-empty text among those turns, cut to `--excerpt-chars` characters.
