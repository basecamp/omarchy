# Shared catalog for Install / Remove Preinstalls.
# Sourced by omarchy-install-preinstalls and omarchy-remove-preinstalls.
# Kind keys: pkg, webapp, tui, agent.

PREINSTALL_PACKAGES=(
  aether
  cliamp
  libreoffice-fresh
  xournalpp
  pinta
  obsidian
  obs-studio
  kdenlive
  moonlight-qt
  lazydocker
  omacut
  omacalc
  omawrite
)

PREINSTALL_PACKAGE_LABELS=(
  aether:Aether
  cliamp:Cliamp
  libreoffice-fresh:LibreOffice
  xournalpp:Xournal++
  pinta:Pinta
  obsidian:Obsidian
  obs-studio:OBS Studio
  kdenlive:Kdenlive
  moonlight-qt:Moonlight
  lazydocker:Lazydocker
  omacut:Omacut
  omacalc:Omacalc
  omawrite:Omawrite
)

# command|label|omarchy-mise-install args|extra files to delete on remove
PREINSTALL_AGENTS=(
  "codex|Codex|codex|"
  "claude|Claude|claude|"
  "crush|Crush|crush|"
  "agy|Antigravity|antigravity-cli agy|"
  "gh|GitHub CLI|gh|"
  "copilot|Copilot|copilot|"
  "opencode|OpenCode|opencode|"
  "playwright|Playwright|npm:playwright playwright|playwright-cli"
  "pi|Pi|pi|"
  "omp|Oh My Pi|github:can1357/oh-my-pi omp|"
  "grok|Grok|npm:@xai-official/grok grok|"
  "ghui|ghui|npm:@kitlangton/ghui ghui|"
  "hunk|Hunk|aqua:modem-dev/hunk hunk|"
  "hey|HEY CLI|github:basecamp/hey-cli hey|"
  "ori|Ori|github:OpenRouterLabs/ori-releases ori|"
)

preinstalls_desktop_kind() {
  local file=$1

  if grep -q '^Exec=.*\(omarchy-launch-webapp\|omarchy-webapp-handler\)' "$file"; then
    printf '%s\n' webapp
  elif grep -q 'Exec=xdg-terminal-exec --app-id=TUI\.' "$file"; then
    printf '%s\n' tui
  fi
}

preinstalls_desktop_name() {
  awk -F= '/^Name=/{ print substr($0, 6); exit }' "$1"
}

preinstalls_icon_name() {
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//'
}

preinstalls_label_for_package() {
  local package=$1 pair label

  for pair in "${PREINSTALL_PACKAGE_LABELS[@]}"; do
    if [[ ${pair%%:*} == "$package" ]]; then
      printf '%s\n' "${pair#*:}"
      return
    fi
  done

  printf '%s\n' "$package"
}

