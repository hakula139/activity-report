#!/usr/bin/env nu

# ==================================================================================================
# Activity Report: Entry Tests
# ==================================================================================================

use std/assert

use ./lib/fixtures.testlib.nu *

const SCRIPT = path self "activity-report.nu"

def "test single-digit date components normalize on both ends of the range" [] {
  let dir = (mktemp --directory)

  let output = (digest-output $dir --from "2026-2-9" --to "2026-2-10")

  assert equal ($output.days | get date) ["2026-02-09" "2026-02-10"]
}

def "test invalid dates and reversed ranges are rejected" [] {
  let dir = (mktemp --directory)
  let cases = [
    {
      name: "short year"
      from: "26-2-9"
      to: null
      message: "Invalid date 26-2-9"
    }
    {
      name: "impossible day"
      from: "2026-02-30"
      to: null
      message: "Invalid date 2026-02-30"
    }
    {
      name: "reversed range"
      from: "2026-10-16"
      to: "2026-10-15"
      message: "Last date 2026-10-15 precedes first date 2026-10-16"
    }
  ]

  for c in $cases {
    let run = (digest-run $dir --from=$c.from --to=$c.to)

    assert equal $run.exit_code 1 $c.name
    assert str contains $run.stderr $c.message $c.name
  }
}

def "test a negative excerpt length is rejected" [] {
  let dir = (mktemp --directory)

  let run = (digest-run $dir --excerpt-chars=-1)

  assert equal $run.exit_code 1
  assert str contains $run.stderr "must be 0 or greater"
}

def "test an invalid config is a CLI error" [] {
  let file = (mktemp --directory | path join "config.toml")
  {excluded_dirs: ["["]} | to toml | save $file

  let run = (^$nu.current-exe --no-config-file $SCRIPT config --config $file | complete)

  assert equal $run.exit_code 1
  assert str contains $run.stderr "Config key `excluded_dirs` holds invalid regex `[`"
}
