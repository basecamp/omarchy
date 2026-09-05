#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

write_cpuinfo_flags() {
  printf 'flags\t\t: %s\n' "$1" >"$tmp_dir/cpuinfo"
}

hw_x86_64_v3() {
  OMARCHY_CPUINFO_PATH="$tmp_dir/cpuinfo" OMARCHY_UNAME_M="${OMARCHY_UNAME_M:-x86_64}" "$ROOT/bin/omarchy-hw-x86-64-v3"
}

assert_detects() {
  local description="$1"

  hw_x86_64_v3 || fail "$description"
  pass "$description"
}

assert_rejects() {
  local description="$1"

  if hw_x86_64_v3; then
    fail "$description"
  fi
  pass "$description"
}

# Ivy Bridge (e.g. i7-3520M): has AVX but not AVX2/BMI/FMA.
write_cpuinfo_flags "fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ss ht syscall nx rdtscp lm constant_tsc rep_good nopl xtopology nonstop_tsc aperfmperf tsc_known_freq pni pclmulqdq est ssse3 fma cx16 sse4_1 sse4_2 popcnt aes xsave avx f16c rdrand hypervisor lahf_lm"
assert_rejects "Ivy Bridge without AVX2/BMI1/BMI2 does not satisfy x86-64-v3"

# Haswell and newer: full x86-64-v3 baseline.
write_cpuinfo_flags "fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ss ht syscall nx rdtscp lm constant_tsc rep_good nopl xtopology nonstop_tsc pni pclmulqdq ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c rdrand lahf_lm abm avx2 bmi1 bmi2"
assert_detects "Haswell with the full x86-64-v3 baseline satisfies it"

write_cpuinfo_flags "fpu vme de pse tsc msr avx avx2"
assert_rejects "AVX2 alone without FMA/BMI1/BMI2/F16C/MOVBE does not satisfy x86-64-v3"

# LZCNT is part of the x86-64-v3 baseline and Voxtype's binaries are built with
# target-cpu=haswell, so a CPU (or a CPUID mask) carrying every other flag but
# not this one can still take a SIGILL.
write_cpuinfo_flags "fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ss ht syscall nx rdtscp lm constant_tsc rep_good nopl xtopology nonstop_tsc pni pclmulqdq ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c rdrand lahf_lm avx2 bmi1 bmi2"
assert_rejects "the full baseline without LZCNT (abm) does not satisfy x86-64-v3"

: >"$tmp_dir/cpuinfo"
assert_rejects "empty cpuinfo does not satisfy x86-64-v3"

write_cpuinfo_flags "fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ss ht syscall nx rdtscp lm constant_tsc rep_good nopl xtopology nonstop_tsc pni pclmulqdq ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c rdrand lahf_lm abm avx2 bmi1 bmi2"
OMARCHY_UNAME_M="aarch64" assert_rejects "aarch64 is rejected even with x86-64-v3 flags present"
