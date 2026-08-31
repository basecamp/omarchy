#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir "$stub"
test_uid=$(id -u)

cat >"$stub/id" <<'SH'
#!/bin/bash
[[ ${1:-} == -u ]] || exit 2
printf '%s\n' "$TEST_UID"
SH
cat >"$stub/getent" <<'SH'
#!/bin/bash
[[ ${1:-} == passwd && ${2:-} == "$TEST_UID" ]] || exit 2
printf 'audit:x:%s:100:Audit Test:%s:/bin/bash\n' "$TEST_UID" "$HOME"
SH

cat >"$stub/omarchy-pkg-add" <<'SH'
#!/bin/bash
echo "package $*" >>"$EVENTS"
[[ ${PACKAGE_FAIL:-0} != 1 ]]
SH
cat >"$stub/omarchy-cmd-missing" <<'SH'
#!/bin/bash
[[ ${UFW_MISSING:-0} == 1 ]]
SH
cat >"$stub/curl" <<'SH'
#!/bin/bash
echo github-fetch >>"$EVENTS"
[[ ${GH_FAIL:-0} != 1 ]] || exit 1
printf %s "${GH_KEYS:-}"
SH
cat >"$stub/gum" <<'SH'
#!/bin/bash
case $1 in choose) printf '%s\n' "${GUM_CHOICE:-}" ;; input) [[ ${GUM_CANCEL:-0} != 1 ]] && printf '%s\n' "${GUM_INPUT:-}" ;; esac
SH
cat >"$stub/mv" <<'SH'
#!/bin/bash
[[ ${*: -1} != */authorized_keys ]] || echo authorized-key >>"$EVENTS"
exec /usr/bin/mv "$@"
SH

