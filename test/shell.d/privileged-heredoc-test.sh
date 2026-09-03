#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Omarchy does not write a root-owned file through a heredoc whose delimiter is
# unquoted, and this check enforces that.
#
# With an unquoted delimiter (<<EOF rather than <<'EOF') the *installing user's*
# shell expands the body before root ever sees the text, so any value that user
# controls is baked into the result as a literal. Send such a body to /etc and
# the file root later reads or executes carries a value an unprivileged user
# chose.
#
# Worked example -- an installer emitting a udev rule:
#
#   sudo tee /etc/udev/rules.d/99-power-profile.rules <<EOF
#   ACTION=="change", SUBSYSTEM=="power_supply", RUN+="$HOME/.local/share/omarchy/bin/omarchy-power-profile"
#   EOF
#
# The delimiter is unquoted, so the rule that lands names
# /home/<user>/.local/share/omarchy/bin/..., and ~/.local/share/omarchy is a
# symlink that same user owns. Replacing the symlink and provoking a
# power_supply event gets their code run by udev as root. Quote the delimiter
# and the rule names a literal $HOME instead, which udev never expands, so
# there is nothing to aim at.
#
# The distinction that matters throughout: install-time expansion bakes a
# literal, user-controlled value into a file root later reads or executes --
# that is the bug. Runtime expansion (an escaped \$VAR left literal in the file
# for a root daemon that does not have the variable set) is a different
# mechanism and is not flagged. install/3-config.sh once used both in one
# heredoc on purpose: $USER expanded at install time because it is a username,
# while \$TERM stayed escaped for systemd to expand later.

# A file under one of these is owned by root, so its content is a root-level
# input no unprivileged user should be able to influence.
PRIVILEGED_PREFIXES=(/etc /usr /opt /srv /boot /var/lib)

# Path roots the installing user can replace outright -- by editing the
# directory, or by swapping a symlink like ~/.local/share/omarchy. An expansion
# anchored in one of these is the shape this check exists to catch.
USER_WRITABLE_VARS=(HOME PWD OLDPWD TMPDIR OMARCHY_PATH OMARCHY_INSTALL
  XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME XDG_RUNTIME_DIR)

# Commands that carry a heredoc's output to its destination, and the ones that
# do it as root. `tee` counts unelevated too: several bin/ commands re-exec
# themselves as root and then tee straight into /etc.
WRITE_COMMANDS=(tee dd install cp mv)
ELEVATORS=(sudo as_root pkexec doas run0)

# A dollar the installing user's shell would act on: $name, ${name}, $1, or $(cmd).
# Kept in a variable because an unquoted `(` inside a bracket expression is a
# syntax error in [[ =~ ]].
EXPANSION_RE='\$[A-Za-z_{(0-9@*#?$!-]'

# One pattern for every expansion form, shared by masking and name extraction
# so the two stay in lockstep.
EXPANSION_SCAN_RE='^([^$]*)\$(\{[^}]*\}|\([^)]*\)|[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?|[0-9@*#?$!-])(.*)$'

# Stand-in name for a command substitution, which has no variable to report.
COMMAND_SUBSTITUTION="command-substitution"

# Sites that legitimately need install-time expansion declare it in a comment
# immediately above the heredoc:
#
#   # omarchy:heredoc-expands paths=none -- $servers is a validated IP list
#   # omarchy:heredoc-expands paths=storage,shared -- checked by valid_path
#
# `paths=` is the machine-checked half, and is what keeps this from being a
# rubber stamp: it must name exactly the expansions that are path-shaped, so
# adding a "$HOME/..." to an already-annotated heredoc makes the declaration
# false and trips the check again instead of inheriting the old exemption. The
# reason after `--` is for the reviewer.
ANNOTATION_RE='^[[:space:]]*#[[:space:]]*omarchy:heredoc-expands[[:space:]]+paths=([A-Za-z_][A-Za-z0-9_-]*(,[A-Za-z_][A-Za-z0-9_-]*)*|none)[[:space:]]+--[[:space:]]+([^[:space:]].*)$'

FINDINGS=()

