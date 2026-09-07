#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# smoke_test_frosted_glass.sh -- CROSS-DISTRO SMOKE TEST (BƯỚC 3)
# ---------------------------------------------------------------------------
# Auto-detects the running distro (Arch / Fedora / Debian / Ubuntu / NixOS)
# and smoke-tests the hardened scripts/frosted_glass.sh through its
# `--check` + apply/remove contract WITHOUT needing a live compositor.
#
# It never touches the real Hyprland state: it forces a synthetic, writable
# state dir (LW_STATE_DIR), injects a fake hyprctl via a PATH shim, and a
# synthetic /etc/os-release per distro (LW_OS_RELEASE). The SAME binary is
# therefore portable across all CI runners / distros.
#
# Usage:
#   bash smoke_test_frosted_glass.sh
# Exit codes: 0 = all smoke checks green, 1 = at least one failed.
# ---------------------------------------------------------------------------
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FG="$SCRIPT_DIR/../frosted_glass.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lw_frost_smoke.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

passed=0
failed=0

ok()   { printf '  [OK]   %s\n' "$1"; passed=$((passed+1)); }
bad()  { printf '  [LỖI]  %s\n' "$1"; failed=$((failed+1)); }

# Build a hermetic bin dir containing ONLY the tools the target needs, so
# `command -v hyprctl` can never accidentally find a host-installed hyprctl
# (this host runs CachyOS/Hyprland; tests must simulate "no compositor"
# credibly on ANY CI box). bash/sed/head/tr/id/mkdir/cat/rm suffice.
FARM="$TEST_ROOT/farm"
mkdir -p "$FARM"
for _t in bash sed head tr id mkdir cat rm; do
    _src="$(command -v "$_t" 2>/dev/null || true)"
    if [ -n "$_src" ] && [ -x "$_src" ]; then
        ln -sf "$_src" "$FARM/$_t"
    fi
done

# Run one scenario with a fabricated environment.
#   scenario <os_id> <session> <with_hyprctl 0|1> <expect_blur 0|1>
scenario() {
    local os_id="$1" session="$2" with_hp="$3" expect_blur="$4"
    local label="$os_id / ${with_hp}:hyprctl / $session"

    local osrel="$TEST_ROOT/osrelease-$os_id"
    printf 'ID=%s\n' "$os_id" > "$osrel"
    local statedir="$TEST_ROOT/state-$os_id"
    mkdir -p "$statedir"

    local shim="$TEST_ROOT/bin-$os_id"
    mkdir -p "$shim"
    rm -f "$shim/hyprctl"      # never let a previous scenario's fake leak in
    if [ "$with_hp" = 1 ]; then
        printf '#!/usr/bin/env bash\nexit 0\n' > "$shim/hyprctl"
        chmod +x "$shim/hyprctl"
    fi

    # Env the hardened script resolves; LW_* are our injectable hooks.
    # HYPRLAND_INSTANCE_SIGNATURE is intentionally NEVER injected, so
    # compositor detection is decided purely by the binary on PATH.
    local env_args=(env
        LW_OS_RELEASE="$osrel"
        LW_STATE_DIR="$statedir"
        HYPRLAND_INSTANCE_SIGNATURE=
        SWAYSOCK=
        PATH="$shim:$FARM"
    )
    case "$session" in
        wayland) env_args+=(WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland) ;;
        x11)     env_args+=(XDG_SESSION_TYPE=x11 DISPLAY=:0) ;;
        headless) : ;;
    esac

    # 1) --check always succeeds; blur_supported must match the setup.
    local out bs
    out="$("${env_args[@]}" bash "$FG" --check)" || { bad "$label: --check returned non-zero"; return; }
    bs="$(printf '%s\n' "$out" | grep '^blur_supported=' | cut -d= -f2)"
    local exp_bs=no; [ "$expect_blur" = 1 ] && exp_bs=yes
    if [ "$bs" = "$exp_bs" ]; then
        ok "$label: --check blur_supported=$bs (expected $exp_bs)"
    else
        bad "$label: --check blur_supported=$bs, expected $exp_bs"
    fi

    # 2) apply must be a clean return (0) in EVERY scenario.
    "${env_args[@]}" bash "$FG" apply 15 >/dev/null 2>&1
    [ $? -eq 0 ] && ok "$label: apply 15 cleanly returns 0" \
                  || bad "$label: apply 15 returned non-zero"

    # 3) remove must be a clean return too.
    "${env_args[@]}" bash "$FG" remove >/dev/null 2>&1
    [ $? -eq 0 ] && ok "$label: remove cleanly returns 0" \
                  || bad "$label: remove returned non-zero"

    # 4) invalid input must be rejected (exit 2), never silently swallowed.
    "${env_args[@]}" bash "$FG" apply abc >/dev/null 2>&1
    [ $? -eq 2 ] && ok "$label: apply abc rejected (exit 2)" \
                  || bad "$label: apply abc not rejected"
}

