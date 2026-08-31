#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

cat >"$stub_bin/docker" <<'STUB'
#!/bin/bash

printf 'docker' >>"$DOCKER_CALL_LOG"
printf '\t%s' "$@" >>"$DOCKER_CALL_LOG"
printf '\n' >>"$DOCKER_CALL_LOG"

if [[ ${1:-} == container && ${2:-} == ls ]]; then
  (( ${DOCKER_LIST_FAIL:-0} == 0 )) || exit 1
  shopt -s nullglob
  for state in "$DOCKER_STATE_DIR"/container-*; do
    printf '%s\n' "${state##*/container-}"
  done
  exit 0
fi

[[ ${1:-} == run ]] || exit 2
shift
name=""
env_file=""
mount_spec=""
args=("$@")
for ((index = 0; index < ${#args[@]}; index++)); do
  case ${args[index]} in
    --name) name=${args[index + 1]} ;;
    --env-file) env_file=${args[index + 1]} ;;
    --mount) mount_spec=${args[index + 1]} ;;
  esac
done
[[ -n $name ]] || exit 3
printf '%s\0' "${args[@]}" >"$DOCKER_CAPTURE_DIR/$name.argv"
if [[ -n $env_file ]]; then
  cp -- "$env_file" "$DOCKER_CAPTURE_DIR/$name.credentials"
