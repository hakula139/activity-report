# ==================================================================================================
# Activity Report: Config
# ==================================================================================================
# The TOML schema, its defaults, and the resolved configuration.
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------------------------------

export const DEFAULTS = {
  excluded_dirs: []
  assistants: {
    claude: "~/.claude"
    codex: "~/.codex"
    omp: "~/.omp/agent"
  }
  hours: {
    reading_minutes: 10
    max_minutes: 60
    agent_max_minutes: 120
    agent_idle_minutes: 30
  }
  labels: {
    default: []
    projects: {}
  }
  sources: {
    enabled: []
    gitlab: {
      host: ""
    }
  }
  report: {
    instructions: ""
  }
}

# The environment's value for `name`, or `fallback` when the variable is unset or empty.
def environment-path [name: string, fallback: string]: nothing -> string {
  let value = ($env | get -o $name)
  if ($value | is-empty) { $fallback } else { $value }
}

# The assistant directories as the environment names them, before the home defaults.
def environment-assistants []: nothing -> record {
  {
    claude: (environment-path "CLAUDE_CONFIG_DIR" "~/.claude")
    codex: (environment-path "CODEX_HOME" "~/.codex")
    omp: "~/.omp/agent"
  }
}

# --------------------------------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------------------------------

# The kind of a value, so a list's element type does not affect the comparison.
def kind [value: any]: nothing -> string {
  $value | describe | str replace --regex '<.*>' ''
}

def type-error [path: string, expected: string, actual: string]: nothing -> error {
  error make {msg: $"Config key `($path)` must be ($expected), but is ($actual)"}
}

# `labels.projects` maps any project name to a list of labels.
def check-projects [value: any, path: string]: nothing -> nothing {
  if (kind $value) != "record" {
    type-error $path "record" (kind $value)
  }

  for name in ($value | columns) {
    let labels = ($value | get $name)
    let item = $"($path).($name)"

    if (kind $labels) != "list" {
      type-error $item "list" (kind $labels)
    }

    if ($labels | any {|label| (kind $label) != "string" }) {
      error make {msg: $"Config key `($item)` must be a list of strings"}
    }
  }
}

# The only sources this release reads.
def check-sources [value: list]: nothing -> nothing {
  let allowed = ["github" "gitlab" "calendar" "computer-history"]

  for source in $value {
    if $source not-in $allowed {
      error make {
        msg: $"Config key `sources.enabled` has unknown source `($source)`, expected one of ($allowed | str join ', ')"
      }
    }
  }
}

# Reject an unknown key, and a leaf whose type differs from its default.
def validate [config: record, schema: record, prefix: string]: nothing -> nothing {
  for key in ($config | columns) {
    let path = (if $prefix == "" { $key } else { $"($prefix).($key)" })

    if $key not-in ($schema | columns) {
      error make {msg: $"Unknown config key `($path)`"}
    }

    let value = ($config | get $key)
    let default = ($schema | get $key)
    let expected = (kind $default)
    let actual = (kind $value)

    if $path == "labels.projects" {
      check-projects $value $path
    } else if $expected == "record" {
      if $actual != "record" {
        type-error $path $expected $actual
      }
      validate $value $default $path
    } else if $actual != $expected {
      type-error $path $expected $actual
    } else if $path == "sources.enabled" {
      check-sources $value
    }
  }
}

# --------------------------------------------------------------------------------------------------
# Merge
# --------------------------------------------------------------------------------------------------

# Tables merge over the defaults, and lists replace them.
def deep-merge [base: record, over: record]: nothing -> record {
  $over
  | columns
  | reduce --fold $base {|key, acc|
    let value = ($over | get $key)
    let old = ($acc | get -o $key)

    if (kind $value) == "record" and (kind $old) == "record" {
      $acc | upsert $key (deep-merge $old $value)
    } else {
      $acc | upsert $key $value
    }
  }
}

# --------------------------------------------------------------------------------------------------
# Load
# --------------------------------------------------------------------------------------------------

# The config at `path`, or at `${XDG_CONFIG_HOME:-~/.config}/activity-report/config.toml` when it is
# null. A missing explicit file is an error, while a missing default file means the defaults.
export def load [path?: path]: nothing -> record {
  let file = (
    (
      if $path == null {
        [(environment-path "XDG_CONFIG_HOME" "~/.config") "activity-report" "config.toml"]
        | path join
      } else {
        $path
      }
    )
    | path expand --no-symlink
  )

  let config = if ($file | path exists) {
    open $file
  } else if $path != null {
    error make {msg: $"Config file `($path)` does not exist"}
  } else {
    {}
  }

  validate $config $DEFAULTS ""

  (
    (deep-merge ($DEFAULTS | upsert assistants (environment-assistants)) $config)
    | update assistants {
      {
        claude: ($in.claude | path expand --no-symlink)
        codex: ($in.codex | path expand --no-symlink)
        omp: ($in.omp | path expand --no-symlink)
      }
    }
  )
}
