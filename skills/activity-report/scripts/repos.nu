# ==================================================================================================
# Activity Report: Repositories
# ==================================================================================================
# Repository resolution from session directories.
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------------------------------

# The main checkout of a deleted sibling worktree, `<root>/<name>` for `<root>/<name>__worktrees`,
# or null outside that layout.
def worktrees-main [dir: string]: nothing -> any {
  $dir | parse --regex "^(?<main>.+)__worktrees/" | get -o 0.main
}

# The nearest existing ancestor of a directory.
def literal-ancestor [dir: string]: nothing -> any {
  if ($dir | path exists) {
    $dir
  } else {
    let parent = ($dir | path dirname)
    if $parent == $dir {
      null
    } else {
      literal-ancestor $parent
    }
  }
}

# The nearest existing ancestor of a directory, or the main checkout of a deleted sibling worktree.
def existing-ancestor [dir: string]: nothing -> any {
  let ancestor = (literal-ancestor $dir)
  let main = (worktrees-main $dir)
  if (
    $main != null
    and not ($ancestor | str starts-with $"($main)__worktrees/")
    and ($main | path join ".git" | path exists)
  ) {
    $main
  } else {
    $ancestor
  }
}

# --------------------------------------------------------------------------------------------------
# Repositories
# --------------------------------------------------------------------------------------------------

# The repository at a directory, as its root, or null outside any repository. A linked
# worktree's root is its main checkout, the parent of the worktree's common git dir.
def repository-of [dir: string]: nothing -> any {
  let run = (
    ^git
      -C $dir
      rev-parse
        --path-format=absolute
        --git-dir
        --git-common-dir
        --show-toplevel
    | complete
  )

  if $run.exit_code != 0 {
    null
  } else {
    let parts = ($run.stdout | lines)
    if $parts.0 == $parts.1 {
      $parts.2
    } else {
      $parts.1 | path dirname
    }
  }
}

# The repository holding each directory, keyed by directory. Resolving each ancestor once is the
# cache, and a missing directory resolves through its nearest existing ancestor.
export def repository-map [dirs: list<string>]: nothing -> record {
  let pairs = ($dirs | each {|dir| {dir: $dir, ancestor: (existing-ancestor $dir)} })
  let found = (
    $pairs
    | get ancestor
    | compact
    | uniq
    | each {|ancestor| [$ancestor (repository-of $ancestor)] }
    | into record
  )
  $pairs | each {|pair| [$pair.dir ($found | get -o $pair.ancestor)] } | into record
}

# --------------------------------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------------------------------

# Every repository named in the output, mapped to its root. A repeated directory name keeps the
# first root found.
export def repositories [repos: record, names: list<string>]: nothing -> record {
  let found = ($repos | values | compact | group-by {|root| $root | path basename })

  $names
  | where {|name| $name in $found }
  | each {|name| [$name ($found | get $name | first)] }
  | into record
}
