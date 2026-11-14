# Output fields

`activity-report digest` prints one JSON document for a range of local dates. Time values are reproducible estimates in hours, rounded to four decimals.

## Top level

| Field          | Type   | Meaning                                                                 |
| -------------- | ------ | ----------------------------------------------------------------------- |
| `labels`       | record | `default` labels and `projects` labels keyed by repository name.        |
| `repositories` | record | Repository names in units and sources, mapped to main checkout paths.   |
| `units`        | list   | Prompt-owned or independent agent work, with text stored once per unit. |
| `days`         | list   | Requested local dates in ascending order, including days with no work.  |

A linked worktree reports its main checkout. When repository directory names collide, `repositories` keeps the first root found. A missing project label entry uses `labels.default`.

## Units

Only units referenced by a requested day are included. A unit belongs to one attended prompt, including the turns it delegated, or is a run without an attended prompt. A recent delegate can keep an older prompt and its evidence in the output.

| Field     | Type           | Meaning                                                             |
| --------- | -------------- | ------------------------------------------------------------------- |
| `kind`    | string         | `prompt` or `run`.                                                  |
| `tool`    | string         | Owner's assistant: `claude`, `codex`, or `omp`.                     |
| `session` | string         | Owner session's id.                                                 |
| `cwd`     | string         | Owner session's working directory.                                  |
| `repo`    | string or null | Repository holding `cwd`, or null outside a repository.             |
| `from`    | timestamp      | Original prompt time, or first in-range turn start for a run.       |
| `text`    | string         | Prompt text, or first nonempty in-range start text for a run.       |
| `replies` | list           | Final owner replies, each with a timestamp `at` and message `text`. |
| `sources` | list           | Other sessions contributing turns within the requested range.       |

Each source has `tool`, `session`, `cwd`, and `repo`, with the same meaning as the owner's fields. A source appears once per unit. Use these directories, the conversation, and supporting evidence to attribute projects.

Timestamps include the full local date, time, and UTC offset, keeping repeated daylight-saving clock times distinct. `text` and reply text are cut to `--excerpt-chars` characters, and 0 keeps them whole.

Each prompt or trigger interval keeps its last reply. Steering prompts sharing a reply retain it only on the latest prompt. Replies come from owner turns started in range, plus the anchor prompt's turn even when it predates the range. A selected turn keeps its reply past midnight or the range's end. Empty replies are omitted.

## Days

| Field     | Type   | Meaning                                                   |
| --------- | ------ | --------------------------------------------------------- |
| `date`    | string | Local date, as `YYYY-MM-DD`.                              |
| `weekday` | string | Abbreviated weekday, such as `Thu`.                       |
| `entries` | list   | Units active that day, ordered by their first turn start. |

Each entry has these fields:

| Field   | Type  | Meaning                                                   |
| ------- | ----- | --------------------------------------------------------- |
| `unit`  | int   | Zero-based index into the top-level `units` list.         |
| `hours` | hours | Human credit, zero for a run or later-day delegated work. |
| `agent` | hours | Time spent by the unit's turns started that day.          |

A unit can have an entry on several days without repeating its text. Zero-time activity is retained. Days follow local civil midnights, including daylight-saving transitions.

Human credit runs from a prompt to the end of its turn, plus `hours.reading_minutes`, cut short by the next prompt in any attended session and capped at `hours.max_minutes`. It belongs to the prompt's day. Headless sessions, sidechains, and directories matching `excluded_dirs` earn no human credit.

A turn ends at its first reply or last model output. Agent time stops at the earliest of that end, `hours.agent_max_minutes` after the start, and the last record before a gap longer than `hours.agent_idle_minutes`. It belongs to the turn's start day, even across midnight. Parallel delegates each add their own time to the owning unit.
