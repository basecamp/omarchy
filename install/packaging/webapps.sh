set -euo pipefail

webapps_data_file="$OMARCHY_PATH/install/packaging/webapps-data.sh"

if [[ ! -f "$webapps_data_file" ]]; then
  echo "Missing webapps data file: $webapps_data_file" >&2
  exit 1
fi

source "$webapps_data_file"

for webapp in "${OMARCHY_PREINSTALLED_WEBAPPS[@]}"; do
  IFS="|" read -r app_name app_url icon_ref custom_exec mime_types <<< "$webapp"

  args=("$app_name" "$app_url" "$icon_ref")

  if [[ -n $custom_exec || -n $mime_types ]]; then
    args+=("$custom_exec")
  fi

  if [[ -n $mime_types ]]; then
    args+=("$mime_types")
  fi

  omarchy-webapp-install "${args[@]}"
done
