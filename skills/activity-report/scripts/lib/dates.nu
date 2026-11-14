# ==================================================================================================
# Activity Report: Dates
# ==================================================================================================

export def local-time []: any -> datetime {
  $in | into datetime | into int | into datetime --timezone "local"
}

export def day-start []: any -> datetime {
  $in | local-time | format date "%Y-%m-%d" | into datetime
}

export def next-day []: any -> datetime {
  let midnight = ($in | day-start)
  $midnight + 1day | format date "%Y-%m-%d" | into datetime
}
