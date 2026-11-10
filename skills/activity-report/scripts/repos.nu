# ==================================================================================================
# Activity Digest: Repositories
# ==================================================================================================
# Repository resolution, ignored files, and file shares.
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------------------------------

# The main checkout of a deleted sibling worktree, `<root>/<name>` for `<root>/<name>__worktrees`,
# or null outside that layout.
def worktrees-main [dir: string]: nothing -> any {
  $dir | parse --regex '^(?<main>.+)__worktrees/' | get -o 0.main
}

# The nearest existing ancestor of a directory without resolving a sibling worktree, so a deleted
# sibling worktree stays outside its main checkout.
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

# Whether a path lies inside a checkout, resolving a symlink in its nearest existing ancestor.
def inside-checkout [path: string, checkout: string]: nothing -> bool {
  let ancestor = (literal-ancestor ($path | path dirname))

  if $ancestor == null {
    false
  } else {
    let root = ($checkout | path expand)
    let resolved = ($ancestor | path expand)
    $resolved == $root or ($resolved | str starts-with $"($root)/")
  }
}

# A written path with its existing directory resolved, so a symlinked parent names the directory the
# write lands in.
export def physical [path: string]: nothing -> string {
  let dir = ($path | path dirname)
  if ($dir | path exists) {
    $dir | path expand | path join ($path | path basename)
  } else {
    $path
  }
}

# --------------------------------------------------------------------------------------------------
# Repositories
# --------------------------------------------------------------------------------------------------

# The repository at a directory, as its checkout and root, or null outside any repository. A linked
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
    {
      checkout: $parts.2
      root: (if $parts.0 == $parts.1 {
        $parts.2
      } else {
        $parts.1 | path dirname
      })
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
    | reduce --fold {} {|ancestor, acc| $acc | insert $ancestor (repository-of $ancestor) }
  )
  $pairs | reduce --fold {} {|pair, acc| $acc | insert $pair.dir ($found | get -o $pair.ancestor) }
}

# The directory name of a repository, or null.
export def repo-name [repo: any]: nothing -> any {
  if $repo == null {
    null
  } else {
    $repo.root | path basename
  }
}

# The repository containing a written path, or null.
def repo-of-file [repos: record, path: string]: nothing -> any {
  $repos | get -o ($path | path dirname)
}

# --------------------------------------------------------------------------------------------------
# Ignored files and shares
# --------------------------------------------------------------------------------------------------

# Paths git ignores, checked once per checkout. A path outside its resolved checkout is never
# reported, since a deleted sibling worktree resolves to its main checkout, whose check-ignore
# rejects it.
export def ignored-paths [repos: record, paths: list<string>]: nothing -> list<string> {
  $paths
  | each {|path| {path: $path, repo: (repo-of-file $repos $path)} }
  | where repo != null
  | where {|row| inside-checkout $row.path $row.repo.checkout }
  | group-by {|row| $row.repo.checkout }
  | transpose checkout rows
  | each {|group|
    let run = (
      $group.rows
      | get path
      | str join (char nul)
      | ^git
        -C $group.checkout
        check-ignore
          -z
          --stdin
      | complete
    )

    if $run.exit_code not-in [0 1] {
      error make {msg: $"git check-ignore failed in ($group.checkout): ($run.stderr | str trim)"}
    }

    $run.stdout
    | split row (char nul)
    | compact --empty
  }
  | flatten
}

# Split a list of files among their repositories by distinct-file count, largest share first.
export def shares [repos: record, ignored: list<string>]: list<string> -> record {
  let repos_of_files = (
    $in
    | uniq
    | where {|path| $path not-in $ignored }
    | each {|path| repo-name (repo-of-file $repos $path) }
    | compact
    | sort
  )
  let counts = ($repos_of_files | uniq --count)

  if ($counts | is-empty) {
    return {}
  }

  let total = ($counts | get count | math sum)
  $counts
  | each {|count| {repo: $count.value, share: ($count.count / $total | math round --precision 2)} }
  | sort-by share --reverse
  | reduce --fold {} {|count, acc| $acc | insert $count.repo $count.share }
}

# --------------------------------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------------------------------

# Every repository named in the output, mapped to its root. A repeated directory name keeps the
# first root found.
export def repositories [repos: record, names: list<string>]: nothing -> record {
  let found = ($repos | values | compact | uniq-by root)

  $names
  | reduce --fold {} {|name, acc|
    let root = ($found | where {|repo| ($repo.root | path basename) == $name } | get -o 0.root)
    if $root == null {
      $acc
    } else {
      $acc | insert $name $root
    }
  }
}
