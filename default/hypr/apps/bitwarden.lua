hl.window_rule({ match = { class = "^(Bitwarden)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(Bitwarden)$" }, tag = "+floating-window" })

-- Bitwarden Chrome Extension.
hl.window_rule({ match = { class = "chrome-nngceckbapebfimnlniiiahkandclblb-Default" }, no_screen_share = true })
hl.window_rule({ match = { class = "chrome-nngceckbapebfimnlniiiahkandclblb-Default" }, tag = "+floating-window" })
