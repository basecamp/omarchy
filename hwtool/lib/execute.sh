#!/bin/bash
#
# hwtool/lib/execute.sh
#
# Wrappers around omarchy-pkg-add, omarchy-pkg-aur-add, systemctl, gpasswd.
# All respect DRY_RUN — when set, commands are printed but not executed.
#

[[ -n "$HWTOOL_EXECUTE_SH" ]] && return
HWTOOL_EXECUTE_SH=1

# Print or run a command depending on DRY_RUN
_run() {
    if (( DRY_RUN )); then
        plain "  \$ %s" "$*"
    else
        "$@"
    fi
}

# omarchy-pkg-add and omarchy-pkg-aur-add are Omarchy's official package
# install commands. They wrap pacman / yay respectively, handle sudo,
# and play nicely with Omarchy's package channels (OPR + AUR).
#
# We require these commands rather than falling back to pacman, because
# hwtool is intended to ship as part of Omarchy. If they're missing,
# either Omarchy isn't installed or these tools have been renamed
# upstream — both worth surfacing as an error rather than silently
# bypassing.

execute_install_packages() {
    (( ${#ACTION_DEPENDS[@]} )) || return 0
    if (( ! DRY_RUN )) && ! command -v omarchy-pkg-add >/dev/null 2>&1; then
        error "omarchy-pkg-add not found; cannot install %d package(s)" \
            "${#ACTION_DEPENDS[@]}"
        return 1
    fi
    msg "Installing official packages via omarchy-pkg-add"
    _run omarchy-pkg-add "${ACTION_DEPENDS[@]}"
}

execute_install_aur() {
    (( ${#ACTION_AUR_DEPENDS[@]} )) || return 0
    if (( ! DRY_RUN )) && ! command -v omarchy-pkg-aur-add >/dev/null 2>&1; then
        warning "omarchy-pkg-aur-add not found; skipping %d AUR package(s): %s" \
            "${#ACTION_AUR_DEPENDS[@]}" "${ACTION_AUR_DEPENDS[*]}"
        return 0
    fi
    msg "Installing AUR packages via omarchy-pkg-aur-add"
    _run omarchy-pkg-aur-add "${ACTION_AUR_DEPENDS[@]}"
}

execute_enable_services() {
    (( ${#ACTION_SERVICES[@]} )) || return 0
    msg "Enabling systemd services (system)"
    local svc
    for svc in "${ACTION_SERVICES[@]}"; do
        _run sudo systemctl enable --now "$svc"
    done
}

# Enable systemd --user units for the real (non-root) user.
#
# When hwtool runs under sudo, $USER is root but $SUDO_USER is the real
# user. systemctl --user needs to talk to that user's session bus, so we
# drop privileges with sudo -u and set XDG_RUNTIME_DIR explicitly (it's
# normally per-session and not inherited across sudo).
#
# Caveat: this requires the target user to have an active session, or
# linger enabled (loginctl enable-linger). If neither is true, the
# --now will fail to start the unit but enable will still succeed,
# and the unit will start on next login.
execute_enable_user_services() {
    (( ${#ACTION_SERVICES_USER[@]} )) || return 0

    local target_user=${SUDO_USER:-${USER:-$(id -un)}}
    if [[ "$target_user" == "root" ]]; then
        warning "Cannot enable user services as root; skipping %d unit(s): %s" \
            "${#ACTION_SERVICES_USER[@]}" "${ACTION_SERVICES_USER[*]}"
        return 0
    fi

    msg "Enabling systemd services (user: %s)" "$target_user"
    local target_uid
    target_uid=$(id -u "$target_user" 2>/dev/null) || {
        warning "Could not resolve uid for %s; skipping user services" "$target_user"
        return 0
    }

    local svc
    for svc in "${ACTION_SERVICES_USER[@]}"; do
        if [[ -n "$SUDO_USER" ]]; then
            # We're root via sudo: drop down to the real user
            _run sudo -u "$target_user" \
                XDG_RUNTIME_DIR="/run/user/$target_uid" \
                systemctl --user enable --now "$svc"
        else
            # We're already running as the user
            _run systemctl --user enable --now "$svc"
        fi
    done
}

execute_add_groups() {
    (( ${#ACTION_GROUPS[@]} )) || return 0
    local target_user=${SUDO_USER:-${USER:-$(id -un)}}
    msg "Adding %s to groups" "$target_user"
    local g
    for g in "${ACTION_GROUPS[@]}"; do
        if (( ! DRY_RUN )); then
            if ! getent group "$g" >/dev/null; then
                warning "Group '%s' does not exist; skipping" "$g"
                continue
            fi
            if id -nG "$target_user" | tr ' ' '\n' | grep -qx "$g"; then
                msg2 "%s already in %s" "$target_user" "$g"
                continue
            fi
        fi
        _run sudo gpasswd -a "$target_user" "$g"
    done
}

execute_kernel_params() {
    (( ${#ACTION_KERNEL_PARAMS[@]} )) || return 0
    warning "Kernel parameter modification not yet implemented"
    msg2 "Would add: %s" "${ACTION_KERNEL_PARAMS[*]}"
    msg2 "Add these manually to your bootloader config (e.g. /boot/loader/entries/*.conf)"
}

execute_post_install() {
    (( ${#ACTION_POST_INSTALL[@]} )) || return 0
    msg "Running post-install hooks"
    local entry rid body decoded
    for entry in "${ACTION_POST_INSTALL[@]}"; do
        rid=${entry%%$'\t'*}
        body=${entry#*$'\t'}
        decoded=$(printf '%s' "$body" | base64 -d 2>/dev/null) || {
            warning "Failed to decode post_install for %s" "$rid"
            continue
        }
        msg2 "Hook from %s" "$rid"
        if (( DRY_RUN )); then
            plain "  (dry-run) would execute post_install() from %s" "$rid"
        else
            eval "$decoded"
            post_install || warning "post_install for %s exited non-zero" "$rid"
            unset -f post_install
        fi
    done
}

# Mark the system as needing a reboot via Omarchy's state mechanism.
# This sets a flag that Omarchy's UI/notifications can pick up to nudge
# the user to reboot at a convenient time. We don't trigger a reboot
# ourselves — that's intrusive and the user may have other work in
# progress.
execute_mark_reboot_required() {
    (( ${#ACTION_REBOOT_REASONS[@]} )) || return 0
    if (( ! DRY_RUN )) && ! command -v omarchy-state >/dev/null 2>&1; then
        warning "omarchy-state not found; cannot mark reboot-required state"
        return 0
    fi
    msg "Marking reboot-required state"
    _run omarchy-state set reboot-required
}

execute_all() {
    execute_install_packages
    execute_install_aur
    execute_enable_services
    execute_enable_user_services
    execute_add_groups
    execute_kernel_params
    execute_post_install
    execute_mark_reboot_required
}