# Prints kind<TAB>id<TAB>label for every catalog item, packages first, then
# shipped web apps, TUIs, and agent stubs.
preinstalls_catalog() {
  local package file kind name agent command label mise extra

  for package in "${PREINSTALL_PACKAGES[@]}"; do
    printf 'pkg\t%s\t%s\n' "$package" "$(preinstalls_label_for_package "$package")"
  done

  for file in "$OMARCHY_PATH"/applications/*.desktop; do
    [[ -f "$file" ]] || continue
    kind=$(preinstalls_desktop_kind "$file")
    [[ -n $kind ]] || continue
    name=$(basename "$file" .desktop)
    printf '%s\t%s\t%s\n' "$kind" "$name" "$(preinstalls_desktop_name "$file")"
  done

  for agent in "${PREINSTALL_AGENTS[@]}"; do
    IFS='|' read -r command label mise extra <<<"$agent"
    printf 'agent\t%s\t%s\n' "$command" "$label"
  done
}

preinstalls_agent_record() {
  local wanted=$1 agent command label mise extra

  for agent in "${PREINSTALL_AGENTS[@]}"; do
    IFS='|' read -r command label mise extra <<<"$agent"
    if [[ $command == "$wanted" ]]; then
      printf '%s\n' "$agent"
      return 0
    fi
  done

  return 1
}

preinstalls_item_present() {
  local kind=$1 id=$2 extra command label mise
  local desktop="$HOME/.local/share/applications/$id.desktop"

  case $kind in
  pkg)
    omarchy-pkg-present "$id"
    ;;
  webapp | tui)
    [[ -f "$desktop" ]]
    ;;
  agent)
    extra=$(preinstalls_agent_record "$id") || return 1
    IFS='|' read -r command label mise extra <<<"$extra"
    [[ -e "$HOME/.local/bin/$command" ]]
    ;;
  *)
    return 1
    ;;
  esac
}

preinstalls_ids_for_mode() {
  local mode=$1 kind id label

  while IFS=$'\t' read -r kind id label; do
    case $mode in
    install)
      preinstalls_item_present "$kind" "$id" && continue
      ;;
    remove)
      preinstalls_item_present "$kind" "$id" || continue
      ;;
    esac

    printf '%s\t%s\t%s\n' "$kind" "$id" "$label"
  done < <(preinstalls_catalog)
}

preinstalls_picker_row() {
  local kind=$1 id=$2 label=$3 kind_label

  case $kind in
  pkg) kind_label=app ;;
  webapp) kind_label="web app" ;;
  tui) kind_label=TUI ;;
  agent) kind_label=agent ;;
  esac

  printf '%s (%s)|%s:%s\n' "$label" "$kind_label" "$kind" "$id"
}

preinstalls_catalog_has_spec() {
  local spec=$1 kind id label
  local -a rows=()

  mapfile -t rows < <(preinstalls_catalog)
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r kind id label <<<"$row"
    if [[ $kind:$id == "$spec" ]]; then
      return 0
    fi
  done

  return 1
}

preinstalls_resolve_token() {
  local token=$1 kind id label
  local -a rows=()

  if [[ $token == pkg:* || $token == webapp:* || $token == tui:* || $token == agent:* ]]; then
    preinstalls_catalog_has_spec "$token" || return 1
    printf '%s\n' "$token"
    return 0
  fi

  mapfile -t rows < <(preinstalls_catalog)
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r kind id label <<<"$row"
    if [[ $id == "$token" || $label == "$token" ]]; then
      printf '%s:%s\n' "$kind" "$id"
      return 0
    fi
  done

  for row in "${rows[@]}"; do
    IFS=$'\t' read -r kind id label <<<"$row"
    if [[ ${id,,} == "${token,,}" || ${label,,} == "${token,,}" ]]; then
      printf '%s:%s\n' "$kind" "$id"
      return 0
    fi
  done

  return 1
}

preinstalls_parse_selection() {
  local token resolved

  PREINSTALL_ALL=0
  PREINSTALL_SELECTION=()

  if (( $# == 0 )); then
    return 0
  fi

  if [[ $1 == --all ]]; then
    PREINSTALL_ALL=1
    return 0
  fi

  for token in "$@"; do
    if [[ $token == --all ]]; then
      PREINSTALL_ALL=1
      PREINSTALL_SELECTION=()
      return 0
    fi

    resolved=$(preinstalls_resolve_token "$token") || {
      echo "Unknown preinstall: $token" >&2
      return 1
    }

    PREINSTALL_SELECTION+=("$resolved")
  done
}

preinstalls_pick() {
  local mode=$1 header=$2 kind id label row
  local -a rows=() selected=()

  while IFS=$'\t' read -r kind id label; do
    row=$(preinstalls_picker_row "$kind" "$id" "$label")
    rows+=("$row")
  done < <(preinstalls_ids_for_mode "$mode")

  if (( ${#rows[@]} == 0 )); then
    return 0
  fi

  mapfile -t selected < <(printf '%s\n' "${rows[@]}" | gum choose --no-limit --header "$header" --height 20 --label-delimiter='|') || return 1

  PREINSTALL_SELECTION=("${selected[@]}")
}

preinstalls_remove_desktop() {
  local name=$1
  local desktop="$HOME/.local/share/applications/$name.desktop"
  local icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
  local old_icon_dir="$HOME/.local/share/applications/icons"
  local icon_name

  icon_name=$(preinstalls_icon_name "$name")
  rm -f "$desktop"
  rm -f "$icon_dir/$icon_name.png" "$icon_dir/$name.png" "$old_icon_dir/$name.png"
}

preinstalls_install_desktop() {
  local name=$1
  local source="$OMARCHY_PATH/applications/$name.desktop"

  mkdir -p "$HOME/.local/share/applications" || return 1
  cp "$source" "$HOME/.local/share/applications/"
}

preinstalls_refresh_desktop_database() {
  local app_dir=$HOME/.local/share/applications

  if omarchy-cmd-present update-desktop-database; then
    update-desktop-database "$app_dir" &>/dev/null || true
  fi
}

preinstalls_install_agent() {
  local id=$1 record command label mise extra

  record=$(preinstalls_agent_record "$id") || return 1
  IFS='|' read -r command label mise extra <<<"$record"
  # shellcheck disable=SC2086
  omarchy-mise-install $mise
}

preinstalls_remove_agent() {
  local id=$1 record command label mise extra file

  record=$(preinstalls_agent_record "$id") || return 1
  IFS='|' read -r command label mise extra <<<"$record"
  rm -f "$HOME/.local/bin/$command"
  for file in $extra; do
    rm -f "$HOME/.local/bin/$file"
  done
}

preinstalls_apply_install() {
  local -a packages=() ids=("$@")
  local spec kind id desktop_changed=0

  for spec in "${ids[@]}"; do
    kind=${spec%%:*}
    id=${spec#*:}

    case $kind in
    pkg)
      packages+=("$id")
      ;;
    webapp | tui)
      echo "Restoring $id..."
      preinstalls_install_desktop "$id" || return 1
      desktop_changed=1
      ;;
    agent)
      echo "Restoring $id..."
      preinstalls_install_agent "$id" || return 1
      ;;
    *)
      echo "Unknown preinstall: $spec" >&2
      return 1
      ;;
    esac
  done

  if (( desktop_changed )); then
    preinstalls_refresh_desktop_database
  fi

  if (( ${#packages[@]} > 0 )); then
    omarchy-pkg-add "${packages[@]}" || return 1
  fi
}

preinstalls_apply_remove() {
  local -a packages=() ids=("$@")
  local spec kind id desktop_changed=0

  for spec in "${ids[@]}"; do
    kind=${spec%%:*}
    id=${spec#*:}

    case $kind in
    pkg)
      packages+=("$id")
      ;;
    webapp | tui)
      echo "Removing $id..."
      preinstalls_remove_desktop "$id"
      desktop_changed=1
      ;;
    agent)
      echo "Removing $id..."
      preinstalls_remove_agent "$id" || return 1
      ;;
    *)
      echo "Unknown preinstall: $spec" >&2
      return 1
      ;;
    esac
  done

  if (( desktop_changed )); then
    preinstalls_refresh_desktop_database
  fi

  if (( ${#packages[@]} > 0 )); then
    omarchy-pkg-drop "${packages[@]}" || return 1
  fi
}

preinstalls_selection_ids() {
  local mode=$1 kind id label

  if (( PREINSTALL_ALL )); then
    while IFS=$'\t' read -r kind id label; do
      printf '%s:%s\n' "$kind" "$id"
    done < <(preinstalls_catalog)
    return
  fi

  if (( ${#PREINSTALL_SELECTION[@]} > 0 )); then
    printf '%s\n' "${PREINSTALL_SELECTION[@]}"
    return
  fi
}

preinstalls_offered_specs() {
  local mode=$1 kind id label

  while IFS=$'\t' read -r kind id label; do
    printf '%s:%s\n' "$kind" "$id"
  done < <(preinstalls_ids_for_mode "$mode")
}

preinstalls_selection_covers() {
  local -a selected=() required=()
  local spec found chosen

  if (( $# == 0 )); then
    return 1
  fi

  while IFS= read -r spec; do
    required+=("$spec")
  done

  selected=("$@")
  (( ${#required[@]} > 0 )) || return 1

  for spec in "${required[@]}"; do
    found=0
    for chosen in "${selected[@]}"; do
      if [[ $chosen == "$spec" ]]; then
        found=1
        break
      fi
    done
    (( found )) || return 1
  done
}

preinstalls_run_install() {
  local -a ids=() offered=()

  preinstalls_parse_selection "$@" || return 1

  if (( PREINSTALL_ALL )); then
    echo -e "Restoring preinstalled Omarchy applications...\n"

    # Recreates the shipped .desktop launchers (web apps and TUIs) and the mise stubs
    # that back claude, gh, opencode, and the rest of the agents
    omarchy-refresh-applications

    if ! omarchy-pkg-add "${PREINSTALL_PACKAGES[@]}"; then
      echo -e "\nPreinstalls are still marked as removed. Fix the errors above and try again."
      return 1
    fi

    rm -f "$HOME/.local/state/omarchy/preinstalls-removed"
    hyprctl reload
    return 0
  fi

  mapfile -t offered < <(preinstalls_offered_specs install)

  if (( $# == 0 )); then
    preinstalls_pick install "Select preinstalls to restore (space to toggle, return to confirm)" || return 0
  fi

  mapfile -t ids < <(preinstalls_selection_ids install)
  if (( ${#ids[@]} == 0 )); then
    echo "Nothing to restore."
    return 0
  fi

  echo -e "Restoring selected preinstalls...\n"
  preinstalls_apply_install "${ids[@]}" || return 1

  if printf '%s\n' "${offered[@]}" | preinstalls_selection_covers "${ids[@]}"; then
    rm -f "$HOME/.local/state/omarchy/preinstalls-removed"
  fi

  hyprctl reload
}

preinstalls_run_remove() {
  local -a ids=() offered=()

  preinstalls_parse_selection "$@" || return 1

  mapfile -t offered < <(preinstalls_offered_specs remove)

  if (( $# == 0 )); then
    preinstalls_pick remove "Select preinstalls to remove (space to toggle, return to confirm)" || return 0
  fi

  mapfile -t ids < <(preinstalls_selection_ids remove)
  if (( ${#ids[@]} == 0 )); then
    echo "Nothing to remove."
    return 0
  fi

  echo -e "Removing selected preinstalls...\n"
  preinstalls_apply_remove "${ids[@]}" || return 1

  mkdir -p "$HOME/.local/state/omarchy"
  if (( PREINSTALL_ALL )) || printf '%s\n' "${offered[@]}" | preinstalls_selection_covers "${ids[@]}"; then
    touch "$HOME/.local/state/omarchy/preinstalls-removed"
  fi

  hyprctl reload
}
