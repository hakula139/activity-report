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

def environment-assistants []: nothing -> record {
  {
    claude: ($env.CLAUDE_CONFIG_DIR? | default --empty $DEFAULTS.assistants.claude)
    codex: ($env.CODEX_HOME? | default --empty $DEFAULTS.assistants.codex)
    omp: $DEFAULTS.assistants.omp
  }
}

# --------------------------------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------------------------------

def validate [config: record, schema: record, prefix: string, file: string]: nothing -> nothing {
  for entry in ($config | transpose key value) {
    let key = $entry.key
    let value = $entry.value
    let path = (if $prefix == "" { $key } else { $"($prefix).($key)" })

    # Project names are open-ended, with a list of labels for each.
    let default = if $prefix == "labels.projects" {
      []
    } else {
      if $key not-in ($schema | columns) {
        error make {msg: $"Unknown config key `($path)` in `($file)`"}
      }
      $schema | get $key
    }

    let expected = ($default | describe --detailed | get type)
    let actual = ($value | describe --detailed | get type)
    if $actual != $expected {
      error make {msg: $"Config key `($path)` must be ($expected), but is ($actual) in `($file)`"}
    }

    if $expected == "record" {
      validate $value $default $path $file
    } else if $expected == "list" {
      if ($value | any {|item| ($item | describe --detailed | get type) != "string" }) {
        error make {msg: $"Config key `($path)` must be a list of strings in `($file)`"}
      }

      if $path == "excluded_dirs" {
        for pattern in $value {
          try {
            "" =~ $pattern | ignore
          } catch {
            error make {
              msg: $"Config key `excluded_dirs` holds invalid regex `($pattern)` in `($file)`"
            }
          }
        }
      }
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

def expand-home [path: string]: nothing -> string {
  let home = ($env.HOME? | default --empty $nu.home-dir)
  let path = if $path == "~" or ($path | str starts-with "~/") {
    $home + ($path | str substring 1..)
  } else {
    $path
  }
  $path | path expand --no-symlink
}

# The config at `path`, or at `${XDG_CONFIG_HOME:-~/.config}/activity-report/config.toml` when it is
# null. A missing explicit file is an error, while a missing default file means the defaults.
export def load [path?: path]: nothing -> record {
  let config_path = if $path == null {
    let base = ($env.XDG_CONFIG_HOME? | default --empty "~/.config")
    $base | path join "activity-report/config.toml"
  } else {
    $path
  }
  let file = (expand-home $config_path)

  let config = if ($file | path exists) {
    open --raw $file | from toml
  } else if $path != null {
    error make {msg: $"Config file `($path)` does not exist"}
  } else {
    {}
  }

  validate $config $DEFAULTS "" $file

  let resolved = (
    ($DEFAULTS | upsert assistants (environment-assistants))
    | merge deep --strategy overwrite $config
  )
  for entry in ($resolved.assistants | transpose tool dir) {
    if not ($entry.dir | str starts-with "/") and not ($entry.dir | str starts-with "~") {
      error make {
        msg: $"Config key `assistants.($entry.tool)` must be an absolute path or start with ~ in `($file)`"
      }
    }
  }

  $resolved | update assistants {
    items {|tool, dir| [$tool (expand-home $dir)] }
    | into record
  }
}
