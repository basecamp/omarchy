# Overwrite parts of the omarchy-menu with user-specific submenus.
# See $OMARCHY_PATH/bin/omarchy-menu for functions that can be overwritten.
#
# WARNING: Overwritten functions will obviously not be updated when Omarchy changes.
#
# Example adding suspend to the system menu:
#
# show_system_menu() {
#   case $(menu "System" "  Lock\n󱄄  Screensaver\n󰒲  Suspend\n󰜉  Restart\n󰐥  Shutdown") in
#   *Lock*) omarchy-lock-screen ;;
#   *Screensaver*) omarchy-launch-screensaver force ;;
#   *Suspend*) systemctl suspend ;;
#   *Restart*) omarchy-cmd-reboot ;;
#   *Shutdown*) omarchy-cmd-shutdown ;;
#   *) back_to show_main_menu ;;
#   esac
# }
