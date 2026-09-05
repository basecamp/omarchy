#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
source "$ROOT/default/bash/fns/drives"

expect_partition() {
  local device="$1"
  local want="$2"
  local got
  got=$(format-drive-partition "$device")
  [[ $got == "$want" ]] || fail "format-drive-partition $device" "expected $want, got $got"
  pass "format-drive-partition $device → $want"
}

expect_partition /dev/sda /dev/sda1
expect_partition /dev/vdb /dev/vdb1
expect_partition /dev/nvme0n1 /dev/nvme0n1p1
expect_partition /dev/mmcblk0 /dev/mmcblk0p1
expect_partition /dev/loop0 /dev/loop0p1
expect_partition /dev/md0 /dev/md0p1
expect_partition /dev/md127 /dev/md127p1
expect_partition /dev/md/data /dev/md/data1
expect_partition /dev/nbd0 /dev/nbd0p1
