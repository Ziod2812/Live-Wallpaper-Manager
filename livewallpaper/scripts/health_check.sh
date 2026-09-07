#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

check_cmd() {
    local name="$1" command="$2" version=""
    if command -v "$command" >/dev/null 2>&1; then
        version="$("$command" --version 2>/dev/null | head -1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
        jq -n --arg name "$name" --arg status "ok" --arg detail "${version:-installed}" \
            '{name:$name,status:$status,detail:$detail}'
    else
        jq -n --arg name "$name" --arg status "missing" --arg detail "command not found: \($command)" \
            '{name:$name,status:$status,detail:$detail}'
    fi
}

gpu_detail="No DRM device detected"
gpu_status="missing"
if compgen -G "/dev/dri/renderD*" >/dev/null 2>&1; then
    gpu_status="ok"; gpu_detail="$(printf '%s\n' /dev/dri/renderD* | paste -sd ', ' -)"
fi

pipe_status="missing"; pipe_detail="PipeWire socket not found"
if command -v pw-cli >/dev/null 2>&1 || command -v pipewire >/dev/null 2>&1; then
    pipe_status="ok"; pipe_detail="PipeWire tools available"
fi

jq -n \
    --argjson mpvpaper "$(check_cmd mpvpaper mpvpaper)" \
    --argjson gpu "$(jq -n --arg name GPU --arg status "$gpu_status" --arg detail "$gpu_detail" '{name:$name,status:$status,detail:$detail}')" \
    --argjson ffmpeg "$(check_cmd ffmpeg ffmpeg)" \
    --argjson cava "$(check_cmd Cava cava)" \
    --argjson pipewire "$(jq -n --arg name PipeWire --arg status "$pipe_status" --arg detail "$pipe_detail" '{name:$name,status:$status,detail:$detail}')" \
    --argjson jq "$(check_cmd jq jq)" \
    '{checks:[$mpvpaper,$gpu,$ffmpeg,$cava,$pipewire,$jq], generated_at:now|todate}'