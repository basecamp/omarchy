echo "Installing PostgreSQL and setting it up"

DATA_DIR=/var/lib/postgres/data
PG_PRIMARY_USER=${SUDO_USER:-$USER}   # Non-root account
PG_SERVICE=postgresql

if ! pacman -Qi postgresql &>/dev/null; then
  echo "Installing PostgreSQL..."
  sudo pacman -Sy --needed --noconfirm postgresql
else
  echo "PostgreSQL package already installed."
fi

cluster_initialised() { [[ -f "$DATA_DIR/PG_VERSION" ]]; }
service_runs()       { sudo systemctl is-active --quiet "$PG_SERVICE"; }

if cluster_initialised; then
  echo "Cluster already initialised."
else
  echo "Cluster not detected; checking service..."
  if service_runs; then
    echo "Service starts—cluster exists. Skipping initdb."
  else
    if [[ -d $DATA_DIR ]] && [[ -n $(sudo ls -A "$DATA_DIR") ]]; then
      echo "ERROR: $DATA_DIR exists and is non-empty but not a valid cluster."
      echo "Remove or empty the directory, then re-run this script."
      exit 1
    fi
    echo "Running initdb..."
    sudo -iu postgres initdb -D "$DATA_DIR" --locale en_US.UTF-8
  fi
fi

echo "Enabling and starting $PG_SERVICE.service..."
sudo systemctl enable --now "$PG_SERVICE"
sudo systemctl --no-pager --lines=0 status "$PG_SERVICE"

echo "Checking PostgreSQL role '$PG_PRIMARY_USER'..."
if ! sudo -iu postgres psql -qtAc "SELECT 1 FROM pg_roles WHERE rolname='${PG_PRIMARY_USER}'" | grep -q 1; then
  sudo -iu postgres createuser --superuser "$PG_PRIMARY_USER"
  echo "Role '$PG_PRIMARY_USER' created."
else
  echo "Role '$PG_PRIMARY_USER' already exists; no action needed."
fi

echo -e "\nSetup complete. Test with:\n  psql -U \"$PG_PRIMARY_USER\"\n"
