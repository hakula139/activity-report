#!/usr/bin/env nu

# ==================================================================================================
# Activity Digest: Entry Tests
# ==================================================================================================

use std/assert

use ./lib/fixtures.testlib.nu *

def "test a negative excerpt length is rejected" [] {
  let dir = (mktemp --directory)

  let run = (digest-run $dir --excerpt-chars=-1)

  assert equal $run.exit_code 1
  assert str contains $run.stderr "must be 0 or greater"
}