starts_with_privileged_prefix() {
  local candidate="$1" prefix

  for prefix in "${PRIVILEGED_PREFIXES[@]}"; do
    [[ $candidate == "$prefix"/* ]] && return 0
  done

  return 1
}

in_list() {
  local needle="$1" item
  shift

  for item in "$@"; do
    [[ $needle == "$item" ]] && return 0
  done

  return 1
}

# Drop escaped dollars, backticks and backslashes so what is left is only what
# the installing user's shell would actually expand. Escaped backslashes go
# first, otherwise "\\$TERM" would read as an escaped dollar.
strip_escapes() {
  local text="$1"

  text=${text//\\\\/}
  text=${text//\\$/}
  text=${text//\\\`/}

  printf '%s' "$text"
}

# Replace every expansion in TEXT with \001 and list the variable names in
# order: the masked text first, then one name per line.
#
# Masking whole lines rather than whitespace-split words is what makes
# "DNS=${dns_servers//,/ }" readable. Those slashes belong to the substitution
# operator, not to a path, and the space inside the braces would otherwise
# split the expansion across two words and leave a bare "//,/" looking like a
# path. Because both halves come from one pass over one pattern, the Nth \001
# is the Nth name, so a token can be judged against the right variable.
mask_and_names() {
  local text="$1" masked="" body inner tail name guard=0 nested_masked
  local -a names=() nested_scan=() nested_names=()

  # Normalize backtick substitution into $( ) so one pattern covers both.
  while ((guard++ < 64)) && [[ $text =~ ^([^\`]*)\`([^\`]*)\`(.*)$ ]]; do
    body=${BASH_REMATCH[2]//[()]/}
    text="${BASH_REMATCH[1]}\$($body)${BASH_REMATCH[3]}"
  done

  guard=0
  while ((guard++ < 128)) && [[ $text =~ $EXPANSION_SCAN_RE ]]; do
    masked+="${BASH_REMATCH[1]}"$'\001'
    body=${BASH_REMATCH[2]}
    text=${BASH_REMATCH[4]}
    nested_masked=""
    nested_names=()

    if [[ $body == \(* ]]; then
      name=$COMMAND_SUBSTITUTION
    elif [[ $body == \{* ]]; then
      inner=${body:1:${#body}-2}
      # ${name}, ${name:-default}, ${name//a/b}, ${#name}, ${!name} all start
      # with the name once the decorations are stripped.
      inner=${inner#[\#!]}
      if [[ $inner =~ ^([A-Za-z_][A-Za-z0-9_]*) ]]; then
        name=${BASH_REMATCH[1]}
        tail=${inner#"$name"}
      elif [[ $inner =~ ^[0-9@*#?$!-] ]]; then
        name="shell-parameter"
        tail=${inner:1}
      else
        name=$COMMAND_SUBSTITUTION
        tail=$inner
      fi

      # The shell expands the operator payload too. Keep it as a synthetic
      # adjacent token so its placeholders stay aligned with their names while
      # the outer expansion remains independently classifiable. Without this,
      # ${target:-$HOME/path} is consumed as only `target` and hides HOME.
      if [[ $tail =~ $EXPANSION_RE || $tail == *'`'* ]]; then
        mapfile -t nested_scan < <(mask_and_names "$tail")
        nested_masked=${nested_scan[0]}
        nested_names=("${nested_scan[@]:1}")
      fi
    else
      name=${body%%\[*}
      [[ $name =~ ^[A-Za-z_] ]] || name="shell-parameter"
    fi

    names+=("$name")
    if ((${#nested_names[@]} > 0)); then
      masked+=" $nested_masked"
      names+=("${nested_names[@]}")
    fi
  done

  printf '%s\n' "$masked$text"
  if ((${#names[@]} > 0)); then
    printf '%s\n' "${names[@]}"
  fi
}

declare -A VARS=()
declare -A VARS_TAINTED=()

# Literal assignments in the file under scan, so a destination written as
# "$DROP_IN" or "$COMPOSE_FILE" can be judged as the path it actually is.
# First assignment wins: these scripts set a constant once, and an append like
# boot_params+=(...) is not an assignment this reads at all.
#
# VARS_TAINTED records, separately, any name that is assigned a value naming a
# root the user can replace -- at any point in the file, not just the assignment
# that won. That is what stops a name being introduced with a harmless packaged
# value and then reassigned under $HOME, which judging one assignment in
# isolation would miss in whichever direction it picked.
collect_vars() {
  local -n source_lines="$1"
  local line name value append

  VARS=()
  VARS_TAINTED=()
  for line in "${source_lines[@]}"; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*(local|declare|export|readonly|typeset)?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)(\+?)=(.*)$ ]] || continue

    name=${BASH_REMATCH[2]}
    append=${BASH_REMATCH[3]}
    value=${BASH_REMATCH[4]}
    value=${value%%[[:space:]]#*}
    value=${value%[[:space:]]}
    if [[ $value == \"*\" || $value == \'*\' ]]; then
      value=${value:1:${#value}-2}
    fi

    mentions_user_writable_root "$value" && VARS_TAINTED["$name"]=1

    # An append never wins the value -- an array grown across a file resolves to
    # nothing useful -- but it does carry the taint, or a name could reach a user
    # root through += and never be judged on it.
    [[ -n $append ]] && continue
    [[ -v VARS[$name] ]] || VARS["$name"]=$value
  done
}

# Expand what can be expanded from the file's own assignments. ${NAME:-default}
# falls back to the default, which is how RUNTIME_DIR reaches
# /var/lib/omarchy/windows; mktemp is unwrapped to the template it is handed, so
# a scratch file inside a privileged directory still reads as privileged.
resolve_value() {
  local value="$1" outer=0 inner before name default replacement

  while ((outer++ < 8)); do
    before=$value

    inner=0
    while ((inner++ < 32)) && [[ $value =~ \$\{([A-Za-z_][A-Za-z0-9_]*):?-([^}]*)\} ]]; do
      name=${BASH_REMATCH[1]}
      default=${BASH_REMATCH[2]}
      if [[ -v VARS[$name] && ${VARS[$name]} != *"\$$name"* ]]; then
        replacement=${VARS[$name]}
      else
        replacement=$default
      fi
      value=${value/"${BASH_REMATCH[0]}"/$replacement}
    done

    inner=0
    while ((inner++ < 32)) && [[ $value =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*) ]]; do
      name=${BASH_REMATCH[1]}
      [[ -n $name ]] || name=${BASH_REMATCH[2]}
      [[ -v VARS[$name] && ${VARS[$name]} != *"\$$name"* ]] || break
      value=${value/"${BASH_REMATCH[0]}"/${VARS[$name]}}
    done

    if [[ $value =~ \$\(mktemp[^\)]*[[:space:]]\"?([^\"\)]+)\"?\) ]]; then
      value=${BASH_REMATCH[1]}
    fi

    [[ $value == "$before" ]] && break
  done

  printf '%s' "$value"
}

# Strip a leading KEY= and any opening quote so a token's literal head can be
# compared against the privileged prefixes.
literal_head() {
  local text="$1"

  [[ $text =~ ^[A-Za-z_][A-Za-z0-9_]*\+?= ]] && text=${text#*=}
  text=${text#[\"\']}

  printf '%s' "$text"
}

# The literal value a name is assigned, when that value is knowable. A value
# read out of a command substitution is not: resolving it would treat the
# slashes in the command itself as a path, which made $autologin_user (an awk
# over /etc/sddm.conf.d) look like a path when it holds a username.
literal_value() {
  local name="$1"

  [[ -v VARS[$name] ]] || return 0
  [[ ${VARS[$name]} != *'$('* && ${VARS[$name]} != *'`'* ]] || return 0

  resolve_value "${VARS[$name]}"
}

# Does TEXT still reference a root the installing user can replace? Used on a
# value the scan could not fully resolve, where the remaining "$HOME" or
# "${XDG_DATA_HOME}" is the whole reason the value cannot be trusted as a
# root-owned path. A chain through a name this scan never saw assigned resolves
# to neither, and is judged on the rest of the evidence.
mentions_user_writable_root() {
  local text="$1" name pattern

  for name in "${USER_WRITABLE_VARS[@]}"; do
    # Whole name only. A prefix match would read ${OMARCHY_INSTALL_USER:-}, which
    # holds a username, as OMARCHY_INSTALL, which holds a path.
    pattern='\$\{?'"$name"'([^A-Za-z0-9_]|$)'
    [[ $text =~ $pattern ]] && return 0
  done

  return 1
}

# Is this expansion used as a path, and if so, is that path anchored somewhere
# root already owns? MASKED is the containing whitespace token with expansions
# replaced by \001.
#
# Path-shaped means the literal text left around the expansion contains a slash
# ("$HOME/.local/...", "$storage:/storage"), or the variable names a
# user-writable root, or it is assigned a literal value containing a slash.
# Anchored means the literal text *before* the expansion is itself a privileged
# path, as in "/etc/systemd/system/$unit" -- still a path, but one root owns end
# to end. Scoping the anchor test to the containing token is what keeps a udev
# RUN+= line honest: it can name /usr/bin/systemd-run earlier on the same line
# while the $HOME token stands alone.
classify_expansion() {
  local masked="$1" name="$2" head literal piece
  local path_shape=""

  head=$(literal_head "$masked")
  head=${head%%$'\001'*}
  literal=$(literal_value "$name")

  [[ $masked == */* ]] && path_shape+="token "
  in_list "$name" "${USER_WRITABLE_VARS[@]}" && path_shape+="user-root "
  [[ -v VARS_TAINTED[$name] ]] && path_shape+="tainted "
  [[ -n $literal && $literal == */* ]] && path_shape+="literal "

  [[ -n $path_shape ]] || return 1

  # A path expansion anchored under a root-owned prefix cannot introduce a
  # user-writable location, so it does not need declaring.
  starts_with_privileged_prefix "$head" && return 1

  # When the token itself is not a path and the shape came only from the
  # assigned value, a variable holding root-owned absolute paths is not baking
  # anything user-writable in: that is how $fprintd_gate carries
  # /usr/bin/omarchy-hw-laptop-closed. This rescue deliberately does not apply
  # when the token is a path, so "$storage:/storage" stays flagged.
  #
  # It also does not apply to a value this scan could not finish resolving whose
  # unresolved part reaches a root the user can replace. One hop is all it takes
  # to hide the shape: helper="$HOME/.local/share/omarchy/bin/agent" followed by
  # ExecStart=$helper puts no slash in the token and no literal path in the value,
  # so rescuing it would exempt exactly the write this check exists to catch. A
  # value that merely fails to resolve -- a kernel parameter list, an escaped
  # password -- is left to the rescue, since nothing in it names a user root.
  # A name assigned a user root anywhere in the file is never rescued: the
  # assignment that won may be the packaged path it was later reassigned away
  # from, and the rescue would then clear it on evidence it no longer holds.
  if [[ $path_shape == "literal " ]]; then
    for piece in $literal; do
      piece=$(literal_head "$piece")
      if mentions_user_writable_root "$piece"; then
        return 0
      fi
      if [[ $piece == /* ]] && ! starts_with_privileged_prefix "$piece"; then
        return 0
      fi
    done
    return 1
  fi

  return 0
}

# Destination paths a command line hands a heredoc's output, as written. An
# "\002elevated" marker is emitted when the line runs through sudo and friends.
command_destinations() {
  local line="$1" token target elevated=1 copy_like=1 last="" index scan
  local -a tokens=()

  # Quotes only get in the way of splitting; the paths inside them do not
  # contain spaces anywhere this check runs.
  line=${line//\"/ }
  line=${line//\'/ }
  # `>|` overrides noclobber; the bar belongs to the operator, not to a pipe.
  # Left alone it becomes the redirect's target and hides the privileged path
  # behind it, so a `cat <<EOF >| /etc/...` heredoc reports no destination.
  line=${line//">|"/">"}
  # Preserve append redirects before detaching redirect operators from their
  # targets, so ">> /etc/x" does not become two ">" tokens whose first target
  # is the second operator.
  line=${line//>>/$'\003'}
  line=${line//>/ > }
  line=${line//$'\003'/" >> "}

  read -r -a tokens <<<"$line"

  index=0
  while ((index < ${#tokens[@]})); do
    token=${tokens[index]}
    index=$((index + 1))

    in_list "$token" "${ELEVATORS[@]}" && elevated=0

    if [[ $token == ">" || $token == ">>" ]]; then
      target=${tokens[index]:-}
      index=$((index + 1))
      [[ -n $target && $target != "&"* && $target != /dev/* ]] && printf '%s\n' "$target"
      continue
    fi

    if [[ $token == of=* ]]; then
      printf '%s\n' "${token#of=}"
      continue
    fi

    if in_list "$token" "${WRITE_COMMANDS[@]}"; then
      if [[ $token == "tee" ]]; then
        # Every non-flag argument to tee is a destination.
        scan=$index
        while ((scan < ${#tokens[@]})); do
          target=${tokens[scan]}
          scan=$((scan + 1))
          [[ $target == "|" || $target == "&&" || $target == ";" ]] && break
          [[ $target == -* || $target == "<"* || $target == ">" || $target == of=* ]] && continue
          [[ $target == /dev/* ]] && continue
          printf '%s\n' "$target"
        done
      elif [[ $token != "dd" ]]; then
        # dd destinations are expressed only by of= operands, handled above.
        copy_like=0
      fi
      continue
    fi

    [[ $token != -* && $token != "|" && $token != "<"* && $token != ">" ]] && last=$token
  done

  # install/cp/mv put the destination last.
  if ((copy_like == 0)) && [[ -n $last ]]; then
    printf '%s\n' "$last"
  fi

  if ((elevated == 0)); then
    printf '%s\n' $'\002elevated'
  fi
}

# Does LINE carry the same resolved value as DEST? Compare resolved tokens rather
# than source spelling so $tmp, ${tmp}, and an alias assigned from either form
# all identify the same scratch file.
line_carries_destination() {
  local line="$1" dest="$2" resolved token candidate
  local -a tokens=()

  resolved=$(resolve_value "$dest")
  line=${line//\"/ }
  line=${line//\'/ }
  read -r -a tokens <<<"$line"

  for token in "${tokens[@]}"; do
    token=${token#[<>]}
    token=${token%;}
    candidate=$(resolve_value "$token")
    [[ $candidate == "$resolved" ]] && return 0
  done

  return 1
}

# Does the heredoc on this line reach a root-owned file? Either directly, or in
# one hop: written to a scratch file that a later install/cp/mv carries into a
# privileged directory.
privileged_destination() {
  local line="$1" start_index="$2"
  local -n scan_lines="$3"
  local dest resolved elevated=1 follow hop hop_dest
  local -a unresolved=()

  while IFS= read -r dest; do
    if [[ $dest == $'\002elevated' ]]; then
      elevated=0
      continue
    fi

    resolved=$(resolve_value "$dest")
    resolved=${resolved#\~}
    if starts_with_privileged_prefix "$resolved"; then
      printf '%s' "$resolved"
      return 0
    fi

    if [[ $resolved == *'$'* ]]; then
      unresolved+=("$dest")
    fi

    # One hop: a later copy of this same destination into a root-owned path.
    # Literal scratch files need tracing just as much as variable destinations.
    follow=$start_index
    while ((follow < ${#scan_lines[@]})); do
      hop=${scan_lines[follow]}
      follow=$((follow + 1))
      [[ $hop =~ (^|[[:space:]])(install|cp|mv)([[:space:]]|$) ]] || continue
      line_carries_destination "$hop" "$dest" || continue
      while IFS= read -r hop_dest; do
        [[ $hop_dest == $'\002elevated' ]] && continue
        [[ $hop_dest == "$dest" ]] && continue
        hop_dest=$(resolve_value "$hop_dest")
        if starts_with_privileged_prefix "$hop_dest"; then
          printf '%s' "$hop_dest"
          return 0
        fi
      done < <(command_destinations "$hop")
    done
  done < <(command_destinations "$line")

  # An elevated write whose destination cannot be resolved counts as privileged:
  # sudo tee is not aimed at a user's own dotfile.
  if ((elevated == 0)) && ((${#unresolved[@]} > 0)); then
    printf '%s' "${unresolved[0]} (unresolved destination of an elevated write)"
    return 0
  fi

  return 1
}

# A pipeline may put the command consuming a heredoc after its terminator:
#
#   cat <<EOF |
#   body
#   EOF
#     sudo tee /etc/file
#
# Join only while the command is syntactically continued, leaving unrelated
# commands below the heredoc to be scanned independently.
continued_heredoc_command() {
  local command="$1" next="$2"
  local -n source_lines="$3"

  while [[ $command =~ (\|\||&&|\|)[[:space:]]*$ ]] && ((next < ${#source_lines[@]})); do
    while ((next < ${#source_lines[@]})) && [[ ${source_lines[next]} =~ ^[[:space:]]*(#.*)?$ ]]; do
      next=$((next + 1))
    done
    ((next < ${#source_lines[@]})) || break
    command+=" ${source_lines[next]}"
    next=$((next + 1))
  done

  printf '%s' "$command"
}

# Count the \001 placeholders in a masked token.
count_placeholders() {
  local text="$1" count=0

  while [[ $text == *$'\001'* ]]; do
    count=$((count + 1))
    text=${text#*$'\001'}
  done

  printf '%s' "$count"
}

normalize_path_set() {
  local value="$1"
  local -a names=()

  if [[ $value == "none" ]]; then
    printf 'none'
    return 0
  fi

  IFS=, read -ra names <<<"$value"
  mapfile -t names < <(printf '%s\n' "${names[@]}" | sort -u)
  (
    IFS=,
    printf '%s' "${names[*]}"
  )
}

inside_same_line_arithmetic() {
  local prefix="$1" opens=0 closes=0

  while [[ $prefix == *"(("* ]]; do
    opens=$((opens + 1))
    prefix=${prefix#*"(("}
  done
  while [[ $prefix == *"))"* ]]; do
    closes=$((closes + 1))
    prefix=${prefix#*"))"}
  done

  ((opens > closes))
}

scan_file() {
  local file="$1" display="${2:-$1}"
  local -a lines=()
  local index lineno line command scan rest raw operator match prefix guard slot delim candidate candidate_delim body_start
  local body_text unescaped destination destination_command body_line masked_line token name
  local declared_paths annotation look shown_paths shown_plain count next slots terminated
  local hd_re='(<<-?)[[:space:]]*("[A-Za-z_][A-Za-z0-9_]*"|'"'"'[A-Za-z_][A-Za-z0-9_]*'"'"'|[A-Za-z_][A-Za-z0-9_]*)'

  mapfile -t lines <"$file"
  collect_vars lines

  index=0
  while ((index < ${#lines[@]})); do
    line=${lines[index]}
    lineno=$((index + 1))
    index=$((index + 1))

    [[ $line =~ ^[[:space:]]*# ]] && continue

    # A backslash-escaped newline is removed before Bash parses the command, so
    # a pipeline consumer can appear on the next physical line before heredoc
    # body collection begins: `cat <<EOF | \\` then `sudo tee /etc/file`.
    # Join those physical lines first. A bare newline after `|` instead starts
    # the heredoc body and is handled after the terminator below.
    command=$line
    while [[ $command == *\\ ]] && ((index < ${#lines[@]})); do
      command=${command%\\}
      command+=" ${lines[index]}"
      index=$((index + 1))
    done

    # Herestrings are not heredocs. Blanking them keeps <<<"$x" from reading as
    # a heredoc while preserving every other offset on the line.
    scan=${command//<<</   }
    [[ $scan == *"<<"* ]] || continue

    # Collect this line's heredoc delimiters in order. Quoted ones are safe by
    # construction but still have to be tracked, or their bodies would be
    # parsed as code.
    local -a delims=() quoted=() strip_tabs=()
    rest=$scan
    guard=0
    while ((guard++ < 8)) && [[ $rest =~ $hd_re ]]; do
      match=${BASH_REMATCH[0]}
      operator=${BASH_REMATCH[1]}
      raw=${BASH_REMATCH[2]}
      prefix=${rest%%"$match"*}
      rest=${rest#*"$match"}

      # `(( value << shift ))` and `$(( value << shift ))` are arithmetic, not
      # heredocs. Without this guard the shift count becomes a phantom delimiter
      # and can consume every real heredoc below it.
      inside_same_line_arithmetic "$prefix" && continue

      if [[ $raw == \"*\" || $raw == \'*\' ]]; then
        delims+=("${raw:1:${#raw}-2}")
        quoted+=(0)
      else
        delims+=("$raw")
        quoted+=(1)
      fi
      [[ $operator == "<<-" ]] && strip_tabs+=(1) || strip_tabs+=(0)
    done

    ((${#delims[@]} > 0)) || continue

    for slot in "${!delims[@]}"; do
      delim=${delims[slot]}
      local -a body=()
      body_start=$index
      terminated=1

      while ((index < ${#lines[@]})); do
        candidate=${lines[index]}
        index=$((index + 1))
        candidate_delim=$candidate
        if ((strip_tabs[slot] == 1)); then
          while [[ $candidate_delim == $'\t'* ]]; do
            candidate_delim=${candidate_delim#$'\t'}
          done
        fi
        if [[ $candidate_delim == "$delim" ]]; then
          terminated=0
          break
        fi
        body+=("$candidate")
      done

      # A valid shell source cannot contain an unterminated heredoc. If this
      # candidate has no terminator it was syntax such as a multi-line arithmetic
      # shift that the lightweight matcher could not classify; resume scanning
      # below it instead of swallowing the rest of the file.
      if ((terminated != 0)); then
        index=$body_start
        continue
      fi

      # A quoted delimiter cannot expand anything.
      ((quoted[slot] == 1)) || continue

      printf -v body_text '%s\n' "${body[@]:-}"
      unescaped=$(strip_escapes "$body_text")
      [[ $unescaped =~ $EXPANSION_RE || $unescaped == *'`'* ]] || continue

      destination_command=$(continued_heredoc_command "$command" "$index" lines)
      destination=$(privileged_destination "$destination_command" "$index" lines) || continue

      # Sort the expansions into the ones that bake a path into the file and
      # the ones that only interpolate a scalar.
      local -a path_expansions=() plain_expansions=() scanned=() names=()
      while IFS= read -r body_line; do
        mapfile -t scanned < <(mask_and_names "$body_line")
        masked_line=${scanned[0]}
        names=("${scanned[@]:1}")
        next=0

        for token in $masked_line; do
          count=$(count_placeholders "$token")
          ((count > 0)) || continue

          for ((slots = 0; slots < count; slots++)); do
            name=${names[next]:-}
            next=$((next + 1))
            [[ -n $name ]] || continue

            if classify_expansion "$token" "$name"; then
              in_list "$name" "${path_expansions[@]:-}" || path_expansions+=("$name")
            else
              in_list "$name" "${plain_expansions[@]:-}" || plain_expansions+=("$name")
            fi
          done
        done
      done <<<"$unescaped"

      declared_paths=""
      annotation=""
      look=$((lineno - 2))
      while ((look >= 0)) && [[ ${lines[look]} =~ ^[[:space:]]*# ]]; do
        if [[ ${lines[look]} =~ $ANNOTATION_RE ]]; then
          declared_paths=${BASH_REMATCH[1]}
          annotation=${BASH_REMATCH[3]}
        fi
        look=$((look - 1))
      done

      shown_paths="none"
      if ((${#path_expansions[@]} > 0)); then
        shown_paths=$(
          IFS=,
          printf '%s' "${path_expansions[*]}"
        )
      fi
      shown_plain="none"
      if ((${#plain_expansions[@]} > 0)); then
        shown_plain=$(
          IFS=,
          printf '%s' "${plain_expansions[*]}"
        )
      fi

      if [[ -z $annotation ]]; then
        FINDINGS+=("$display:$lineno: unquoted heredoc <<$delim expands values at install time and its output reaches $destination
    path-shaped expansions: $shown_paths
    other expansions:       $shown_plain
    Whatever expands here is baked into a file root owns. If it is a path the
    installing user can replace, root later reads or executes attacker-controlled
    content -- that is a local privilege escalation.
    Fix, in order of preference:
      1. quote the delimiter (<<'$delim') so nothing expands at install time;
      2. hardcode an absolute root-owned path instead of expanding one;
      3. if the expansion is genuinely required, declare it above the heredoc:
           # omarchy:heredoc-expands paths=<expansions used as paths, or none> -- <why this is safe>
         Decide that list yourself. The scan's own reading of it is above, and
         where the scan is most likely wrong is exactly here -- a path it could
         not follow reads as an ordinary value -- so pasting its verdict back
         signs off on the case worth checking by hand.")
        continue
      fi

      if [[ $(normalize_path_set "$declared_paths") != $(normalize_path_set "$shown_paths") ]]; then
        FINDINGS+=("$display:$lineno: heredoc annotation declares paths=$declared_paths but the path-shaped expansions are $shown_paths
    Writing to: $destination
    Every expansion used as a path outside a root-owned prefix has to be named,
    so adding one to an already-annotated heredoc trips this check again instead
    of inheriting the old exemption.
    Fix: drop the path expansion (hardcode an absolute root-owned path), or name
    every path-shaped expansion in the declaration and say why root using it is
    safe.")
      fi
    done
  done
}

# bin/, install/ and migrations/ are where privileged writes live: bin/ holds
# the setup and upgrade commands, install/ runs during install, migrations/
# during update. default/ is scanned too even though the pattern is not
# reachable there today -- it ships bash functions and completions whose only
# "<<" uses are herestrings, with no privileged writes at all -- because the
# scan is cheap and default/ is sourced into every login shell, so a privileged
# write arriving there later should not arrive unchecked.
shell_sources() {
  local file first

  while IFS= read -r -d '' file; do
    # Binary files and sources with no heredoc operator have nothing this check
    # can classify. Filter them before collect_vars and the line-by-line scan.
    grep -Iq '<<' "$file" 2>/dev/null || continue

    case $file in
      *.sh | *.hook)
        printf '%s\0' "$file"
        continue
        ;;
    esac

    IFS= read -r first <"$file" || true
    if [[ $first =~ ^#!.*[[:space:]/](bash|sh)$ ]]; then
      printf '%s\0' "$file"
    fi
  done < <(find "$ROOT/bin" "$ROOT/install" "$ROOT/migrations" "$ROOT/default" \
    -type f -print0 2>/dev/null | sort -z)
}

require_command find
require_command grep

sources=()
while IFS= read -r -d '' file; do
  sources+=("$file")
done < <(shell_sources)

((${#sources[@]} > 50)) || fail "the scan reaches the privileged-write scripts" \
  "only ${#sources[@]} shell sources found under bin/, install/, migrations/ and default/"
pass "the scan reaches the privileged-write scripts (${#sources[@]} files)"

for file in "${sources[@]}"; do
  scan_file "$file" "${file#"$ROOT"/}"
done

if ((${#FINDINGS[@]} > 0)); then
  fail "no privileged write embeds an install-time expansion through an unquoted heredoc" \
    "$(printf '%s\n\n' "${FINDINGS[@]}")"
fi
pass "no privileged write embeds an install-time expansion through an unquoted heredoc"

# --- Non-vacuity ------------------------------------------------------------
#
# A check that cannot catch the bug it was written for is worthless, so the same
# scanner runs against fixtures: installer shapes taken verbatim from this
# repository's history, the routes other than a pipe into sudo tee, and the
# shapes that must stay quiet.

FIXTURES="$SHELL_TEST_DIR/fixtures/privileged-heredoc"

fixture_flags() {
  local fixture="$1" description="$2" expected="${3:-}"

  FINDINGS=()
  scan_file "$FIXTURES/$fixture" "$fixture"

  ((${#FINDINGS[@]} > 0)) || fail "$description" "$fixture produced no finding"
  if [[ -n $expected ]]; then
    printf '%s\n' "${FINDINGS[@]}" | grep -qF -- "$expected" ||
      fail "$description" "expected \"$expected\" in:$(printf '\n%s' "${FINDINGS[@]}")"
  fi
  pass "$description"
}

fixture_passes() {
  local fixture="$1" description="$2"

  FINDINGS=()
  scan_file "$FIXTURES/$fixture" "$fixture"

  ((${#FINDINGS[@]} == 0)) || fail "$description" "$(printf '%s\n' "${FINDINGS[@]}")"
  pass "$description"
}

# Verbatim installer shapes: two udev rules whose RUN+= resolves through a
# user's home, and a systemd unit whose ExecStop did the same. Kept as written
# rather than tidied, so the fixtures stay faithful to the real shape instead of
# a cleaned-up sketch of it.
fixture_flags udev-rule-home-path.sh \
  "flags a power-profile udev rule whose RUN+= resolves under \$HOME" \
  "path-shaped expansions: HOME"
fixture_flags wifi-rule-home-path.sh \
  "flags a wifi-powersave udev rule whose RUN+= resolves under \$HOME" \
  "path-shaped expansions: HOME"
fixture_flags shutdown-unit-home-execstop.sh \
  "flags a shutdown unit with ExecStop=\$HOME/..." \
  "path-shaped expansions: HOME"

# The exemption must not be a rubber stamp: the same file carrying a
# plausible-looking annotation still fails, because $HOME is path-shaped and
# the declaration does not say so.
fixture_flags annotated-paths-none-still-fails.sh \
  "an annotation claiming paths=none cannot silence a baked \$HOME path" \
  "declares paths=none but the path-shaped expansions are HOME"
fixture_flags annotated-special-parameter-before-home.sh \
  "a shell special parameter cannot hide a later baked \$HOME path" \
  "declares paths=none but the path-shaped expansions are HOME"

# A path can hide one or more hops away from the heredoc. In each of these the
# token in the body has no slash and the value never resolves to a literal path,
# so an annotation of paths=none looks plausible while the write still bakes the
# user's home into a root-owned file. The declaration has to name the expansion.
fixture_flags hop-variable-home-path.sh \
  "an annotation cannot exempt a home path carried one variable hop away" \
  "declares paths=none but the path-shaped expansions are helper"
fixture_flags hop-twice-home-path.sh \
  "an annotation cannot exempt a home path carried two variable hops away" \
  "declares paths=none but the path-shaped expansions are helper"
fixture_flags shadowed-assignment-home-path.sh \
  "a later assignment under \$HOME is judged, not the packaged value it shadowed" \
  "declares paths=none but the path-shaped expansions are target"

# Routes other than a direct pipe into sudo tee.
fixture_flags route-redirect.sh "flags a plain redirect into /etc"
fixture_flags route-sudo-dd.sh "flags sudo dd of= into a privileged path"
fixture_flags route-variable-path.sh \
  "flags an elevated write whose destination is a variable resolving under /etc"
fixture_flags route-install-hop.sh \
  "flags a scratch file that install(1) later copies into /usr"
fixture_flags route-install-hop-literal.sh \
  "flags a literal scratch file that install(1) later copies into /etc"
fixture_flags route-install-hop-braced.sh \
  "flags a scratch-file hop whose variable uses braces at the privileged copy"
fixture_flags route-install-hop-alias.sh \
  "flags a scratch-file hop carried through an alias variable"
fixture_flags route-continued-pipeline.sh \
  "flags a privileged pipeline command continued after the heredoc terminator"
fixture_flags route-prebody-escaped-pipeline.sh \
  "flags an escaped-line pipeline consumer before the heredoc body"
fixture_flags route-dash-delimiter.sh "flags an indented <<- heredoc"
fixture_flags route-append-redirect.sh "flags an append redirect into /etc"
fixture_flags route-noclobber-redirect.sh \
  "flags a noclobber-override redirect into /etc"
fixture_flags arithmetic-left-shift-before-heredoc.sh \
  "an arithmetic left shift does not swallow a later privileged heredoc" \
  "path-shaped expansions: HOME"
fixture_flags plain-heredoc-indented-pseudo-delimiter.sh \
  "an indented delimiter does not terminate a plain heredoc" \
  "path-shaped expansions: HOME"
fixture_flags nested-parameter-default.sh \
  "a nested parameter default cannot hide a baked home path" \
  "path-shaped expansions are HOME"

mapfile -t dd_destinations < <(command_destinations \
  'sudo dd if=/tmp/input bs=4M status=none of=/etc/omarchy/image')
[[ ${dd_destinations[0]:-} == "/etc/omarchy/image" && ${dd_destinations[1]:-} == $'\002elevated' && ${#dd_destinations[@]} == 2 ]] ||
  fail "dd emits only its of= destination" "$(printf '%q\n' "${dd_destinations[@]:-}")"
pass "dd emits only its of= destination"

# Negatives.
fixture_passes safe-quoted-delimiter.sh "a quoted delimiter passes"
fixture_passes safe-user-destination.sh \
  "an unquoted heredoc expanding into the user's own ~/.config passes"
fixture_passes safe-no-expansion.sh \
  "a privileged write with no expansion in the body passes"
fixture_passes safe-runtime-expansion.sh \
  "an escaped \\\$VAR left for a root daemon to expand passes"
fixture_passes safe-annotated.sh "a declared, reasoned exemption passes"
fixture_passes safe-annotated-reordered-paths.sh \
  "path declarations compare as sets rather than traversal order"
fixture_passes safe-root-anchored.sh \
  "a path expansion anchored under /etc is truthfully declared paths=none"
fixture_passes safe-herestring.sh "a herestring is not mistaken for a heredoc"
