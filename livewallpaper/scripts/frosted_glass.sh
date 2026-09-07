#!/usr/bin/env bash
#
# frosted_glass.sh <apply <pct 0..100>|remove|--check>
# ----------------------------------------------------
# REAL compositor blur for this app's translucent surfaces --
# CROSS-DISTRO HARDENED EDITION (Arch / Fedora / Debian / Ubuntu / NixOS).
#
# WHY: the QML scene never renders the wallpaper (mpvpaper owns it on its
# own wlr-layer-shell Background surface), so only the compositor can frost
# it behind translucent layer-shell windows. This helper enables Hyprland's
# real multi-pass blur and adds `blur` + `ignorealpha` layerrules for every
# namespace this app owns.
#
# SLIDER CONTRACT (v2.9.b inverse semantics -- keep in sync with Theme.qml's
# micaAlpha()/blurRadius): pct = round(uiBgOpacity * 100).
#   0.15 -> pct 15  -> blur size 12 (MAXIMUM blur, boot state)
#   1.00 -> pct 100 -> blur size 3  (weakest blur)
# CROSS-DISTRO GUARANTEES
#   * Arch/Hyprland .......... full hyprctl blur path.
#   * Fedora/SELinux ......... every hyprctl call is fault-tolerant; policy
#                              denials degrade to a logged safe no-op.
#   * Debian/Ubuntu Wayland .. no hardcoded paths; session auto-detected
#                              from $XDG_SESSION_TYPE/$WAYLAND_DISPLAY/
#                              $DISPLAY; unsupported compositors -> exit 0
#                              so the QML Process child never fails.
#   * NixOS (read-only) ...... writes ONLY to $XDG_STATE_HOME/$XDG_CACHE_HOME
#                              (or $HOME), last resort /tmp/livewallpaper-$UID.
#                              Never touches /etc or /nix/store.
# FAIL-SAFE LAYERS (the app UI can never be taken down by this script)
#   1. hyprctl missing           -> exit 0, one-line note.
#   2. wrong session/compositor  -> exit 0, one-line note.
#   3. SELinux/policy denial     -> per-call toleration; after 4 denials
#                                   switch to a safe compositor no-op.
#   4. interrupted apply         -> EXIT trap restores prior blur cfg.
#   5. unresolvable data home    -> /tmp fallback; every write guarded.
#   6. LW_FROST_DISABLED=1       -> admin/SELinux kill-switch, exit 0.
#
# Usage:
#   frosted_glass.sh apply 15    # pct = round(uiBgOpacity * 100)
#   frosted_glass.sh remove      # drop our rules, restore prior blur cfg
#   frosted_glass.sh --check     # machine-readable env probe (always 0)
#
# (The pre-hardening frosted_glass.sh.orig backup was deleted -- stale
# backup files were being copied into every install on every update.)
set -u

# --------------------------------------------------------------------------
# DYNAMIC PATHS -- XDG-aware, writable on every supported distro
# --------------------------------------------------------------------------
# Preference order: LW_STATE_DIR (test/admin override) -> $XDG_STATE_HOME ->
# ~/.local/state -> $XDG_CACHE_HOME -> ~/.cache -> /tmp/livewallpaper-$UID.
# Every access below is guarded so a read-only or missing dir can NEVER
# abort the script (immutable XDG pins on NixOS, systemd --user shells
# without $HOME, SELinux-restricted $HOME, ...).
resolve_state_dir() {
    local d="" home="${HOME:-}"
    if [ -n "${LW_STATE_DIR:-}" ]; then
        d="$LW_STATE_DIR"
    elif [ -n "${XDG_STATE_HOME:-}" ]; then
        d="$XDG_STATE_HOME/livewallpaper"
    elif [ -n "$home" ]; then
        d="$home/.local/state/livewallpaper"
    fi
    if [ -n "$d" ]; then
        mkdir -p "$d" 2>/dev/null || d=""
    fi
    if [ -z "$d" ] && [ -n "${XDG_CACHE_HOME:-}" ]; then
        d="$XDG_CACHE_HOME/livewallpaper"; mkdir -p "$d" 2>/dev/null || d=""
    fi
    if [ -z "$d" ] && [ -n "$home" ]; then
        d="$home/.cache/livewallpaper"; mkdir -p "$d" 2>/dev/null || d=""
    fi
    if [ -z "$d" ] || [ ! -w "$d" ] 2>/dev/null; then
        d="/tmp/livewallpaper-$(id -u 2>/dev/null || echo 0)"
        mkdir -p "$d" 2>/dev/null || true
    fi
    printf '%s' "$d"
}

