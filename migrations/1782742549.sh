# Omarchy migration — apply the T2 synchronous device-suspend fix to existing
# installs. At submission time, RENAME this file to a fresh unix timestamp that
# is greater than the newest existing migration, e.g.:
#
#     mv migration.sh "migrations/$(date +%s).sh"
#
# (Verify it sorts after the current latest in migrations/.)

echo "Fix intermittent suspend hang on T2 MacBooks (force synchronous device suspend)"

source $OMARCHY_PATH/install/config/hardware/apple/fix-suspend-async.sh
