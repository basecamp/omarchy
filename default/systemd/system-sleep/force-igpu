#!/bin/bash

# Use the Vfio to Integrated trick to turn off NVIDIA dgpu when in integrated mode
# without needing to restart the computer. This is needed because computers like the Asus G14
# will wake after suspend in Hybrid mode, even if the system was in Integrated mode before
# suspending.

if [[ $1 == "post" ]]; then
  # small delay so the device is fully re-enumerated
  sleep 4

  # force-bind dGPU to vfio (fully detached from nvidia)
  /usr/bin/supergfxctl -m Vfio
  sleep 1

  # then go back to Integrated, which powers it off again
  /usr/bin/supergfxctl -m Integrated
fi