elif [[ -n $mount_spec ]]; then
  source_path=${mount_spec#*src=}
  source_path=${source_path%%,dst=*}
  cp -- "$source_path" "$DOCKER_CAPTURE_DIR/$name.credentials"
fi
printf '%s\n' "$name" >>"$DOCKER_RUN_LOG"
[[ -z ${DOCKER_RUN_DELAY:-} ]] || sleep "$DOCKER_RUN_DELAY"
(( ${DOCKER_RUN_FAIL:-0} == 0 )) || exit 42
touch "$DOCKER_STATE_DIR/container-$name"
printf 'fake-container-id\n'
STUB

chmod +x "$stub_bin"/*
export PATH="$stub_bin:$PATH"

database_library="$test_dir/omarchy-install-docker-dbs.library"
sed '1,/^# OMARCHY_DOCKER_DBS_IMPLEMENTATION$/d' \
  "$ROOT/bin/omarchy-install-docker-dbs" >"$database_library"
source "$database_library"

# Production deliberately bypasses PATH for the privilege boundary. Replace
# only that function in this isolated test so the Docker protocol still runs
# through the deterministic stub below.
run_docker() {
  docker "$@"
}

export DOCKER_STATE_DIR="$test_dir/docker-state"
export DOCKER_CAPTURE_DIR="$test_dir/docker-captures"
export DOCKER_CALL_LOG="$test_dir/docker.calls"
export DOCKER_RUN_LOG="$test_dir/docker.runs"
mkdir -p "$DOCKER_STATE_DIR" "$DOCKER_CAPTURE_DIR"
: >"$DOCKER_CALL_LOG"
: >"$DOCKER_RUN_LOG"

# Use a disposable caller-owned home while still exercising all of the real
# path validation below it. Identity derivation itself is checked separately.
TEST_ACCOUNT_HOME="$test_dir/home"
mkdir -m 0700 "$TEST_ACCOUNT_HOME"
resolve_caller_identity() {
  CALLER_UID=$(/usr/bin/id -u)
  CALLER_NAME=$(/usr/bin/id -un)
  ACCOUNT_HOME=$TEST_ACCOUNT_HOME
  CREDENTIAL_DIR="$ACCOUNT_HOME/.config/omarchy/docker-dbs"
}

actual_home=$(/usr/bin/getent passwd "$(/usr/bin/id -u)" | /usr/bin/cut -d: -f6)
if (( $(/usr/bin/id -u) > 0 )); then
  original_home=${HOME:-}
  resolved_dir=$(HOME=/tmp/attacker-controlled-home bash -c '
    source "$1"
    resolve_caller_identity
    printf "%s" "$CREDENTIAL_DIR"
  ' _ "$database_library")
  HOME=$original_home
  [[ $resolved_dir == "$actual_home/.config/omarchy/docker-dbs" ]] ||
    fail "database installer ignores an untrusted HOME for credential placement" "$resolved_dir"
fi
pass "database credential location is derived from the exact numeric caller identity"

# Exercise the production home validator directly, independently of the
# disposable-home identity override used by the rest of this test. A home that
# another local UID can modify cannot safely anchor a private credential path.
mode_test_home="$test_dir/home-mode-validation"
mkdir -m 0700 "$mode_test_home"
account_home_is_private "$mode_test_home" "$(/usr/bin/id -u)" ||
  fail "caller-owned private home is rejected"
chmod 0777 "$mode_test_home"
if account_home_is_private "$mode_test_home" "$(/usr/bin/id -u)"; then
  fail "group/world-writable caller home is accepted"
fi
chmod 0700 "$mode_test_home"
pass "real caller-home validation rejects group/world-writable homes"

declare -A expected_container=(
  [MySQL]=mysql8
  [PostgreSQL]=postgres18
  [Redis]=redis
  [MongoDB]=mongodb
  [MariaDB]=mariadb11
  [MSSQL]=mssql
)
declare -A expected_port=(
  [MySQL]=127.0.0.1:3306:3306
  [PostgreSQL]=127.0.0.1:5432:5432
  [Redis]=127.0.0.1:6379:6379
  [MongoDB]=127.0.0.1:27017:27017
  [MariaDB]=127.0.0.1:3306:3306
  [MSSQL]=127.0.0.1:1433:1433
)
declare -A passwords=()

file_contains_secret() {
  local file="$1" secret="$2" field
  [[ -f $file ]] || return 1
  if [[ $file == *.argv ]]; then
    while IFS= read -r -d '' field; do
      [[ $field != *"$secret"* ]] || return 0
    done <"$file"
  else
    while IFS= read -r field || [[ -n $field ]]; do
      [[ $field != *"$secret"* ]] || return 0
    done <"$file"
  fi
  return 1
}

for db in "${DATABASE_OPTIONS[@]}"; do
  container=${expected_container[$db]}
  output="$test_dir/$container.output"
  (umask 000; main "$db") >"$output" 2>&1 || fail "$db secure database install succeeds with Docker stub" "$(cat "$output")"
  resolve_caller_identity
  credential=$(credential_path_for "$db")
  [[ -f $credential && ! -L $credential ]] || fail "$db writes a regular credential file"
  [[ $(stat -c '%a' "$credential") == 600 ]] || fail "$db credential file is mode 0600"
  [[ $(stat -c '%u' "$credential") == "$CALLER_UID" ]] || fail "$db credential belongs to the caller"

  if [[ $db == Redis ]]; then
    password=$(sed -n 's/^requirepass //p' "$credential")
    grep -qxF 'protected-mode yes' "$credential" || fail "Redis keeps protected mode enabled"
    grep -qxF 'bind 0.0.0.0' "$credential" || fail "Redis container accepts its loopback-published connection"
  else
    password=$(sed -n 's/^[A-Z_]*PASSWORD=//p' "$credential")
  fi
  [[ $password =~ ^Om4![0-9a-f]{48}$ ]] || fail "$db password has 192 random bits and a compatible complexity prefix"
  [[ $password =~ [A-Z] && $password =~ [a-z] && $password =~ [0-9] && $password =~ [^A-Za-z0-9] ]] ||
    fail "$db password satisfies SQL Server complexity policy"
  passwords[$db]=$password

  argv_file="$DOCKER_CAPTURE_DIR/$container.argv"
  mapfile -d '' -t argv <"$argv_file"
  printf '%s\n' "${argv[@]}" | grep -qxF "${expected_port[$db]}" || fail "$db remains bound to host loopback"
  printf '%s\n' "${argv[@]}" | grep -qxF "$container" || fail "$db uses its stable named container"
  ! file_contains_secret "$argv_file" "$password" || fail "$db exposes its password in Docker argv"
  ! file_contains_secret "$output" "$password" || fail "$db exposes its password in command output"
  ! file_contains_secret "$DOCKER_CALL_LOG" "$password" || fail "$db exposes its password in the Docker call log"
  printf '%s\n' "${argv[@]}" | grep -qxF -- '--env-file' || fail "$db passes credentials through --env-file"
  printf '%s\n' "${argv[@]}" | grep -qxF -- '/dev/stdin' || fail "$db does not inherit credentials on standard input"
  ! printf '%s\n' "${argv[@]}" | grep -qxF -- '-e' || fail "$db uses inline environment arguments"
  ! printf '%s\n' "${argv[@]}" | grep -qxF -- '--mount' || fail "$db gives root Docker a caller-owned bind path"
  ! printf '%s\n' "${argv[@]}" | grep -qxF -- "$credential" || fail "$db exposes its credential pathname to Docker"
  if [[ $db == Redis ]]; then
    grep -qxF "REDIS_PASSWORD=$password" "$DOCKER_CAPTURE_DIR/$container.credentials" ||
      fail "Redis does not inherit its exact password through the opaque descriptor"
    printf '%s\n' "${argv[@]}" | grep -Fq -- 'exec redis-server /tmp/omarchy-redis.conf' ||
      fail "Redis does not build and use its fixed in-container config"
  else
    cmp -s "$credential" "$DOCKER_CAPTURE_DIR/$container.credentials" ||
      fail "$db does not pass the validated credential bytes unchanged"
  fi
done

[[ $(stat -c '%a' "$CREDENTIAL_DIR") == 700 ]] || fail "database credential directory is mode 0700 under permissive umask"
unique_count=$(printf '%s\n' "${passwords[@]}" | sort -u | wc -l)
((unique_count == ${#DATABASE_OPTIONS[@]})) || fail "database services do not share generated passwords"
! rg -q 'POSTGRES_HOST_AUTH_METHOD=trust|ALLOW_EMPTY|admin123|@dmin123|requirepass[[:space:]]*$' \
  "$ROOT/bin/omarchy-install-docker-dbs" || fail "database installer retains a legacy public or empty authentication mode"
! rg -q '/usr/bin/(printf|echo).*\$(password|contents)' "$ROOT/bin/omarchy-install-docker-dbs" ||
  fail "database installer passes a generated secret to an external output helper"
pass "all six database invocations use independent private credentials and loopback-only ports"

# Existing credential files are accepted only when every line exactly matches
# that engine's generated schema. A valid-looking password must not mask a
# trust/empty-password directive, duplicate field, or other injected setting.
poison_password='Om4!0123456789abcdef0123456789abcdef0123456789abcdef'
assert_poisoned_credentials_rejected() {
  local db="$1" label="$2" contents="$3" credential output before
  TEST_ACCOUNT_HOME="$test_dir/poison-$label"
  mkdir -m 0700 "$TEST_ACCOUNT_HOME"
  rm -f "$DOCKER_STATE_DIR"/container-*
  : >"$DOCKER_CALL_LOG"
  : >"$DOCKER_RUN_LOG"
  resolve_caller_identity
  prepare_credential_dir
  credential=$(credential_path_for "$db")
  printf '%s' "$contents" >"$credential"
  chmod 0600 "$credential"
  before=$(sha256sum "$credential")
  output="$test_dir/poison-$label.output"

  if main "$db" >"$output" 2>&1; then
    fail "$label poisoned existing credentials are accepted"
  fi
  [[ ! -s $DOCKER_CALL_LOG ]] || fail "$label poisoned credentials invoke Docker"
  [[ ! -s $DOCKER_RUN_LOG ]] || fail "$label poisoned credentials reach docker run"
  [[ $(sha256sum "$credential") == "$before" ]] || fail "$label rejected credential file is modified"
  ! file_contains_secret "$output" "$poison_password" || fail "$label rejected credential is printed"
}

assert_poisoned_credentials_rejected PostgreSQL postgres-trust \
  $'POSTGRES_USER=postgres\nPOSTGRES_PASSWORD='"$poison_password"$'\nPOSTGRES_HOST_AUTH_METHOD=trust\n'
assert_poisoned_credentials_rejected MySQL mysql-empty \
  'MYSQL_ROOT_PASSWORD='"$poison_password"$'\nMYSQL_ALLOW_EMPTY_PASSWORD=true\n'
assert_poisoned_credentials_rejected MariaDB mariadb-extra \
  'MARIADB_ROOT_PASSWORD='"$poison_password"$'\nUNEXPECTED_SETTING=yes\n'
assert_poisoned_credentials_rejected MongoDB mongodb-duplicate \
  $'MONGO_INITDB_ROOT_USERNAME=omarchy_admin\nMONGO_INITDB_ROOT_PASSWORD='"$poison_password"$'\nMONGO_INITDB_ROOT_PASSWORD='"$poison_password"$'\n'
pass "poisoned, duplicate, and extra Docker env-file fields fail closed without disclosure or mutation"

assert_poisoned_credentials_rejected Redis redis-protected-mode-override \
  $'protected-mode yes\nbind 0.0.0.0\nrequirepass '"$poison_password"$'\nprotected-mode no\n'
assert_poisoned_credentials_rejected Redis redis-duplicate-requirepass \
  $'protected-mode yes\nbind 0.0.0.0\nrequirepass '"$poison_password"$'\nrequirepass '"$poison_password"$'\n'
pass "Redis config validation rejects later overrides and duplicate authentication directives"

# An existing named container wins before credential generation. The installer
# reports the legacy risk and leaves the container/data untouched.
TEST_ACCOUNT_HOME="$test_dir/existing-home"
mkdir -m 0700 "$TEST_ACCOUNT_HOME"
rm -f "$DOCKER_STATE_DIR"/container-*
touch "$DOCKER_STATE_DIR/container-mysql8"
: >"$DOCKER_RUN_LOG"
if main MySQL >"$test_dir/existing.output" 2>&1; then
  fail "existing database container is silently reused or replaced"
fi
[[ ! -s $DOCKER_RUN_LOG ]] || fail "existing container triggers docker run"
[[ ! -e $TEST_ACCOUNT_HOME/.config/omarchy/docker-dbs/mysql.env ]] || fail "existing container generates misleading credentials"
grep -q 'may retain legacy' "$test_dir/existing.output" || fail "existing container warning omits legacy authentication risk"
grep -q 'Back up its data' "$test_dir/existing.output" || fail "existing container warning lacks safe remediation guidance"
pass "existing containers fail closed without modifying data or generating credentials"

# Docker discovery failure is distinct from absence and also precedes secrets.
TEST_ACCOUNT_HOME="$test_dir/list-failure-home"
mkdir -m 0700 "$TEST_ACCOUNT_HOME"
rm -f "$DOCKER_STATE_DIR"/container-*
if DOCKER_LIST_FAIL=1 main PostgreSQL >/dev/null 2>&1; then
  fail "Docker discovery failure is treated as container absence"
fi
[[ ! -e $TEST_ACCOUNT_HOME/.config/omarchy/docker-dbs/postgresql.env ]] ||
  fail "Docker discovery failure generates credentials"
pass "unavailable Docker state fails before credential generation"

# If docker run fails after the atomic credential publication, keep that exact
# credential: Docker may have created the container before returning failure,
# and a retry must never invent a mismatched password.
TEST_ACCOUNT_HOME="$test_dir/retry-home"
mkdir -m 0700 "$TEST_ACCOUNT_HOME"
rm -f "$DOCKER_STATE_DIR"/container-*
if DOCKER_RUN_FAIL=1 main MariaDB >"$test_dir/retry-failure.output" 2>&1; then
  fail "Docker run failure reports success"
fi
retry_credential="$TEST_ACCOUNT_HOME/.config/omarchy/docker-dbs/mariadb.env"
[[ -f $retry_credential ]] || fail "failed Docker run loses its matching private credential"
retry_before=$(sha256sum "$retry_credential")
main MariaDB >/dev/null
[[ $(sha256sum "$retry_credential") == "$retry_before" ]] || fail "retry rotates a persisted credential"
! find "${retry_credential%/*}" -name '.credential.*' -print -quit | grep -q . ||
  fail "database credential writer leaves a partial temporary file"
pass "Docker failure and retry preserve one consistent atomic credential"

# Reject planted symlinks rather than following them or replacing an ambiguous
# existing credential. The target content must remain untouched.
TEST_ACCOUNT_HOME="$test_dir/file-symlink-home"
mkdir -m 0700 "$TEST_ACCOUNT_HOME"
rm -f "$DOCKER_STATE_DIR"/container-*
resolve_caller_identity
prepare_credential_dir
victim="$test_dir/symlink-victim"
printf 'do-not-change\n' >"$victim"
ln -s "$victim" "$CREDENTIAL_DIR/mysql.env"
if main MySQL >/dev/null 2>&1; then fail "planted credential symlink is accepted"; fi
[[ $(<"$victim") == do-not-change ]] || fail "credential symlink target was modified"

TEST_ACCOUNT_HOME="$test_dir/dir-symlink-home"
mkdir -m 0700 -p "$TEST_ACCOUNT_HOME/.config/omarchy" "$test_dir/outside-creds"
ln -s "$test_dir/outside-creds" "$TEST_ACCOUNT_HOME/.config/omarchy/docker-dbs"
if main Redis >/dev/null 2>&1; then fail "symlinked credential directory is accepted"; fi
[[ -z $(find "$test_dir/outside-creds" -mindepth 1 -print -quit) ]] || fail "symlinked credential directory receives files"
pass "credential path and directory symlink attacks are rejected without target mutation"

# Two concurrent installers serialize on the private directory inode. The
# winner creates the named container; the waiter then observes it and refuses,
# so there is exactly one run and one credential.
TEST_ACCOUNT_HOME="$test_dir/concurrent-home"
mkdir -m 0700 "$TEST_ACCOUNT_HOME"
rm -f "$DOCKER_STATE_DIR"/container-*
: >"$DOCKER_RUN_LOG"
DOCKER_RUN_DELAY=0.2 main MongoDB >"$test_dir/concurrent-a.output" 2>&1 &
first_pid=$!
DOCKER_RUN_DELAY=0.2 main MongoDB >"$test_dir/concurrent-b.output" 2>&1 &
second_pid=$!
first_status=0
second_status=0
wait "$first_pid" || first_status=$?
wait "$second_pid" || second_status=$?
(( (first_status == 0 && second_status != 0) || (first_status != 0 && second_status == 0) )) ||
  fail "concurrent database install does not produce exactly one winner"
[[ $(grep -c '^mongodb$' "$DOCKER_RUN_LOG") == 1 ]] || fail "concurrent database install invokes docker run more than once"
[[ -f $TEST_ACCOUNT_HOME/.config/omarchy/docker-dbs/mongodb.env ]] || fail "concurrent winner does not persist credentials"
pass "concurrent database installs serialize to one container and credential"

# Strictly one allowlisted menu/CLI choice is accepted; whitespace and multiple
# args cannot become a partially installed list.
TEST_ACCOUNT_HOME="$test_dir/invalid-home"
mkdir -m 0700 "$TEST_ACCOUNT_HOME"
: >"$DOCKER_CALL_LOG"
if main 'MySQL PostgreSQL' >/dev/null 2>&1; then fail "whitespace-split database choice is accepted"; fi
if main MySQL Redis >/dev/null 2>&1; then fail "multiple database choices are accepted"; fi
if main Unknown >/dev/null 2>&1; then fail "unknown database choice is accepted"; fi
[[ ! -s $DOCKER_CALL_LOG ]] || fail "invalid database choice reaches Docker"
[[ ! -e $TEST_ACCOUNT_HOME/.config/omarchy/docker-dbs ]] || fail "invalid database choice creates credential state"
pass "database choice dispatch is single-value and allowlisted"

# The executable entry must suppress BASH_ENV before it can spawn a waiter for
# the later Docker authorization. A decoy -p after the script path is not an
# interpreter option and must not satisfy the gate.
startup_bash_env="$test_dir/docker-startup-bash-env"
startup_marker="$test_dir/docker-startup-bash-env-ran"
cat >"$startup_bash_env" <<'STUB'
: >"$TEST_DOCKER_BASH_ENV_RAN"
unset BASH_ENV
set -o privileged
set -- MySQL
STUB
if BASH_ENV="$startup_bash_env" TEST_DOCKER_BASH_ENV_RAN="$startup_marker" \
  /usr/bin/bash "$ROOT/bin/omarchy-install-docker-dbs" -p >/dev/null 2>&1; then
  fail "database installer accepted a decoy post-script -p"
fi
[[ -e $startup_marker ]] || fail "database startup-injection precondition was not exercised"
pass "database installer rejects startup injection before opening sudo"

# Threat-model regression: where subordinate-id user namespaces are available,
# prove a listener owned by uid 1000 on 127.0.0.1 is reachable by uid 1001 in
# the same network namespace. Authentication, not loopback, is the UID boundary.
cross_uid_probe="$test_dir/cross-uid-probe.sh"
cat >"$cross_uid_probe" <<'PROBE'
#!/bin/bash
set -euo pipefail
output=$(mktemp)
setpriv --reuid=1000 --regid=1000 --clear-groups python -u -c '
import os, socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(1)
print(s.getsockname()[1], flush=True)
c, _ = s.accept()
c.sendall(str(os.getuid()).encode())
c.close()
' >"$output" &
server=$!
for _ in {1..200}; do
  [[ -s $output ]] && break
  kill -0 "$server" 2>/dev/null || exit 2
  sleep 0.01
done
read -r port <"$output"
reply=$(setpriv --reuid=1001 --regid=1001 --clear-groups python -c '
import socket, sys
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])))
print(s.recv(64).decode())
' "$port")
wait "$server"
[[ $reply == 1000 ]]
PROBE
chmod +x "$cross_uid_probe"
if unshare --user --map-auto --map-root-user true 2>/dev/null &&
  unshare --user --map-auto --map-root-user "$cross_uid_probe" 2>/dev/null; then
  pass "distinct local UIDs share loopback, so database authentication remains mandatory"
else
  pass "subordinate-id namespace unavailable; skipping cross-UID loopback runtime probe"
fi
