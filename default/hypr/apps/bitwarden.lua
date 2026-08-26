o.window("^(Bitwarden)$", { no_screen_share = true, tag = "+floating-window" })

o.window("(([cC]hrome|[bB]rave|Vivaldi-stable|helium)-nngceckbapebfimnlniiiahkandclblb-Default)|([mM]sedge-_jbkfoedolllekgbhcbcoahefnbanhhlh-Default)", {
  no_screen_share = true,
  float = true,
  no_blur = true,
  max_size = "480 650",
})