STATE_DIR="$(resolve_state_dir)"
PREV_FILE="$STATE_DIR/hypr-blur-enabled.prev"

# Every layer-shell namespace this app owns (see each *Overlay/Panel's
# `WlrLayershell.namespace`). The Manager window is an opaque xdg
# FloatingWindow and needs no blur.
NAMESPACES=(
    "livewallpaper"
    "livewallpaper-musicdock"
    "livewallpaper-peaclockcavadock"
    "livewallpaper-trigger"
)

# --------------------------------------------------------------------------
# LOGGING -- status -> stdout (QML Process debug log); diag -> stderr.
# LW_DEBUG=1 turns on verbose tracing; default stderr stays quiet.
# --------------------------------------------------------------------------
log()     { printf 'frosted_glass: %s\n' "$*"; }
log_err() { printf 'frosted_glass: %s\n' "$*" >&2; }
dbg()     { if [ "${LW_DEBUG:-0}" = 1 ]; then printf 'frosted_glass[dbg]: %s\n' "$*" >&2; fi; }

# --------------------------------------------------------------------------
# SESSION & COMPOSITOR DETECTION (X11 / Wayland / headless conditional probe)
# --------------------------------------------------------------------------
# OS-family probe from /etc/os-release. LW_OS_RELEASE lets tests inject a
# synthetic file so the same probe is validated per target distro.
detect_os() {
    local rel="${LW_OS_RELEASE:-/etc/os-release}" id=""
    if [ -r "$rel" ]; then
        id="$(sed -n 's/^ID=//p' "$rel" | tr -d '"' | head -1)"
    fi
    printf '%s' "${id:-unknown}"
}

# Protocol detection. Wayland wins over X11; these vars are exported by the
# display manager / compositor on every target distro, including Ubuntu's
# and Debian's Wayland safe-launch sessions.
detect_session() {
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then printf 'wayland'; return 0; fi
    case "${XDG_SESSION_TYPE:-}" in
        wayland) printf 'wayland'; return 0 ;;
    esac
    if [ -n "${DISPLAY:-}" ]; then printf 'x11'; return 0; fi
    if [ -n "${XDG_SESSION_TYPE:-}" ]; then printf '%s' "$XDG_SESSION_TYPE"; return 0; fi
    if [ -S "/run/user/$(id -u 2>/dev/null || echo 0)/wayland-0" ] 2>/dev/null; then
        printf 'wayland'; return 0
    fi
    printf 'headless'
}
# Compositor detection -- the HYPRLAND_INSTANCE_SIGNATURE / SWAYSOCK env
# vars (exported by the compositor into the app's process tree) are the
# most reliable cross-distro signals; binary lookups back them up.
detect_compositor() {
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then printf 'hyprland'; return 0; fi
    command -v hyprctl >/dev/null 2>&1 && { printf 'hyprland'; return 0; }
    if [ -n "${SWAYSOCK:-}" ]; then printf 'sway'; return 0; fi
    command -v swaymsg >/dev/null 2>&1 && { printf 'sway'; return 0; }
    printf 'unknown'
}

