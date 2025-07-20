#!/bin/bash

MIGRATION_LOG="$HOME/.local/share/omarchy/migrations.log"
MIGRATION_DIR="$HOME/.local/share/omarchy/migrations"
SYSTEM_START_DATE=$(stat -c %W / 2>/dev/null || echo "0")

# Ensure config directory exists
mkdir -p "$(dirname "$MIGRATION_LOG")"

# Get list of completed migration timestamps
get_completed_migrations() {
  [[ -f "$MIGRATION_LOG" ]] && cat "$MIGRATION_LOG" || true
}

# Check if a specific migration has been completed
is_migration_completed() {
  local timestamp="$1"
  [[ -f "$MIGRATION_LOG" ]] && grep -q "^${timestamp}$" "$MIGRATION_LOG" 2>/dev/null
}

# Mark a migration as completed
mark_migration_completed() {
  local timestamp="$1"
  echo "$timestamp" >>"$MIGRATION_LOG"
}

# Remove a migration from the completed log
remove_migration_completed() {
  local timestamp="$1"
  if [[ -f "$MIGRATION_LOG" ]]; then
    # Remove the line with this timestamp
    grep -v "^${timestamp}$" "$MIGRATION_LOG" >"${MIGRATION_LOG}.tmp" || true
    mv "${MIGRATION_LOG}.tmp" "$MIGRATION_LOG"
  fi
}

