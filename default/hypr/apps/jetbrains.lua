-- Disable mouse focus (see https://github.com/basecamp/omarchy/pull/5183#issuecomment-4189299971).
hl.window_rule({
  name = "jetbrains-focus",
  match = { class = "^(jetbrains-.*)$" },
  no_follow_mouse = true,
})