# --------------------------------------------------------------------------
# FAIL-SAFE COMPOSITOR RUNNER
# --------------------------------------------------------------------------
# Runs one hyprctl call with full tolerance. Counts consecutive failures;
# after the threshold (e.g. SELinux denying every exec on Fedora, or an
# incompatible Hyprland build) it flips into a safe no-op mode so later
# calls are skipped wholesale -- we never hammer a blocked socket.
hypr_call() {
    if [ "${_LW_HYPR_PROBLEM:-0}" = 1 ]; then return 0; fi
    if hyprctl "$@" >/dev/null 2>&1; then
        _LW_HYPR_FAILS=0
        return 0
    fi
    _LW_HYPR_FAILS="$(( ${_LW_HYPR_FAILS:-0} + 1 ))"
    dbg "hyprctl $* -> denial #${_LW_HYPR_FAILS}"
    if [ "$_LW_HYPR_FAILS" -ge 4 ]; then
        _LW_HYPR_PROBLEM=1
        log_err "compositor unresponsive (${_LW_HYPR_FAILS} consecutive denials) -- SELinux policy block or missing runtime; switching to safe no-op, app UI unaffected"
    fi
    return 1
}

# Strict whitelist for the restored `decoration:blur:enabled` value: only a
# prior snapshot of 0/1 is ever forwarded to hyprctl -- never raw file
# content from a possibly corrupt state file.
_sanitize_int() {
    case "$1" in
        0|1) printf '%s' "$1" ;;
        *)   printf '0' ;;
    esac
}

# Map the slider percent (0..100) to the Hyprland blur `size`, clamping to
# [3, 12]. Inverse mapping: LOW pct -> MAXIMUM radius (default 15 -> 12),
# pct 100 -> 3. Mirrors Theme.blurRadius' `(1 - uiBgOpacity)` curve.
blur_size_for() {
    local pct="$1" size
    [ "$pct" -lt 0 ]   && pct=0
    [ "$pct" -gt 100 ] && pct=100
    size=$(( (100 - pct) * 12 / 100 + 3 ))
    [ "$size" -gt 12 ] && size=12
    [ "$size" -lt 3 ]  && size=3
    printf '%s' "$size"
}

# Best-effort restore of the user's prior blur config. Used by the EXIT
# trap when an `apply` is interrupted AND by the regular `remove` path.
_restore_prior_state() {
    local prevv
    prevv="$(cat "$PREV_FILE" 2>/dev/null || echo 0)"
    prevv="$(_sanitize_int "$prevv")"
    hyprctl keyword layerrule unset,blur        >/dev/null 2>&1 || true
    hyprctl keyword layerrule unset,ignorealpha >/dev/null 2>&1 || true
    hyprctl keyword decoration:blur:enabled "$prevv" >/dev/null 2>&1 || true
    rm -f "$PREV_FILE" 2>/dev/null || true
    log "interrupted/removed -- decoration:blur:enabled restored to $prevv"
}

# EXIT/INT trap handler: only acts if `apply` armed it (a signal arrived
# mid-apply); the clean-return path disarms first.
_trap_cleanup() {
    if [ "${_LW_TRAP_ARMED:-0}" = 1 ]; then
        _LW_TRAP_ARMED=0
        _restore_prior_state
    fi
}
trap '_trap_cleanup' EXIT INT HUP TERM

