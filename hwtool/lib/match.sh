#!/bin/bash
#
# hwtool/lib/match.sh
#
# Rule matching. Each rule file is sourced in a subshell and the
# match_type/match_value are checked against the global HW_* variables
# populated by detect.sh. Matching rules contribute their depends/services/
# groups/kernel_params to the action queue.
#
# Action queue (populated by collect_actions):
#   ACTION_DEPENDS          array (deduplicated)
#   ACTION_AUR_DEPENDS      array (deduplicated)
#   ACTION_SERVICES         array (deduplicated)
#   ACTION_GROUPS           array (deduplicated)
#   ACTION_KERNEL_PARAMS    array (deduplicated)
#   ACTION_SERVICES_USER    array (deduplicated)
#   ACTION_POST_INSTALL     array (rule_id<TAB>function-body) — preserves order
#   ACTION_REBOOT_REASONS   array (rule_id<TAB>reason) — preserves order
#   ACTION_REQUIRED_KERNELS array (rule_id<TAB>kernel-pkg) — preserves order
#   ACTION_MATCHED_RULES    array (rule IDs that matched)
#   NEEDS_KERNEL_HEADERS    flag (1 if any rule needs auto-detected headers)
#

[[ -n "$HWTOOL_MATCH_SH" ]] && return
HWTOOL_MATCH_SH=1

# Reset action queues to empty.
match_reset_actions() {
    ACTION_DEPENDS=()
    ACTION_AUR_DEPENDS=()
    ACTION_SERVICES=()
    ACTION_SERVICES_USER=()
    ACTION_GROUPS=()
    ACTION_KERNEL_PARAMS=()
    ACTION_POST_INSTALL=()
    ACTION_REBOOT_REASONS=()
    ACTION_REQUIRED_KERNELS=()
    ACTION_MATCHED_RULES=()
    NEEDS_KERNEL_HEADERS=0
}

# Append items from $2... to array named by $1, skipping duplicates.
_append_unique() {
    local arr_name=$1
    shift
    local -n arr=$arr_name
    local item existing found
    for item in "$@"; do
        [[ -z "$item" ]] && continue
        found=0
        for existing in "${arr[@]}"; do
            [[ "$existing" == "$item" ]] && { found=1; break; }
        done
        (( found )) || arr+=("$item")
    done
}

# Test whether the currently-sourced rule (rulename, match_type, match_value, ...)
# applies to the detected hardware. Returns 0 (match) or 1 (no match).
#
# Must be called inside the subshell that sourced the rule, so it sees
# $match_type and $match_value as locals.
rule_matches() {
    local mt=$match_type
    local mv

    case "$mt" in
        pci_vendor)
            # Match if any HW_PCI_VENDOR_CLASS starts with this vendor
            for mv in "${HW_PCI_VENDOR_CLASS[@]}"; do
                [[ "$mv" == "${match_value}:"* ]] && return 0
            done
            return 1
            ;;

        pci_vendor_class)
            for mv in "${HW_PCI_VENDOR_CLASS[@]}"; do
                [[ "$mv" == "$match_value" ]] && return 0
            done
            return 1
            ;;

        cpu_vendor)
            [[ "$HW_CPU_VENDOR" == "$match_value" ]]
            ;;

        cpu_flag)
            for mv in "${HW_CPU_FLAGS[@]}"; do
                [[ "$mv" == "$match_value" ]] && return 0
            done
            return 1
            ;;

        dmi_vendor)
            [[ "$HW_DMI_VENDOR" == "$match_value" ]]
            ;;

        dmi_product_regex)
            [[ "$HW_DMI_PRODUCT" =~ $match_value ]]
            ;;

        chassis_type)
            [[ "$HW_CHASSIS_TYPE" == "$match_value" ]]
            ;;

        block_device)
            for mv in "${HW_BLOCK_DEVICES[@]}"; do
                [[ "$mv" == "${match_value}"* ]] && return 0
            done
            return 1
            ;;

        usb_vendor)
            for mv in "${HW_USB_VENDORS[@]}"; do
                [[ "$mv" == "$match_value" ]] && return 0
            done
            return 1
            ;;

        usb_vendor_any)
            # match_value here is an array
            local want
            for want in "${match_value[@]}"; do
                for mv in "${HW_USB_VENDORS[@]}"; do
                    [[ "$mv" == "$want" ]] && return 0
                done
            done
            return 1
            ;;

        usb_vidpid_any)
            # match_value is an array of "vvvv:pppp" strings; match if any
            # appears in HW_USB_VIDPID
            local want
            for want in "${match_value[@]}"; do
                for mv in "${HW_USB_VIDPID[@]}"; do
                    [[ "$mv" == "$want" ]] && return 0
                done
            done
            return 1
            ;;

        *)
            warning "Unknown match_type '%s' in rule %s" "$mt" "${rulename:-?}"
            return 1
            ;;
    esac
}

