#!/usr/bin/env nu

# ==================================================================================================
# Activity Report: Dates Tests
# ==================================================================================================

use std/assert

const PROBE = path self "dates.testlib.nu"

def "test civil midnights and historical offsets survive DST transitions" [] {
  let run = (with-env {TZ: "America/New_York"} {
    ^$nu.current-exe --no-config-file $PROBE | complete
  })

  assert equal $run.exit_code 0 $run.stderr
}