detect_real_os() {
    local rel="$1" id=""
    if [ -r "$rel" ]; then
        id="$(sed -n 's/^ID=//p' "$rel" | tr -d '"' | head -1)"
    fi
    printf '%s' "${id:-unknown}"
}

real_os="$(detect_real_os /etc/os-release)"
printf 'Host distro detected: %s\n' "$real_os"
printf 'Testing hardened target: %s\n' "$FG"
{ bash -n "$FG" && ok 'target passes bash -n' || bad 'target bash -n failed'; }
# --- all five target distros, Wayland session, with AND without hyprctl ---
for d in arch fedora debian ubuntu nixos; do
    scenario "$d" wayland 1 1     # compositor available -> blur supported
    scenario "$d" wayland 0 0     # no compositor -> graceful skip
done

# --- cross-session exception matrix ----------------------------------------
scenario arch x11 1 1        # hyprctl tool present; runtime no-ops safely
scenario debian x11 0 0      # non-Hyprland X11 fallback
scenario ubuntu headless 0 0 # headless: no display at all
scenario nixos headless 0 0

# --- SELinux/denial degradation simulation (Fedora, hyprctl always fails) ---
printf '\n--- Fedora SELinux denial simulation (hyprctl blocked) ---\n'
fed_shim="$TEST_ROOT/bin-selinux"
mkdir -p "$fed_shim"
printf '#!/usr/bin/env bash\nexit 1\n' > "$fed_shim/hyprctl"
chmod +x "$fed_shim/hyprctl"
env LW_OS_RELEASE="$TEST_ROOT/osrelease-fedora" \
    LW_STATE_DIR="$TEST_ROOT/state-selinux" \
    HYPRLAND_INSTANCE_SIGNATURE= SWAYSOCK= \
    PATH="$fed_shim:$FARM" WAYLAND_DISPLAY=wayland-0 \
    bash "$FG" apply 15 >/dev/null 2>&1
[ $? -eq 0 ] && ok 'fedora/selinux: apply degrades to safe no-op, returns 0' \
              || bad 'fedora/selinux: apply did NOT survive denials'

# --- NixOS read-only $HOME simulation (no HOME, no XDG_*) -------------------
printf '\n--- NixOS read-only HOME simulation (no HOME, no XDG_*) ---\n'
env -i PATH="$FARM" LW_OS_RELEASE="$TEST_ROOT/osrelease-nixos" \
    LW_STATE_DIR="$TEST_ROOT/state-nixos" \
    bash "$FG" apply 15 >/dev/null 2>&1
[ $? -eq 0 ] && ok 'nixos + stripped env: apply 15 cleanly returns 0' \
              || bad 'nixos + stripped env: apply 15 crashed (unbound variable?)'

# --- summary -----------------------------------------------------------------
printf '\n===== SMOKE TEST SUMMARY =====\n'
printf '[OK] passed=%d  [LỖI] failed=%d\n' "$passed" "$failed"
if [ "$failed" -eq 0 ]; then
    printf 'RESULT: %s\n' '[OK] ALL SMOKE CHECKS GREEN'
    exit 0
else
    printf 'RESULT: %s\n' '[LỖI] SMOKE TEST FAILED'
    exit 1
fi