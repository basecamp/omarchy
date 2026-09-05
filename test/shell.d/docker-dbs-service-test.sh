#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

grep -F 'sudo systemctl enable --now docker.service' "$ROOT/bin/omarchy-install-docker-dbs" >/dev/null ||
  fail "Docker DB installer does not enable docker.service"
pass "Docker DB installer enables docker.service when a database is chosen"

migration="$ROOT/migrations/1787864101.sh"
[[ -f $migration ]] || fail "Docker DB docker.service migration is missing"
pass "Docker DB docker.service migration exists"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
SYSTEMCTL_LOG="$tmp_dir/systemctl-log"
DOCKER_LOG="$tmp_dir/docker-log"

cat >"$tmp_dir/bin/systemctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
if [[ $1 == "is-enabled" ]]; then
  exit 1
fi
exit 0
SH

cat >"$tmp_dir/bin/docker" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$DOCKER_LOG"
if [[ $1 == "info" ]]; then
  exit 0
fi
if [[ $1 == "inspect" && $2 == "--type" && $3 == "container" && $4 == "postgres18" ]]; then
  exit 0
fi
exit 1
SH

cat >"$tmp_dir/bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$tmp_dir/bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$tmp_dir/bin/systemctl" "$tmp_dir/bin/docker" "$tmp_dir/bin/sudo" "$tmp_dir/bin/omarchy-cmd-present"

PATH="$tmp_dir/bin:$PATH" \
SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
DOCKER_LOG="$DOCKER_LOG" \
  bash -euo pipefail "$migration" >/dev/null

grep -Fqx -- "enable --now docker.service" "$SYSTEMCTL_LOG" ||
  fail "migration does not enable docker.service when a Docker DB container exists"
grep -Fqx -- "inspect --type container postgres18" "$DOCKER_LOG" ||
  fail "migration does not inspect containers by type"
pass "migration enables docker.service when a Docker DB container exists"

: >"$SYSTEMCTL_LOG"
: >"$DOCKER_LOG"

cat >"$tmp_dir/bin/docker" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$DOCKER_LOG"
if [[ $1 == "info" ]]; then
  exit 0
fi
exit 1
SH
chmod +x "$tmp_dir/bin/docker"

PATH="$tmp_dir/bin:$PATH" \
SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
DOCKER_LOG="$DOCKER_LOG" \
  bash -euo pipefail "$migration" >/dev/null

if grep -Fqx -- "enable --now docker.service" "$SYSTEMCTL_LOG"; then
  fail "migration enables docker.service when no Docker DB container exists"
fi
pass "migration leaves docker.service alone when no Docker DB container exists"

: >"$SYSTEMCTL_LOG"
: >"$DOCKER_LOG"

cat >"$tmp_dir/bin/docker" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$DOCKER_LOG"
if [[ $1 == "info" ]]; then
  exit 1
fi
exit 0
SH
chmod +x "$tmp_dir/bin/docker"

if PATH="$tmp_dir/bin:$PATH" \
SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
DOCKER_LOG="$DOCKER_LOG" \
  bash -euo pipefail "$migration" >/dev/null 2>&1; then
  fail "migration treats docker info failure as success"
fi
if grep -Fqx -- "enable --now docker.service" "$SYSTEMCTL_LOG"; then
  fail "migration enables docker.service after docker info failure"
fi
pass "migration stays pending when docker info fails"