# Get list of pending migration files
get_pending_migrations() {
  for file in "$MIGRATION_DIR"/*.sh; do
    [[ ! -f "$file" ]] && continue

    local filename=$(basename "$file")
    local timestamp="${filename%%_*}"

    # If filename is just timestamp.sh (old format), extract it differently
    if [[ "$timestamp" == "$filename" ]]; then
      timestamp="${filename%.sh}"
    fi

    # Skip migrations older than system start date
    if [[ "$timestamp" -lt "$SYSTEM_START_DATE" ]]; then
      continue
    fi

    if ! is_migration_completed "$timestamp"; then
      echo "$file"
    fi
  done | sort
}

# Extract timestamp from migration filename
get_migration_timestamp() {
  local filename="$1"
  local timestamp="${filename%%_*}"

  # Handle old format (just timestamp.sh)
  if [[ "$timestamp" == "$filename" ]]; then
    timestamp="${filename%.sh}"
  fi

  echo "$timestamp"
}

# Extract description from migration filename
get_migration_description() {
  local filename="$1"
  local desc="${filename#*_}"

  # Handle old format (no description)
  if [[ "$desc" == "$filename" ]]; then
    echo "unnamed"
  else
    desc="${desc%.sh}"
    echo "${desc//_/ }"
  fi
}

# Migration helper functions
migration_success_msg() {
  echo -e "\e[32mMigration completed successfully\e[0m"
}

migration_failure_msg() {
  echo -e "\e[31mMigration failed!\e[0m"
}

# Core migration runner - handles running a single migration file
run_single_migration() {
  local migration_file="$1"
  local allow_failure="$2" # true if we should prompt on failure, false to exit immediately

  local filename=$(basename "$migration_file")
  local timestamp=$(get_migration_timestamp "$filename")
  local description=$(get_migration_description "$filename")

  echo -e "\nRunning: ${description} (${timestamp})"

  # Remove from log before running (in case it's a re-run)
  remove_migration_completed "$timestamp"

  if (source "$migration_file"); then
    mark_migration_completed "$timestamp"
    migration_success_msg
    return 0
  else
    migration_failure_msg
    if [[ "$allow_failure" == "true" ]]; then
      if ! gum confirm "Migration failed. Continue with remaining migrations?"; then
        echo "Migration run aborted! No further migrations will run."
        exit 1
      fi
    else
      exit 1
    fi
    return 1
  fi
}

# Migration status
migration_status() {
  local completed_count=0
  local total_count=0
  local pending_count=0
  local pre_system_count=0

  for file in "$MIGRATION_DIR"/*.sh; do
    [[ ! -f "$file" ]] && continue

    local filename=$(basename "$file")
    local timestamp=$(get_migration_timestamp "$filename")

    if [[ "$timestamp" -lt "$SYSTEM_START_DATE" ]]; then
      ((pre_system_count++))
      continue
    fi

    ((total_count++))

    if is_migration_completed "$timestamp"; then
      ((completed_count++))
    else
      ((pending_count++))
    fi
  done

  echo "Migrations: $completed_count completed, $pending_count pending"
  if [[ "$pre_system_count" -gt 0 ]]; then
    echo "($pre_system_count pre-system migrations excluded)"
  fi
}

# Create new migration
migration_create() {
  echo -n "Description (use_underscores): "
  read desc

  timestamp=$(date +%s)

  if [[ -n "$desc" ]]; then
    filename="${timestamp}_${desc}.sh"
  else
    filename="${timestamp}.sh"
  fi

  filepath="$MIGRATION_DIR/$filename"

  cat >"$filepath" <<'EOF'
#!/bin/bash

echo "Running migration..."
# yay -Rns --noconfirm PACKAGE
# yay -S --noconfirm --needed PACKAGE

EOF

  ${EDITOR:-nvim} "$filepath"

  echo "Created: $filename"
}

# List all migrations
migration_list() {
  for file in $(ls "$MIGRATION_DIR"/*.sh 2>/dev/null | sort); do
    [[ ! -f "$file" ]] && continue

    filename=$(basename "$file")
    timestamp=$(get_migration_timestamp "$filename")
    desc=$(get_migration_description "$filename")

    if [[ "$timestamp" -lt "$SYSTEM_START_DATE" ]]; then
      echo -e "\e[90m\uf05e\e[0m ${desc} (${timestamp}) [pre-system]"
    elif is_migration_completed "$timestamp"; then
      echo -e "\e[32m\uf00c\e[0m ${desc} (${timestamp})"
    else
      echo -e "\e[33m\uf254\e[0m ${desc} (${timestamp})"
    fi
  done
}

# Run pending migrations
migration_run_pending() {
  echo "Checking for migrations..."
  pending=$(get_pending_migrations)

  if [[ -n "$pending" ]]; then
    echo "Running migrations..."
    readarray -t migrations_array <<<"$pending"

    for migration in "${migrations_array[@]}"; do
      [[ -z "$migration" ]] && continue
      run_single_migration "$migration" "true"
    done
  else
    echo "No pending migrations."
  fi
}

# Run specific migration by timestamp
migration_run_specific() {
  specific_timestamp="$1"
  migration_file=""

  for file in "$MIGRATION_DIR"/*.sh; do
    [[ ! -f "$file" ]] && continue
    filename=$(basename "$file")
    timestamp=$(get_migration_timestamp "$filename")

    if [[ "$timestamp" == "$specific_timestamp" ]]; then
      migration_file="$file"
      break
    fi
  done

  if [[ -z "$migration_file" ]]; then
    echo "Error: No migration found with timestamp $specific_timestamp"
    return 1
  fi

  echo "Running specific migration:"
  run_single_migration "$migration_file" "false"
}

# Show selector for choosing a migration to run
migration_run_selector() {
  local migrations=()
  local timestamps=()

  for file in $(ls "$MIGRATION_DIR"/*.sh 2>/dev/null | sort -r); do
    [[ ! -f "$file" ]] && continue

    local filename=$(basename "$file")
    local timestamp=$(get_migration_timestamp "$filename")
    local desc=$(get_migration_description "$filename")

    # Skip migrations older than system start date
    if [[ "$timestamp" -lt "$SYSTEM_START_DATE" ]]; then
      continue
    fi

    local status=""
    if is_migration_completed "$timestamp"; then
      status="\uf00c"
    else
      status="\uf254"
    fi

    migrations+=("$(echo -e "$status") $desc ($timestamp)")
    timestamps+=("$timestamp")
  done

  local selected
  selected=$(printf "%s\n" "${migrations[@]}" | gum choose --header="Select migration to run") || return 1

  if [[ -n "$selected" ]]; then
    local selected_timestamp="${selected##*(}"
    selected_timestamp="${selected_timestamp%)*}"

    migration_run_specific "$selected_timestamp"
  fi
}

# Run ALL migrations (even completed ones)
migration_run_all() {
  echo "Re-running ALL migrations (from system start date)..."

  for file in $(ls "$MIGRATION_DIR"/*.sh 2>/dev/null | sort); do
    [[ ! -f "$file" ]] && continue

    local filename=$(basename "$file")
    local timestamp=$(get_migration_timestamp "$filename")

    # Skip migrations older than system start date
    if [[ "$timestamp" -lt "$SYSTEM_START_DATE" ]]; then
      continue
    fi

    run_single_migration "$file" "true"
  done
}

# Handle different migration run scenarios
migration_run_new() {
  case "$1" in
  "")
    migration_run_selector
    ;;
  "all")
    migration_run_all
    ;;
  *)
    migration_run_specific "$1"
    ;;
  esac
}
