# ==================================================================================================
# Activity Digest: Text
# ==================================================================================================
# Message text and excerpts for prompts and replies.
# ==================================================================================================

# Mirrors how Codex Desktop extracts the request from a prompt.
const REQUEST_HEADING = "## My request( for Codex)?:"

# A message's content is a string or a list of typed parts, of which only text parts carry text.
export def content-text []: any -> string {
  let content = $in

  if ($content | describe) == "string" {
    $content
  } else {
    $content
    | default []
    | get -o text
    | compact
    | str join "\n"
  }
}

# Cut text to a number of characters, or keep it whole when the number is zero.
export def excerpt [chars: int]: string -> string {
  let text = $in

  if $chars == 0 {
    $text
  } else {
    let flat = (
      $text
      | str replace --all --regex '\s+' " "
      | str trim
    )

    if ($flat | str length --grapheme-clusters) > $chars {
      $"($flat | str substring --grapheme-clusters 0..<$chars)..."
    } else {
      $flat
    }
  }
}

export def strip-request-prefix []: string -> string {
  let text = $in
  let parts = ($text | split row --regex $REQUEST_HEADING)

  if ($parts | length) == 1 {
    $text
  } else {
    $parts | last | str trim
  }
}
