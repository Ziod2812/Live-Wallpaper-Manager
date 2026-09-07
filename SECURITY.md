# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 2.9.x   | :white_check_mark: |
| < 2.9   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in Live Wallpaper Manager, please report it responsibly:

1. **Do not** open a public issue.
2. Email the maintainer directly or use GitHub's private vulnerability reporting feature.
3. Include:
   - A description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if available)

You should receive a response within 48 hours. If the vulnerability is confirmed, a fix will be prioritized and released as soon as possible.

## Security Considerations

### What this application does

- Executes local shell scripts for wallpaper management
- Uses `mpvpaper`, `mpv`, `ffmpeg`, and other media tools
- Optional system tray integration via Python
- Communicates with Quickshell via IPC

### What this application does NOT do

- Make outbound network requests (except optional weather/solar data from Open-Meteo API)
- Send telemetry or analytics
- Collect or transmit user data
- Execute arbitrary remote code

### Installer remote execution (install.sh only)

During interactive installation, `install.sh` may execute remote setup
scripts from trusted third parties. These are clearly disclosed at
runtime with `info` messages before execution:

1. **NodeSource repository setup** (`install_node_latest()`)
   - Executes: `curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -`
   - Purpose: Adds NodeSource apt/dnf repository so yt-dlp's YouTube JS solver works
   - Transparency: URL is printed via `info` before execution
   - Manual alternative: Cancel and follow https://github.com/nodesource/distributions
   - Only runs on Fedora (dnf) and Debian/Ubuntu (apt), never on Arch/NixOS

2. **Rust installer via rustup** (`install_awww()`)
   - Executes: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
   - Purpose: Installs user-local Rust toolchain for AWWW source build
   - Transparency: Clear `info` message printed before execution
   - Manual alternative: Cancel and run `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh` yourself
   - Only runs when system Rust is missing/too old and no existing rustup found
   - Installs to `~/.cargo` (user-local, no root required)

### External dependencies

This project depends on several external tools. Ensure they are installed from trusted sources:

- `quickshell` — QML/Qt shell framework
- `mpvpaper` — Wayland wallpaper renderer
- `mpv` — Media player
- `ffmpeg` — Media processing
- `yt-dlp` — Video streaming (optional, for YouTube/Twitch sources)

### User responsibility

- Review `install.sh` before running it on your system
- Do not run as root unless necessary
- Keep dependencies updated
- Report suspicious behavior