# Source one rule file in a subshell, check if it matches, and emit a
# tab-separated record on stdout if it does:
#
#   rulename|depends|aur|services|services_user|groups|kparams|post_install
#
# Subshell isolation is crucial: rules can define functions and variables
# Without polluting the parent shell, and one bad rule cannot break the run.
_evaluate_rule() {
    local rule_file=$1

    (
        set +e
        # Defaults so unset arrays don't error under strict mode
        rulename=""
        ruledesc=""
        match_type=""
        match_value=""
        depends=()
        aur_depends=()
        services=()
        services_user=()
        groups=()
        kernel_params=()
        requires_reboot=""
        needs_kernel_headers=false
        kernel=""

        # shellcheck disable=SC1090
        if ! source_safe "$rule_file" 2>/dev/null; then
            error "Failed to source rule: %s" "$rule_file"
            exit 2
        fi

        if [[ -z "$rulename" || -z "$match_type" ]]; then
            warning "Rule %s missing 'rulename' or 'match_type'; skipping" "$rule_file"
            exit 3
        fi

        if rule_matches; then
            # Capture post_install body if defined; base64 to survive
            # the line-based delimited format (function bodies are multiline)
            local post_body=""
            if declare -F post_install >/dev/null; then
                post_body=$(declare -f post_install | base64 -w0)
            fi

            # Base64 the reboot reason too — it's free-form text and could
            # contain pipes, quotes, or dashes that would break the format.
            local reboot_b64=""
            if [[ -n "$requires_reboot" ]]; then
                reboot_b64=$(printf '%s' "$requires_reboot" | base64 -w0)
            fi

            # Normalize the boolean: anything but "true" is false
            local needs_headers="false"
            if [[ "$needs_kernel_headers" == "true" ]]; then
                needs_headers="true"
            fi

            local IFS=,
            printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "$rulename" \
                "${depends[*]}" \
                "${aur_depends[*]}" \
                "${services[*]}" \
                "${services_user[*]}" \
                "${groups[*]}" \
                "${kernel_params[*]}" \
                "$post_body" \
                "$reboot_b64" \
                "$needs_headers" \
                "$kernel"
            exit 0
        fi
        exit 1
    )
}

