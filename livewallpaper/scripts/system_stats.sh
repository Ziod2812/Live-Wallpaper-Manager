#!/usr/bin/env bash
#
# system_stats.sh
# ------------------
# Read-only resource snapshot for the Manager app's Performance page
# (Services/SystemStatsService.qml). Same "small script + Paths.script()
# call" shape as monitor.sh/cache.sh -- this file does NOT touch
# mpvpaper, cava, the stream/web workers, or any state file the
# playback pipeline reads/writes. It only reads /proc/stat, /proc/meminfo,
# /proc/cpuinfo, /sys/devices/system/cpu/*/cpufreq, and `ps`.
#
# CPU% uses the SAME algorithm htop/btop use: total jiffies delta vs
# idle jiffies delta between two samples of /proc/stat. Unlike a naive
# implementation, this does NOT sleep inside the process to get two
# samples -- it persists the previous /proc/stat reading to a small
# state file (LW_CACHE_DIR/state/cpu_prev) and diffs against that on
# the NEXT invocation. Since the QML side already polls this script
# once a second (SystemStatsService.qml), consecutive invocations are
# exactly the two samples the algorithm needs -- zero sleep, one fast
# /proc/stat read per call (<1ms), matching the "very low overhead"
# requirement. First-ever call (no previous state) reports 0% and just
# writes the baseline, same as htop's first tick.
#
# Prints one JSON object:
#   {
#     "cpu": {
#       "percent": <0-100 int, real /proc/stat delta -- htop/btop algorithm>,
#       "model": "<CPU model name>",
#       "cores": <int, physical cores>,
#       "threads": <int, logical CPUs>,
#       "freq_mhz": <int, current average frequency across online CPUs>
#     },
#     "mem_used_mb": <int>, "mem_total_mb": <int>,
#     "processes": [{"pid","name","cpu","mem"}, ...]  -- only
#       mpvpaper / ffmpeg / quickshell / cava / the mpv-IPC and
#       cava-reader python helpers, sorted by CPU, top 8
#   }
#
# No arguments, no side effects beyond the tiny cpu_prev state file,
# safe to call as often as the UI wants (SystemStatsService.qml polls
# this every 1s while the Performance page is open).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

CPU_PREV_FILE="$LW_STATE_DIR/cpu_prev"

# ---------------------------------------------------------------------------
# CPU% -- htop/btop algorithm: nonidle = user+nice+system+irq+softirq+steal,
# idle = idle+iowait, percent = nonidle_delta / (nonidle_delta+idle_delta).
# ---------------------------------------------------------------------------
_lw_cpu_percent() {
    local line user nice sys idle iowait irq softirq steal
    read -r line < /proc/stat
    read -r _ user nice sys idle iowait irq softirq steal _ <<< "$line"
    steal="${steal:-0}"

    local idle_now=$((idle + iowait))
    local nonidle_now=$((user + nice + sys + irq + softirq + steal))
    local total_now=$((idle_now + nonidle_now))

    local pct=0
    mkdir -p "$LW_STATE_DIR" 2>/dev/null
    if [ -r "$CPU_PREV_FILE" ]; then
        local idle_prev total_prev
        read -r idle_prev total_prev < "$CPU_PREV_FILE" 2>/dev/null
        if [ -n "$idle_prev" ] && [ -n "$total_prev" ]; then
            local idle_d=$((idle_now - idle_prev))
            local total_d=$((total_now - total_prev))
            [ "$total_d" -gt 0 ] && pct=$(( (100 * (total_d - idle_d)) / total_d ))
            [ "$pct" -lt 0 ] && pct=0
            [ "$pct" -gt 100 ] && pct=100
        fi
    fi
    printf '%s %s\n' "$idle_now" "$total_now" > "$CPU_PREV_FILE" 2>/dev/null

    echo "$pct"
}

# ---------------------------------------------------------------------------
# CPU model / core / thread counts -- static per boot. Individually each of
# these is a cheap read, but together (awk + awk|sort|wc + nproc) they're
# ~4 extra forks paid on EVERY invocation of this script, and
# SystemStatsService.qml polls this every 1s for as long as the Performance
# page is open. Since the values genuinely cannot change without a reboot
# (CPU hotplug on VMs changes the online *count*, not the topology/model
# these fields read), they're computed once and cached to a small state
# file keyed by /proc/sys/kernel/random/boot_id -- a stale cache from a
# previous boot (or a different machine sharing the same $HOME/.cache, e.g.
# a synced dotfiles setup) is detected by the boot_id mismatch and
# recomputed automatically, so this is free correctness-wise, not just an
# assumption. cpu_percent/freq/mem/processes below are UNCHANGED -- they
# still read fresh every single call, exactly as before.
# ---------------------------------------------------------------------------
CPU_STATIC_FILE="$LW_STATE_DIR/cpu_static"

