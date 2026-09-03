-- Mullvad VPN is a fixed-aspect companion popup; tiling stretches the map.
o.window("^(Mullvad VPN|mullvad-vpn|Mullvad)$", {
  float = true,
  center = true,
  size = { 380, 640 },
})
