# ==================================================================================================
# Activity Report: Config
# ==================================================================================================
# The TOML schema, its defaults, and the resolved configuration.
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------------------------------

const DEFAULTS = {
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
}

# The environment's value for `name`, or `fallback` when the variable is unset or empty.
def environment-path [name: string, fallback: string]: nothing -> string {
  let value = ($env | get -o $name)
  if ($value | is-empty) { $fallback } else { $value }
}

# The assistant directories as the environment names them, before the file or the home defaults.
def environment-assistants []: nothing -> record {
  let names = {claude: "CLAUDE_CONFIG_DIR", codex: "CODEX_HOME"}

  $DEFAULTS.assistants
  | columns
  | reduce --fold {} {|tool, acc|
    let name = ($names | get -o $tool)
    let fallback = ($DEFAULTS.assistants | get $tool)
    let dir = if $name == null { $fallback } else { environment-path $name $fallback }
    $acc | upsert $tool $dir
  }
}

# --------------------------------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------------------------------

# The kind of a value, so a list's element type does not affect the comparison.
def kind [value: any]: nothing -> string {
  $value | describe | str replace --regex '<.*>' ''
}

def type-error [path: string, expected: string, actual: string, file: string]: nothing -> error {
  error make {msg: $"Config key `($path)` must be ($expected), but is ($actual) in `($file)`"}
}

# Raise unless every item of `value` is a string.
def check-strings [value: list, path: string, file: string]: nothing -> nothing {
  if ($value | any {|item| (kind $item) != "string" }) {
    error make {msg: $"Config key `($path)` must be a list of strings in `($file)`"}
  }
}

# `labels.projects` maps any project name to a list of labels.
def check-projects [value: any, path: string, file: string]: nothing -> nothing {
  if (kind $value) != "record" {
    type-error $path "record" (kind $value) $file
  }

  for name in ($value | columns) {
    let labels = ($value | get $name)
    let item = $"($path).($name)"

    if (kind $labels) != "list" {
      type-error $item "list" (kind $labels) $file
    }
    check-strings $labels $item $file
  }
}

# Reject an unknown key, and a leaf whose type differs from its default.
def validate [config: record, schema: record, prefix: string, file: string]: nothing -> nothing {
  for key in ($config | columns) {
    let path = (if $prefix == "" { $key } else { $"($prefix).($key)" })

    if $key not-in ($schema | columns) {
      error make {msg: $"Unknown config key `($path)` in `($file)`"}
    }

    let value = ($config | get $key)
    let default = ($schema | get $key)
    let expected = (kind $default)
    let actual = (kind $value)

    if $path == "labels.projects" {
      check-projects $value $path $file
    } else if $expected == "record" {
      if $actual != "record" {
        type-error $path $expected $actual $file
      }
      validate $value $default $path $file
    } else if $actual != $expected {
      type-error $path $expected $actual $file
    } else if $expected == "list" {
      check-strings $value $path $file
    }

    if $prefix == "hours" {
      let minimum = if $key == "reading_minutes" { 0 } else { 1 }
      if $value < $minimum {
        error make {msg: $"Config key `($path)` must be at least ($minimum) in `($file)`"}
      }
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
    open --raw $file | from toml
  } else if $path != null {
    error make {msg: $"Config file `($path)` does not exist"}
  } else {
    {}
  }

  validate $config $DEFAULTS "" $file

  (
    ($DEFAULTS | upsert assistants (environment-assistants))
    | merge deep --strategy overwrite $config
  )
  | update assistants {
    let assistants = $in

    $assistants
    | columns
    | reduce --fold {} {|tool, acc|
      let dir = ($assistants | get $tool)

      if not ($dir | str starts-with "/") and not ($dir | str starts-with "~") {
        error make {
          msg: $"Config key `assistants.($tool)` must be an absolute path or start with ~ in `($file)`"
        }
      }

      $acc | upsert $tool ($dir | path expand --no-symlink)
    }
  }
}