_lw_cpu_model() {
    awk -F: '/^model name/{gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo
}

_lw_cpu_threads() {
    nproc --all 2>/dev/null || grep -c '^processor' /proc/cpuinfo
}

# Physical core count: unique (physical_id, core_id) pairs. Falls back to
# thread count on systems that don't expose these fields (e.g. some ARM/VM
# kernels) rather than guessing.
_lw_cpu_cores() {
    local n
    n="$(awk -F: '
        /^physical id/{p=$2}
        /^core id/{c=$2; print p","c}
    ' /proc/cpuinfo | sort -u | wc -l)"
    if [ -z "$n" ] || [ "$n" -eq 0 ]; then
        _lw_cpu_threads
    else
        echo "$n"
    fi
}

# Prints "model|cores|threads", from cache when the cache matches the
# current boot, otherwise computes fresh (via the three functions above)
# and refreshes the cache. Model names never contain "|", so the delimiter
# is unambiguous to split back out.
_lw_cpu_static_info() {
    local boot_id="" cached_boot="" cached_model="" cached_cores="" cached_threads=""
    [ -r /proc/sys/kernel/random/boot_id ] && boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"

    if [ -n "$boot_id" ] && [ -r "$CPU_STATIC_FILE" ]; then
        IFS='|' read -r cached_boot cached_model cached_cores cached_threads < "$CPU_STATIC_FILE" 2>/dev/null
        if [ "$cached_boot" = "$boot_id" ] && [ -n "$cached_model" ] && [ -n "$cached_cores" ] && [ -n "$cached_threads" ]; then
            printf '%s|%s|%s\n' "$cached_model" "$cached_cores" "$cached_threads"
            return
        fi
    fi

    local model cores threads
    model="$(_lw_cpu_model)"
    cores="$(_lw_cpu_cores)"
    threads="$(_lw_cpu_threads)"
    mkdir -p "$LW_STATE_DIR" 2>/dev/null
    printf '%s|%s|%s|%s\n' "$boot_id" "$model" "$cores" "$threads" > "$CPU_STATIC_FILE" 2>/dev/null
    printf '%s|%s|%s\n' "$model" "$cores" "$threads"
}

# Current average frequency (MHz) across online logical CPUs. Prefers
# cpufreq's scaling_cur_freq (kHz, instantaneous, cheap sysfs read); falls
# back to /proc/cpuinfo's "cpu MHz" field when cpufreq isn't exposed
# (common in some VMs/containers).
_lw_cpu_freq_mhz() {
    local sum=0 n=0 f
    for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
        [ -r "$f" ] || continue
        local khz; khz="$(cat "$f" 2>/dev/null)"
        [ -n "$khz" ] || continue
        sum=$((sum + khz))
        n=$((n + 1))
    done
    if [ "$n" -gt 0 ]; then
        echo $((sum / n / 1000))
        return
    fi
    awk -F: '/^cpu MHz/{gsub(/^[ \t]+/,"",$2); s+=$2; n++} END{if(n>0) printf "%d\n", s/n; else print 0}' /proc/cpuinfo
}

# ---------------------------------------------------------------------------
# Assemble
# ---------------------------------------------------------------------------
cpu_percent="$(_lw_cpu_percent)"
IFS='|' read -r cpu_model cpu_cores cpu_threads < <(_lw_cpu_static_info)
cpu_freq="$(_lw_cpu_freq_mhz)"

read -r memused memtotal < <(free -m 2>/dev/null | awk 'NR==2{print $3, $2}')

procjson=$(ps -eo pid=,comm=,pcpu=,pmem= 2>/dev/null \
    | grep -E 'mpvpaper|ffmpeg|quickshell|cava|_mpv_ipc|python3' \
    | grep -v grep \
    | sort -k3 -rn \
    | head -8 \
    | awk '{printf "{\"pid\":%s,\"name\":\"%s\",\"cpu\":%s,\"mem\":%s},", $1, $2, $3, $4}')
procjson="[${procjson%,}]"

jq -cn \
    --argjson cpu_percent "${cpu_percent:-0}" \
    --arg cpu_model "${cpu_model:-Unknown}" \
    --argjson cpu_cores "${cpu_cores:-0}" \
    --argjson cpu_threads "${cpu_threads:-0}" \
    --argjson cpu_freq "${cpu_freq:-0}" \
    --argjson mem_used "${memused:-0}" \
    --argjson mem_total "${memtotal:-0}" \
    --argjson processes "$procjson" \
    '{
        cpu: {percent:$cpu_percent, model:$cpu_model, cores:$cpu_cores, threads:$cpu_threads, freq_mhz:$cpu_freq},
        mem_used_mb:$mem_used, mem_total_mb:$mem_total,
        processes:$processes
    }'
