-- Condensed mode: no gaps, borders hidden for single windows.
hl.config({
  general = {
    gaps_out = 0,
    gaps_in = 0,
  },
  decoration = {
    shadow = { enabled = false },
  },
})

hl.workspace_rule({ workspace = "w[1]", border_size = 0 })
