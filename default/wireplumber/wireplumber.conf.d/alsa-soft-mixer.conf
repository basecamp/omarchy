## Use software volume control for all ALSA devices.
## This prevents hardware mixer quirks (like muffled audio on Realtek codecs)
## and provides consistent volume behavior across all hardware.

monitor.alsa.rules = [
  {
    matches = [
      {
        device.name = "~alsa_card.*"
      }
    ]
    actions = {
      update-props = {
        api.alsa.soft-mixer = true
      }
    }
  }
]