# --------------------------------------------------------------------------
# APPLY / REMOVE / CHECK
# --------------------------------------------------------------------------
do_apply() {
    # Hard kill-switch for admins or SELinux hardening profiles that want to
    # suppress all compositor interaction for this app.
    if [ "${LW_FROST_DISABLED:-0}" = 1 ]; then
        log "LW_FROST_DISABLED=1 -- blur disabled by policy, exiting cleanly"
        return 0
    fi

    local pct="${1:-15}"

    # ---- Strict argument validation (never propagate garbage into hyprctl)
    case "$pct" in
        ''|*[!0-9]*)
            log_err "apply: invalid pct '$pct' (expected integer 0..100)"
            return 2
            ;;
    esac
    [ "$pct" -gt 100 ] && pct=100

    # ---- Session/compositor gate (X11 / Sway / headless -> clean skip)
    local compositor
    compositor="$(detect_compositor)"
    if [ "$compositor" != hyprland ]; then
        log "compositor '$compositor' has no supported blur backend -- skipping (no-op, UI preserved)"
        return 0
    fi

    # ---- Snapshot the user's prior blur state before we override it
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    local prev
    prev="$(hyprctl getoption decoration:blur:enabled -j 2>/dev/null \
        | sed -n 's/.*"int"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)"
    local prevv
    prevv="$(_sanitize_int "${prev:-0}")"
    if ! printf '%s' "$prevv" > "$PREV_FILE" 2>/dev/null; then
        log_err "cannot snapshot prior blur state to $PREV_FILE -- continuing anyway"
    fi

    # ---- Arm trap: restore prior state if we are interrupted mid-apply
    _LW_TRAP_ARMED=1

    local size
    size="$(blur_size_for "$pct")"

    # Real multi-pass GPU blur. Each keyword is individually tolerant:
    # older Hyprland versions lack some options; SELinux on Fedora may
    # block some calls; either way the app must not be taken down.
    hypr_call keyword decoration:blur:enabled true
    hypr_call keyword decoration:blur:size "$size"
    hypr_call keyword decoration:blur:passes 4
    hypr_call keyword decoration:blur:noise 0.02
    hypr_call keyword decoration:blur:vibrancy 0.15
    hypr_call keyword decoration:blur:new_optimizations true

    local ns
    for ns in "${NAMESPACES[@]}"; do
        # Frost whatever desktop pixels sit behind this surface.
        hypr_call keyword layerrule "blur,namespace:$ns"
        # Skip fully transparent pixels (the desktop visible between
        # floating panels): only translucent rectangles consume blur
        # samples, keeping the compositor path cheap.
        hypr_call keyword layerrule "ignorealpha 0.25,namespace:$ns"
    done

    # ---- Disarm trap: apply completed cleanly
    _LW_TRAP_ARMED=0
    log "applied (slider $pct% -> blur size $size, compositor: $compositor)"
}

do_remove() {
    # Disarm trap: `remove` IS the cleanup path; a double-trap adds nothing.
    _LW_TRAP_ARMED=0

    local compositor
    compositor="$(detect_compositor)"
    if [ "$compositor" != hyprland ]; then
        log "compositor '$compositor' -- nothing to remove"
        rm -f "$PREV_FILE" 2>/dev/null || true
        return 0
    fi

    local prevv
    prevv="$(cat "$PREV_FILE" 2>/dev/null || echo 0)"
    prevv="$(_sanitize_int "$prevv")"

    hypr_call keyword layerrule "unset,blur"
    hypr_call keyword layerrule "unset,ignorealpha"
    hypr_call keyword decoration:blur:enabled "$prevv"
    rm -f "$PREV_FILE" 2>/dev/null || true
    log "removed (decoration:blur:enabled restored to $prevv)"
}

# Machine-readable env probe -- always exits 0, always safe. Used by the
# CI smoke test and `--check` diagnostics mode.
do_check() {
    local sd comp hypr_val
    sd="$(resolve_state_dir)"
    comp="$(detect_compositor)"
    if command -v hyprctl >/dev/null 2>&1; then hypr_val=found; else hypr_val=missing; fi
    printf 'os_id=%s\n' "$(detect_os)"
    printf 'session=%s\n' "$(detect_session)"
    printf 'compositor=%s\n' "$comp"
    printf 'hyprctl=%s\n' "$hypr_val"
    printf 'state_dir=%s\n' "$sd"
    printf 'state_writable=%s\n' "$([ -w "$sd" ] 2>/dev/null && echo yes || echo no)"
    printf 'blur_supported=%s\n' "$([ "$comp" = hyprland ] && echo yes || echo no)"
    printf 'pct15_size=%s\n' "$(blur_size_for 15)"
    printf 'pct50_size=%s\n' "$(blur_size_for 50)"
    printf 'pct100_size=%s\n' "$(blur_size_for 100)"
    printf 'bash=%s\n' "$BASH_VERSION"
}

# --------------------------------------------------------------------------
# DISPATCH
# --------------------------------------------------------------------------
case "${1:-}" in
    apply)
        do_apply "${2:-15}"
        exit $?
        ;;
    remove)
        do_remove
        ;;
    --check|-c|check)
        do_check
        ;;
    *)
        log_err "usage: frosted_glass.sh apply <pct 0..100> | remove | --check"
        exit 1
        ;;
esac
exit 0