cat >"$stub/sudo" <<'SH'
#!/bin/bash
set -euo pipefail
echo "sudo $*" >>"$EVENTS"
[[ ${1:-} != -k ]] || exit 0
map() { [[ $1 == /etc/* ]] && printf '%s%s' "$FAKE_ROOT" "$1" || printf %s "$1"; }
case $1 in
systemctl)
  a=$2
  case $a in
  is-active) [[ -e $STATE/active ]] ;; is-enabled) [[ -e $STATE/enabled ]] ;;
  start) [[ ${START_PARTIAL:-0} != 1 ]] || { touch "$STATE/active"; exit 1; }; [[ ${START_FAIL:-0} != 1 ]] || exit 1; touch "$STATE/active" ;;
  enable) [[ ${ENABLE_PARTIAL:-0} != 1 ]] || { touch "$STATE/enabled"; exit 1; }; [[ ${ENABLE_FAIL:-0} != 1 ]] || exit 1; touch "$STATE/enabled" ;;
  stop) [[ ${STOP_FAIL:-0} != 1 ]] || exit 1; rm -f "$STATE/active" ;;
  disable) [[ ${DISABLE_FAIL:-0} != 1 ]] || exit 1; rm -f "$STATE/enabled" ;;
  reload) n=0; [[ ! -e $STATE/reloads ]] || read -r n <"$STATE/reloads"; n=$((n+1)); echo "$n" >"$STATE/reloads"; [[ ${RELOAD_ALWAYS_FAIL:-0} != 1 && (${RELOAD_ONCE:-0} != 1 || $n != 1) ]] ;;
  esac ;;
ufw)
  shift
  if [[ $1 == show ]]; then [[ -e $STATE/rule && ${VERIFY_MISS:-0} != 1 ]] && echo "ufw limit 22/tcp comment 'omarchy-sshd'"
  elif [[ $1 == limit ]]; then [[ ${LIMIT_PARTIAL:-0} != 1 ]] || { touch "$STATE/rule"; exit 1; }; [[ ${LIMIT_FAIL:-0} != 1 ]] || exit 1; touch "$STATE/rule"
  elif [[ $1 == --force ]]; then [[ ${DELETE_FAIL:-0} != 1 ]] || exit 1; rm -f "$STATE/rule"
  elif [[ $1 == reload ]]; then n=0; [[ ! -e $STATE/ufw-reloads ]] || read -r n <"$STATE/ufw-reloads"; n=$((n+1)); echo "$n" >"$STATE/ufw-reloads"; [[ ${UFW_RELOAD_ALWAYS_FAIL:-0} != 1 && (${UFW_RELOAD_ONCE:-0} != 1 || $n != 1) ]]
  fi ;;
test) p=$(map "$3"); case $2 in -e) [[ -e $p ]] ;; -L) [[ -L $p ]] ;; -f) [[ -f $p ]] ;; esac ;;
mktemp) p=$(map "$2"); mkdir -p "${p%/*}"; /usr/bin/mktemp "$p" ;;
cp) s=$(map "${*: -2:1}"); d=$(map "${*: -1}"); /usr/bin/cp -a "$s" "$d" ;;
install) s=$(map "${*: -2:1}"); d=$(map "${*: -1}"); mkdir -p "${d%/*}"; /usr/bin/install -m0644 "$s" "$d"; echo installed-hardening >>"$EVENTS" ;;
/usr/bin/awk) x=("$@"); x[-1]=$(map "${x[-1]}"); exec "${x[@]}" ;;
/usr/bin/find) x=("$@"); x[1]=$(map "${x[1]}"); exec "${x[@]}" ;;
ssh-keygen) echo host-keygen >>"$EVENTS"; [[ ${HOSTKEY_FAIL:-0} != 1 ]] || exit 1; touch "$FAKE_ROOT/etc/ssh/ssh_host_key" ;;
sshd)
  if [[ $2 == -t ]]; then echo sshd-t >>"$EVENTS"; [[ ${T_FAIL:-0} != 1 ]]
  else echo sshd-T >>"$EVENTS"; [[ ${DUMP_FAIL:-0} != 1 ]] || exit 1; if [[ " $* " == *' -C '* ]]; then echo "PasswordAuthentication ${MATCH_PASS_AUTH:-${PASS_AUTH:-no}}"; echo "KbdInteractiveAuthentication ${MATCH_KBD_AUTH:-${KBD_AUTH:-no}}"; echo "AuthenticationMethods ${MATCH_AUTH_METHODS:-${AUTH_METHODS:-publickey}}"; echo "PubkeyAuthentication ${MATCH_PUBKEY_AUTH:-${PUBKEY_AUTH:-yes}}"; echo "AuthorizedKeysFile ${MATCH_KEYS_SETTING:-${AUTHORIZED_KEYS_SETTING:-.ssh/authorized_keys}}"; else echo "PasswordAuthentication ${PASS_AUTH:-no}"; echo "KbdInteractiveAuthentication ${KBD_AUTH:-no}"; echo "AuthenticationMethods ${AUTH_METHODS:-publickey}"; echo "PubkeyAuthentication ${PUBKEY_AUTH:-yes}"; echo "AuthorizedKeysFile ${AUTHORIZED_KEYS_SETTING:-.ssh/authorized_keys}"; fi; fi ;;
mv) s=$(map "${*: -2:1}"); d=$(map "${*: -1}"); /usr/bin/mv -fT "$s" "$d" ;;
rm) [[ ${CONFIG_RM_FAIL:-0} != 1 ]] || exit 1; /usr/bin/rm -f "$(map "${*: -1}")" ;;
*) exec "$@" ;;
esac
SH
chmod +x "$stub"/*

mapped_sshd="$tmp/omarchy-setup-security-sshd"
sed \
  -e "s#/usr/bin/getent#$stub/getent#g" \
  -e "s#/usr/bin/id#$stub/id#g" \
  -e "s#/usr/bin/sudo#$stub/sudo#g" \
  -e "s#/usr/bin/omarchy-pkg-add#$stub/omarchy-pkg-add#g" \
  -e "s#/usr/bin/omarchy-cmd-missing#$stub/omarchy-cmd-missing#g" \
  -e "s#/usr/bin/curl#$stub/curl#g" \
  -e "s#/usr/bin/gum#$stub/gum#g" \
  -e "s#/usr/bin/mv#$stub/mv#g" \
  "$ROOT/bin/omarchy-setup-security-sshd" >"$mapped_sshd"
chmod 0755 "$mapped_sshd"

ssh-keygen -q -t ed25519 -N '' -f "$tmp/key"
key=$(<"$tmp/key.pub")

run() {
  local name=$1; shift; local d="$tmp/$name"
  mkdir -p "$d/home" "$d/root/etc/ssh/sshd_config.d" "$d/state"
  [[ -e $d/root/etc/ssh/sshd_config ]] || echo 'Include /etc/ssh/sshd_config.d/*.conf' >"$d/root/etc/ssh/sshd_config"
  : >"$d/events"
  [[ ${PRE_ACTIVE:-0} != 1 ]] || touch "$d/state/active"
  [[ ${PRE_ENABLED:-0} != 1 ]] || touch "$d/state/enabled"
  [[ ${PRE_RULE:-0} != 1 ]] || touch "$d/state/rule"
  env HOME="$d/home" PATH="$stub:/usr/bin" FAKE_ROOT="$d/root" STATE="$d/state" EVENTS="$d/events" USER=audit TEST_UID="$test_uid" \
    PACKAGE_FAIL="${PACKAGE_FAIL:-0}" GH_FAIL="${GH_FAIL:-0}" GH_KEYS="${GH_KEYS:-}" GUM_CHOICE="${GUM_CHOICE:-}" GUM_INPUT="${GUM_INPUT:-}" GUM_CANCEL="${GUM_CANCEL:-0}" \
    START_FAIL="${START_FAIL:-0}" START_PARTIAL="${START_PARTIAL:-0}" ENABLE_FAIL="${ENABLE_FAIL:-0}" ENABLE_PARTIAL="${ENABLE_PARTIAL:-0}" RELOAD_ONCE="${RELOAD_ONCE:-0}" RELOAD_ALWAYS_FAIL="${RELOAD_ALWAYS_FAIL:-0}" \
    HOSTKEY_FAIL="${HOSTKEY_FAIL:-0}" T_FAIL="${T_FAIL:-0}" DUMP_FAIL="${DUMP_FAIL:-0}" PASS_AUTH="${PASS_AUTH:-no}" KBD_AUTH="${KBD_AUTH:-no}" AUTH_METHODS="${AUTH_METHODS:-publickey}" PUBKEY_AUTH="${PUBKEY_AUTH:-yes}" AUTHORIZED_KEYS_SETTING="${AUTHORIZED_KEYS_SETTING:-.ssh/authorized_keys}" \
    MATCH_PASS_AUTH="${MATCH_PASS_AUTH:-}" MATCH_KBD_AUTH="${MATCH_KBD_AUTH:-}" MATCH_AUTH_METHODS="${MATCH_AUTH_METHODS:-}" MATCH_PUBKEY_AUTH="${MATCH_PUBKEY_AUTH:-}" MATCH_KEYS_SETTING="${MATCH_KEYS_SETTING:-}" \
    LIMIT_FAIL="${LIMIT_FAIL:-0}" LIMIT_PARTIAL="${LIMIT_PARTIAL:-0}" VERIFY_MISS="${VERIFY_MISS:-0}" UFW_RELOAD_ONCE="${UFW_RELOAD_ONCE:-0}" UFW_RELOAD_ALWAYS_FAIL="${UFW_RELOAD_ALWAYS_FAIL:-0}" DELETE_FAIL="${DELETE_FAIL:-0}" CONFIG_RM_FAIL="${CONFIG_RM_FAIL:-0}" \
    "$mapped_sshd" "$@"
}
no_publish() { ! grep -Eq 'sudo systemctl (start|enable|reload)|sudo ufw limit' "$tmp/$1/events" || fail "$1 published SSH" "$(cat "$tmp/$1/events")"; }
rolled_back() { [[ ! -e $tmp/$1/state/active && ! -e $tmp/$1/state/enabled && ! -e $tmp/$1/state/rule && ! -e $tmp/$1/home/.ssh/authorized_keys ]] || fail "$1 did not roll back"; }

for c in help unknown gh both; do case $c in help) a=(--help); want=0;; unknown) a=(--bad); want=2;; gh) a=(--gh-keys); want=2;; both) a=("--key=$key" --gh-keys x); want=2;; esac; if run "arg-$c" "${a[@]}" >/dev/null 2>&1; then s=0; else s=$?; fi; [[ $s == $want && ! -s $tmp/arg-$c/events ]] || fail "argument $c mutated"; done
pass "SSH arguments and help are mutation-free"

for c in package gh-fail gh-empty gh-invalid prompt-cancel prompt-invalid home-symlink home-writable auth-symlink auth-dir; do
  a=("--key=$key")
  case $c in package) PACKAGE_FAIL=1;; gh-fail) GH_FAIL=1; a=(--gh-keys x);; gh-empty) GH_KEYS=''; a=(--gh-keys x);; gh-invalid) GH_KEYS=bad; a=(--gh-keys x);; prompt-cancel) GUM_CHOICE='Paste key manually'; GUM_CANCEL=1; a=();; prompt-invalid) GUM_CHOICE='Paste key manually'; GUM_INPUT=bad; a=();; home-symlink) mkdir -p "$tmp/$c/real-home"; ln -s "$tmp/$c/real-home" "$tmp/$c/home";; home-writable) mkdir -p "$tmp/$c/home"; chmod 0777 "$tmp/$c/home";; auth-symlink) mkdir -p "$tmp/$c/home/.ssh"; ln -s "$tmp/victim" "$tmp/$c/home/.ssh/authorized_keys";; auth-dir) mkdir -p "$tmp/$c/home/.ssh/authorized_keys";; esac
  if run "$c" "${a[@]}" >/dev/null 2>&1; then fail "$c succeeds"; fi; no_publish "$c"; unset PACKAGE_FAIL GH_FAIL GH_KEYS GUM_CHOICE GUM_CANCEL GUM_INPUT
done
GH_KEYS="bad
$key"; run gh-mixed --gh-keys x >/dev/null; grep -qxF "$key" "$tmp/gh-mixed/home/.ssh/authorized_keys"; unset GH_KEYS
pass "key acquisition and authorization fail before publication"

run fresh "--key=$key" >/dev/null
[[ $(head -n1 "$tmp/fresh/events") == 'sudo -k' && $(tail -n1 "$tmp/fresh/events") == 'sudo -k' ]] ||
  fail "SSH setup does not begin and end with credential invalidation" "$(cat "$tmp/fresh/events")"
prev=0
for e in authorized-key installed-hardening host-keygen sshd-t sshd-T 'sudo systemctl start' 'sudo systemctl enable' 'sudo ufw limit'; do n=$(grep -nF "$e" "$tmp/fresh/events"|head -1|cut -d: -f1); [[ -n $n && $prev -lt $n ]] || fail "unsafe fresh order at $e"; prev=$n; done
grep -qxF 'AuthenticationMethods publickey' "$tmp/fresh/root/etc/ssh/sshd_config.d/00-omarchy-key-only.conf"
pass "fresh SSH is key-authorized and validated before publication"

for c in hostkey syntax dump pass kbd methods pubkey keysfile matched; do case $c in hostkey) HOSTKEY_FAIL=1;; syntax) T_FAIL=1;; dump) DUMP_FAIL=1;; pass) PASS_AUTH=yes;; kbd) KBD_AUTH=yes;; methods) AUTH_METHODS=any;; pubkey) PUBKEY_AUTH=no;; keysfile) AUTHORIZED_KEYS_SETTING=/etc/ssh/admin_keys;; matched) MATCH_PASS_AUTH=yes;; esac; if run "$c" "--key=$key" >/dev/null 2>&1; then fail "$c succeeds"; fi; no_publish "$c"; rolled_back "$c"; unset HOSTKEY_FAIL T_FAIL DUMP_FAIL PASS_AUTH KBD_AUTH AUTH_METHODS PUBKEY_AUTH AUTHORIZED_KEYS_SETTING MATCH_PASS_AUTH; done
pass "host-key, syntax, and effective-policy failures are pre-publication"

mkdir -p "$tmp/precedence/root/etc/ssh/sshd_config.d"
printf 'PasswordAuthentication yes\nInclude /etc/ssh/sshd_config.d/*.conf\n' >"$tmp/precedence/root/etc/ssh/sshd_config"
if run precedence "--key=$key" >/dev/null 2>&1; then fail "auth before drop-in include succeeds"; fi
no_publish precedence
mkdir -p "$tmp/earlier/root/etc/ssh/sshd_config.d"; echo '# admin' >"$tmp/earlier/root/etc/ssh/sshd_config.d/-admin.conf"
if run earlier "--key=$key" >/dev/null 2>&1; then fail "earlier expanded drop-in succeeds"; fi
no_publish earlier
for kind in symlink directory; do p="$tmp/hard-$kind/root/etc/ssh/sshd_config.d/00-omarchy-key-only.conf"; mkdir -p "${p%/*}"; if [[ $kind == symlink ]]; then ln -s "$tmp/victim" "$p"; else mkdir "$p"; fi; if run "hard-$kind" "--key=$key" >/dev/null 2>&1; then fail "$kind hardening path succeeds"; fi; [[ $kind != symlink || -L $p ]] && [[ $kind != directory || -d $p ]] || fail "$kind hardening path changed"; no_publish "hard-$kind"; done
pass "ambiguous include precedence and nonregular hardening paths fail closed"

for c in start start-partial enable enable-partial limit limit-partial verify reload; do case $c in start) START_FAIL=1;; start-partial) START_PARTIAL=1;; enable) ENABLE_FAIL=1;; enable-partial) ENABLE_PARTIAL=1;; limit) LIMIT_FAIL=1;; limit-partial) LIMIT_PARTIAL=1;; verify) VERIFY_MISS=1;; reload) UFW_RELOAD_ONCE=1;; esac; if run "$c" "--key=$key" >/dev/null 2>&1; then fail "$c succeeds"; fi; rolled_back "$c"; unset START_FAIL START_PARTIAL ENABLE_FAIL ENABLE_PARTIAL LIMIT_FAIL LIMIT_PARTIAL VERIFY_MISS UFW_RELOAD_ONCE; done
pass "partial service/firewall publication rolls back fresh state"

name=active-fail; cfg="$tmp/$name/root/etc/ssh/sshd_config.d/00-omarchy-key-only.conf"; auth="$tmp/$name/home/.ssh/authorized_keys"; mkdir -p "${cfg%/*}" "${auth%/*}"; echo ADMIN >"$cfg"; chmod 0600 "$cfg"; printf '# existing\n%s\n' "$key" >"$auth"; chmod 0640 "$auth"; before=$(stat -c '%u:%g:%a' "$cfg"):$(sha256sum "$cfg"); auth_before=$(stat -c '%u:%g:%a' "$auth"):$(sha256sum "$auth"); PRE_ACTIVE=1 RELOAD_ONCE=1; if run "$name" "--key=$key" >/dev/null 2>&1; then fail "active reload failure succeeds"; fi; after=$(stat -c '%u:%g:%a' "$cfg"):$(sha256sum "$cfg"); auth_after=$(stat -c '%u:%g:%a' "$auth"):$(sha256sum "$auth"); [[ $before == "$after" && $auth_before == "$auth_after" && $(grep -c 'systemctl reload' "$tmp/$name/events") == 2 ]] || fail "active config/authorized_keys was not exactly restored/reloaded"; unset PRE_ACTIVE RELOAD_ONCE
name=matched-restore; auth="$tmp/$name/home/.ssh/authorized_keys"; mkdir -p "${auth%/*}"; printf '# preserve\n%s\n' "$key" >"$auth"; chmod 0640 "$auth"; auth_before=$(stat -c '%u:%g:%a' "$auth"):$(sha256sum "$auth"); MATCH_PASS_AUTH=yes; if run "$name" "--key=$key" >/dev/null 2>&1; then fail "unsafe matched dump succeeds"; fi; auth_after=$(stat -c '%u:%g:%a' "$auth"):$(sha256sum "$auth"); [[ $auth_before == "$auth_after" ]] || fail "matched-policy failure did not restore authorized_keys exactly"; no_publish "$name"; unset MATCH_PASS_AUTH
PRE_ACTIVE=1 PRE_ENABLED=1 PRE_RULE=1; run existing "--key=$key" >/dev/null; [[ -e $tmp/existing/state/active && -e $tmp/existing/state/enabled && -e $tmp/existing/state/rule ]]; ! grep -Eq 'systemctl (start|enable)|ufw limit' "$tmp/existing/events"; unset PRE_ACTIVE PRE_ENABLED PRE_RULE
pass "pre-existing service/firewall/config state is preserved"

LIMIT_PARTIAL=1 DELETE_FAIL=1 UFW_RELOAD_ALWAYS_FAIL=1; if run rollback-fail "--key=$key" >"$tmp/rollback.out" 2>&1; then fail "incomplete rollback succeeds"; fi; grep -q 'CRITICAL: SSH setup rollback was incomplete' "$tmp/rollback.out" || fail "rollback failure is silent"; unset LIMIT_PARTIAL DELETE_FAIL UFW_RELOAD_ALWAYS_FAIL
pass "rollback failures are loud"

if command -v sshd >/dev/null; then cat >"$tmp/real.conf" <<EOF
HostKey $tmp/key
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Match all
 PasswordAuthentication no
 KbdInteractiveAuthentication no
 AuthenticationMethods publickey
 PubkeyAuthentication yes
 AuthorizedKeysFile .ssh/authorized_keys
Match User nobody
 PasswordAuthentication yes
 KbdInteractiveAuthentication yes
 AuthenticationMethods any
 PubkeyAuthentication no
 AuthorizedKeysFile /etc/ssh/admin_keys
EOF
dump=$(sshd -T -f "$tmp/real.conf" -C user=nobody,host=localhost,addr=127.0.0.1,laddr=127.0.0.1,lport=22); grep -qixF 'passwordauthentication no' <<<"$dump"; grep -qixF 'kbdinteractiveauthentication no' <<<"$dump"; grep -qixF 'authenticationmethods publickey' <<<"$dump"; grep -qixF 'pubkeyauthentication yes' <<<"$dump"; grep -qixF 'authorizedkeysfile .ssh/authorized_keys' <<<"$dump"; pass "real sshd Match cannot bypass first Match-all usable-key policy"; fi
