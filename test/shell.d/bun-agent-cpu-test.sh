#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
cpuinfo_dir="$test_tmp/cpuinfo"
mise_log="$test_tmp/mise"
skip_log="$test_tmp/skip"
mkdir -p "$mock_bin" "$test_home" "$cpuinfo_dir"

cat >"$mock_bin/omarchy-mise-install" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_MISE_LOG"
SH
chmod +x "$mock_bin/omarchy-mise-install"

cat >"$cpuinfo_dir/core2duo" <<'EOF'
processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 23
model name	: Intel(R) Core(TM)2 Duo CPU     E7600  @ 3.06GHz
stepping	: 10
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx lm constant_tsc art arch_perfmon pebs bts rep_good nopl aperfmperf pni dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm sse4_1 lahf_lm tpr_shadow vnmi flexpriority
EOF

cat >"$cpuinfo_dir/haswell" <<'EOF'
processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 60
model name	: Intel(R) Core(TM) i5-4590 CPU @ 3.30GHz
stepping	: 3
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 sdbg fma cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm abm cpuid_fault epb pti ssbd ibrs ibpb stibp tpr_shadow vnmi flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid xsaveopt dtherm ida arat pln pts md_clear flush_l1d
EOF

cat >"$cpuinfo_dir/aarch64" <<'EOF'
processor	: 0
BogoMIPS	: 48.00
Features	: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop
CPU implementer	: 0x41
CPU architecture: 8
CPU variant	: 0x4
CPU part	: 0xd0b
CPU revision	: 1
EOF

cat >"$cpuinfo_dir/sse4_2-only" <<'EOF'
processor	: 0
vendor_id	: GenuineIntel
flags		: fpu sse sse2 sse3 ssse3 sse4_1 sse4_2
EOF

export PATH="$mock_bin:$ROOT/bin:$PATH"
export HOME="$test_home"
export OMARCHY_PATH="$ROOT"
export OMARCHY_TEST_MISE_LOG="$mise_log"

hw_cpu() {
  "$ROOT/bin/omarchy-hw-cpu-sse4_2"
}

assert_hw() {
  local description=$1 expected=$2
  local actual=no

  hw_cpu && actual=yes
  [[ $actual == "$expected" ]] || fail "$description" "expected $expected, got $actual"
  pass "$description"
}

OMARCHY_CPUINFO="$cpuinfo_dir/core2duo" assert_hw "x86 without sse4_2 is not Bun linux-x64 compatible" no
OMARCHY_CPUINFO="$cpuinfo_dir/sse4_2-only" assert_hw "x86 with sse4_2 but no popcnt is not Bun linux-x64 compatible" no
OMARCHY_CPUINFO="$cpuinfo_dir/haswell" assert_hw "x86 with sse4_2 and popcnt is Bun linux-x64 compatible" yes
OMARCHY_CPUINFO="$cpuinfo_dir/aarch64" assert_hw "aarch64 cpuinfo is Bun linux-x64 compatible" yes
OMARCHY_ARCH=aarch64 OMARCHY_CPUINFO="$cpuinfo_dir/core2duo" assert_hw "OMARCHY_ARCH=aarch64 still installs even with x86 cpuinfo" yes

run_mise() {
  : >"$mise_log"
  OMARCHY_CPUINFO=$1 source "$ROOT/install/user/mise.sh" >"$skip_log" 2>&1
}

assert_skipped() {
  if grep -qx 'claude' "$mise_log"; then
    fail "$1 still installs claude"
  fi
  if grep -qx 'pi' "$mise_log"; then
    fail "$1 still installs pi"
  fi
  grep -q 'Skipping claude:' "$skip_log" || fail "$1 does not explain skipping claude"
  grep -q 'Skipping pi:' "$skip_log" || fail "$1 does not explain skipping pi"
  grep -qx 'codex' "$mise_log" || fail "$1 still installs other mise tools"
}

assert_installed() {
  grep -qx 'claude' "$mise_log" || fail "$1 does not install claude"
  grep -qx 'pi' "$mise_log" || fail "$1 does not install pi"
  if grep -q 'Skipping' "$skip_log"; then
    fail "$1 skips bun agents on a compatible CPU"
  fi
}

run_mise "$cpuinfo_dir/core2duo"
assert_skipped "missing sse4_2"
pass "user setup skips claude and pi when SSE4.2 is missing"

run_mise "$cpuinfo_dir/haswell"
assert_installed "sse4_2+popcnt"
pass "user setup installs claude and pi when SSE4.2 and POPCNT are present"

run_mise "$cpuinfo_dir/aarch64"
assert_installed "aarch64"
pass "user setup installs claude and pi on aarch64"

cat >"$mock_bin/mise" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_MISE_LOG"
if [[ $1 == "where" ]]; then
  [[ ${OMARCHY_TEST_AGENT_INSTALLED:-false} == "true" ]]
  exit
fi
exit 0
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_TERMINAL_LOG"
SH

cat >"$mock_bin/omarchy-agent" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$mock_bin"/*

terminal_log="$test_tmp/terminal"
export OMARCHY_TEST_TERMINAL_LOG="$terminal_log"

: >"$mise_log"
: >"$terminal_log"
mkdir -p "$test_home/.config/omarchy/defaults"
if OMARCHY_CPUINFO="$cpuinfo_dir/core2duo" omarchy-default-agent claude >"$skip_log" 2>&1; then
  fail "default agent installs claude on a CPU without SSE4.2"
fi
grep -q 'SSE4.2' "$skip_log" || fail "default agent explains why claude cannot be installed"
[[ ! -s $mise_log ]] || fail "default agent does not invoke mise for an incompatible claude"
[[ ! -s $terminal_log ]] || fail "default agent does not open an install terminal for incompatible claude"
[[ ! -f $test_home/.config/omarchy/defaults/agent ]] || fail "default agent does not record an incompatible claude"
pass "default agent refuses claude on a CPU without SSE4.2"

: >"$mise_log"
: >"$skip_log"
if OMARCHY_CPUINFO="$cpuinfo_dir/core2duo" omarchy-default-agent pi >"$skip_log" 2>&1; then
  fail "default agent installs pi on a CPU without SSE4.2"
fi
grep -q 'SSE4.2' "$skip_log" || fail "default agent explains why pi cannot be installed"
[[ ! -s $mise_log ]] || fail "default agent does not invoke mise for an incompatible pi"
pass "default agent refuses pi on a CPU without SSE4.2"

: >"$mise_log"
OMARCHY_CPUINFO="$cpuinfo_dir/haswell" OMARCHY_TEST_AGENT_INSTALLED=true omarchy-default-agent claude >/dev/null
grep -q 'use -g claude' "$mise_log" || fail "default agent still installs claude when the CPU can run Bun"
[[ $(<"$test_home/.config/omarchy/defaults/agent") == claude ]] || fail "default agent records claude on a compatible CPU"
pass "default agent still installs claude when SSE4.2 and POPCNT are present"
