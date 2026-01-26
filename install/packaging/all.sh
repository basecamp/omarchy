run_logged $OMARCHY_INSTALL/packaging/base.sh
run_logged $OMARCHY_INSTALL/packaging/fonts.sh

# Skip nvim setup for lite (nvim is in +dev addon)
if [[ "${OMARCHY_EDITION:-full}" != "lite" ]]; then
  run_logged $OMARCHY_INSTALL/packaging/nvim.sh
fi

run_logged $OMARCHY_INSTALL/packaging/icons.sh

# Use lite webapps (none) or full webapps based on edition
if [[ "${OMARCHY_EDITION:-full}" == "lite" ]]; then
  run_logged $OMARCHY_INSTALL/packaging/webapps-lite.sh
else
  run_logged $OMARCHY_INSTALL/packaging/webapps.sh
fi

run_logged $OMARCHY_INSTALL/packaging/tuis.sh