# Iterate all rule files in a directory, collect actions from matching ones.
collect_actions() {
    local rules_dir=$1
    match_reset_actions

    local rule_file output rc
    local name_field deps_field aur_field svc_field svc_user_field
    local grp_field kp_field post_field reboot_field headers_field kernel_field
    while IFS= read -r -d '' rule_file; do
        # Capture stdout and rc; tolerate non-zero (non-match is rc=1)
        output=$(_evaluate_rule "$rule_file") && rc=0 || rc=$?
        case $rc in
            0)
                IFS='|' read -r name_field deps_field aur_field svc_field \
                                 svc_user_field grp_field kp_field \
                                 post_field reboot_field headers_field \
                                 kernel_field <<<"$output"
                ACTION_MATCHED_RULES+=("$name_field")

                local IFS=,
                # shellcheck disable=SC2206
                local d=( $deps_field ) a=( $aur_field ) s=( $svc_field )
                # shellcheck disable=SC2206
                local su=( $svc_user_field ) g=( $grp_field ) k=( $kp_field )
                unset IFS

                _append_unique ACTION_DEPENDS "${d[@]}"
                _append_unique ACTION_AUR_DEPENDS "${a[@]}"
                _append_unique ACTION_SERVICES "${s[@]}"
                _append_unique ACTION_SERVICES_USER "${su[@]}"
                _append_unique ACTION_GROUPS "${g[@]}"
                _append_unique ACTION_KERNEL_PARAMS "${k[@]}"

                if [[ -n "$post_field" ]]; then
                    ACTION_POST_INSTALL+=("${name_field}"$'\t'"$post_field")
                fi
                if [[ -n "$reboot_field" ]]; then
                    local reason
                    reason=$(printf '%s' "$reboot_field" | base64 -d 2>/dev/null)
                    ACTION_REBOOT_REASONS+=("${name_field}"$'\t'"$reason")
                fi
                if [[ "$headers_field" == "true" ]]; then
                    NEEDS_KERNEL_HEADERS=1
                fi
                if [[ -n "$kernel_field" ]]; then
                    # Track as rulename<TAB>kernel — we need both for the
                    # conflict check's error message
                    ACTION_REQUIRED_KERNELS+=("${name_field}"$'\t'"$kernel_field")
                fi
                ;;
            1) ;;  # no match, normal
            *) ;;  # error, already reported by subshell
        esac
    done < <(find "$rules_dir" -maxdepth 1 -type f -name '*.rule' -print0 | sort -z)

    # Resolve `kernel=` requirements before generic header detection,
    # because a required kernel implies adding both the kernel package
    # itself and its headers — the generic detector might miss the kernel
    # if it's not yet installed.
    if (( ${#ACTION_REQUIRED_KERNELS[@]} )); then
        if ! _check_kernel_conflict; then
            return 1
        fi
        # Single distinct kernel: extract it and add to depends
        local required_kernel
        required_kernel=$(_unique_required_kernel)
        _append_unique ACTION_DEPENDS "$required_kernel"
        _append_unique ACTION_DEPENDS "${required_kernel}-headers"
    fi

    # If any matched rule needs kernel headers, expand to the right
    # *-headers package(s) for whatever kernel(s) the user has installed.
    if (( NEEDS_KERNEL_HEADERS )); then
        local pkg
        for pkg in $(_resolve_kernel_headers); do
            _append_unique ACTION_DEPENDS "$pkg"
        done
    fi
}

# Check that all rules requesting a specific kernel agree on which one.
# Returns 0 if there's no conflict (zero, one, or many rules but all
# requesting the same kernel). Returns 1 and prints an error if 2+
# distinct kernels are requested.
_check_kernel_conflict() {
    declare -A kernel_to_rules=()
    local entry rule kernel
    for entry in "${ACTION_REQUIRED_KERNELS[@]}"; do
        rule=${entry%%$'\t'*}
        kernel=${entry#*$'\t'}
        kernel_to_rules[$kernel]+="${rule} "
    done

    if (( ${#kernel_to_rules[@]} <= 1 )); then
        return 0
    fi

    # 2+ distinct kernels requested. Report each one and which rules want it.
    error "Conflicting kernel requirements from matched rules:"
    for kernel in "${!kernel_to_rules[@]}"; do
        plain "  %s required by: %s" "$kernel" "${kernel_to_rules[$kernel]% }"
    done
    plain "Resolve by editing rules so they agree, or by skipping conflicting hardware."
    return 1
}

# Return the single distinct kernel value from ACTION_REQUIRED_KERNELS.
# Caller must have already called _check_kernel_conflict and verified
# success — this function does no validation.
_unique_required_kernel() {
    local entry
    for entry in "${ACTION_REQUIRED_KERNELS[@]}"; do
        echo "${entry#*$'\t'}"
        return
    done
}

# List the *-headers packages corresponding to the kernels that are
# actually installed on the system.
#
# Detection strategy: every kernel package owns `/usr/lib/modules/<ver>/vmlinuz`.
# We enumerate those vmlinuz files, ask pacman who owns each one, and
# strip duplicates. This works for upstream Arch kernels (linux, linux-lts,
# linux-zen, linux-hardened, linux-rt, linux-rt-lts), Omarchy's custom
# kernels (e.g. linux-ptl-audio for Panther Lake), and any third-party
# kernel that follows the standard /usr/lib/modules layout — which is
# essentially all of them, because mkinitcpio and dracut both depend on it.
#
# For each detected kernel P, the headers package is conventionally named
# P-headers. We verify it actually exists in the sync DB before adding it,
# so a kernel without packaged headers (rare, but possible) doesn't cause
# a failed pacman install down the line.
#
# Fallbacks:
#  - No pacman: emit "linux-headers" as the safe default
#  - pacman present but no kernels found: emit "linux-headers" (something
#    is wrong with the system, but adding the standard headers is harmless)
_resolve_kernel_headers() {
    if ! command -v pacman >/dev/null 2>&1; then
        echo "linux-headers"
        return
    fi

    local vmlinuz kernels=()
    # Enumerate vmlinuz files. shopt -s nullglob so an empty match
    # produces an empty array rather than the literal glob string.
    shopt -s nullglob
    local vmlinuzes=(/usr/lib/modules/*/vmlinuz)
    shopt -u nullglob

    for vmlinuz in "${vmlinuzes[@]}"; do
        local owner
        # pacman -Qoq prints just the package name owning the path
        owner=$(pacman -Qoq "$vmlinuz" 2>/dev/null) || continue
        kernels+=("$owner")
    done

    # Dedupe (a kernel package owns just one vmlinuz, but be safe)
    local kernel
    declare -A seen=()
    local unique=()
    for kernel in "${kernels[@]}"; do
        [[ -z "${seen[$kernel]:-}" ]] || continue
        seen[$kernel]=1
        unique+=("$kernel")
    done

    if (( ${#unique[@]} == 0 )); then
        echo "linux-headers"
        return
    fi

    # For each kernel, check that <name>-headers is a real package.
    # `pacman -Si` queries the sync DB without needing it installed.
    for kernel in "${unique[@]}"; do
        local headers="${kernel}-headers"
        if pacman -Si "$headers" >/dev/null 2>&1; then
            echo "$headers"
        fi
    done
}

# Print a human-readable summary of the action queue
match_show_plan() {
    msg "Plan summary"
    msg2 "Matched rules (%d): %s" \
        "${#ACTION_MATCHED_RULES[@]}" "${ACTION_MATCHED_RULES[*]:-none}"

    if (( ${#ACTION_DEPENDS[@]} )); then
        msg2 "Packages to install (%d):" "${#ACTION_DEPENDS[@]}"
        plain "  %s" "${ACTION_DEPENDS[*]}"
    fi
    if (( ${#ACTION_AUR_DEPENDS[@]} )); then
        msg2 "AUR packages to install (%d):" "${#ACTION_AUR_DEPENDS[@]}"
        plain "  %s" "${ACTION_AUR_DEPENDS[*]}"
    fi
    if (( ${#ACTION_SERVICES[@]} )); then
        msg2 "System services to enable (%d):" "${#ACTION_SERVICES[@]}"
        plain "  %s" "${ACTION_SERVICES[*]}"
    fi
    if (( ${#ACTION_SERVICES_USER[@]} )); then
        msg2 "User services to enable (%d):" "${#ACTION_SERVICES_USER[@]}"
        plain "  %s" "${ACTION_SERVICES_USER[*]}"
    fi
    if (( ${#ACTION_GROUPS[@]} )); then
        msg2 "Groups to add user to (%d):" "${#ACTION_GROUPS[@]}"
        plain "  %s" "${ACTION_GROUPS[*]}"
    fi
    if (( ${#ACTION_KERNEL_PARAMS[@]} )); then
        msg2 "Kernel params to add (%d):" "${#ACTION_KERNEL_PARAMS[@]}"
        plain "  %s" "${ACTION_KERNEL_PARAMS[*]}"
    fi
    if (( ${#ACTION_POST_INSTALL[@]} )); then
        msg2 "Post-install hooks (%d):" "${#ACTION_POST_INSTALL[@]}"
        local entry rid
        for entry in "${ACTION_POST_INSTALL[@]}"; do
            rid=${entry%%$'\t'*}
            plain "  from %s" "$rid"
        done
    fi
    if (( ${#ACTION_REBOOT_REASONS[@]} )); then
        msg2 "Reboot required (%d reason(s)):" "${#ACTION_REBOOT_REASONS[@]}"
        local entry rid reason
        for entry in "${ACTION_REBOOT_REASONS[@]}"; do
            rid=${entry%%$'\t'*}
            reason=${entry#*$'\t'}
            plain "  %s: %s" "$rid" "$reason"
        done
    fi
}
