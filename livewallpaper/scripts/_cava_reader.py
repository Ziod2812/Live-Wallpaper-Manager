#!/usr/bin/env python3
"""
_cava_reader.py <fifo_path> <bars>
-------------------------------------------------------------------------
Reader bất đồng bộ cho FIFO raw output của Cava.

Thiết kế phòng vệ:
- os.open(..., O_NONBLOCK) để không treo vô hạn khi Cava chưa mở đầu ghi.
- selectors.select(timeout) để chờ readiness thay vì os.read() blocking.
- EOF được coi là Cava đã ngắt/thoát và reader kết thúc sạch.
- PermissionError/SELinux/AppArmor denial được xử lý như một lỗi runtime
  hữu hạn, không để exception thoát qua QML Process.
- mọi file descriptor/selector được đóng trong finally.
- runtime temp chỉ dùng khi thực sự cần; reader này không ghi vào Nix Store.
"""

from __future__ import annotations

import errno
import json
import os
import selectors
import signal
import sys
import time
from pathlib import Path
from typing import Optional

READ_TIMEOUT = 0.50
INITIAL_CONNECT_TIMEOUT = 5.0
READ_CHUNK = 4096


def detect_environment() -> dict[str, str]:
    """Phát hiện distro/Nix ở mức đủ dùng cho diagnostic và permission log."""
    info: dict[str, str] = {
        "distro": "unknown",
        "nix": "false",
        "wayland": "false",
    }

    try:
        os_release: dict[str, str] = {}
        for line in Path("/etc/os-release").read_text(
            encoding="utf-8", errors="replace"
        ).splitlines():
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            os_release[key] = value.strip().strip('"')
        info["distro"] = os_release.get("ID", "unknown")
    except (OSError, UnicodeError):
        pass

    if (
        os.environ.get("NIX_PATH")
        or os.environ.get("IN_NIX_SHELL")
        or os.path.exists("/nix/store")
    ):
        info["nix"] = "true"

    if os.environ.get("WAYLAND_DISPLAY") or os.environ.get("XDG_SESSION_TYPE") == "wayland":
        info["wayland"] = "true"

    return info


def parse_args(argv: list[str]) -> Optional[tuple[str, int]]:
    if len(argv) != 3:
        return None

    fifo_path = argv[1].strip()
    if not fifo_path:
        return None

    try:
        bars = int(argv[2])
    except (TypeError, ValueError):
        return None

    if bars <= 0 or bars > 4096:
        return None

    return fifo_path, bars


def install_signal_handlers(stop_state: dict[str, bool]) -> None:
    def stop_handler(_signum: int, _frame: object) -> None:
        stop_state["stop"] = True

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        try:
            signal.signal(signum, stop_handler)
        except (OSError, ValueError):
            # Có thể xảy ra khi embedded runtime không cho đăng ký signal.
            pass


def emit_complete_frames(buffer: bytearray, bars: int) -> None:
    while len(buffer) >= bars:
        frame = bytes(buffer[:bars])
        del buffer[:bars]
        sys.stdout.write(json.dumps(list(frame), separators=(",", ":")))
        sys.stdout.write("\n")
        sys.stdout.flush()


def main() -> int:
    parsed = parse_args(sys.argv)
    if parsed is None:
        return 2

    fifo_path, bars = parsed
    environment = detect_environment()
    _ = environment  # Giữ detection để diagnostic/debug có thể mở rộng mà không đổi protocol stdout.

    stop_state = {"stop": False}
    install_signal_handlers(stop_state)

    fd: Optional[int] = None
    selector: Optional[selectors.BaseSelector] = None
    connected = False
    deadline = time.monotonic() + INITIAL_CONNECT_TIMEOUT
    buffer = bytearray()

    try:
        while not stop_state["stop"]:
            if fd is None:
                try:
                    # NONBLOCK giải quyết cả open-read race: reader không bị
                    # khóa nếu Cava chưa kịp mở đầu ghi.
                    fd = os.open(fifo_path, os.O_RDONLY | os.O_NONBLOCK)
                    selector = selectors.DefaultSelector()
                    selector.register(fd, selectors.EVENT_READ)
                except PermissionError:
                    # Ubuntu AppArmor/Fedora SELinux có thể deny FIFO tạm thời.
                    # Đây là lỗi hữu hạn; không retry vô hạn.
                    if time.monotonic() >= deadline:
                        return 1
                    time.sleep(0.05)
                    continue
                except FileNotFoundError:
                    if time.monotonic() >= deadline:
                        return 1
                    time.sleep(0.05)
                    continue
                except OSError:
                    if time.monotonic() >= deadline:
                        return 1
                    time.sleep(0.05)
                    continue

            events = selector.select(timeout=READ_TIMEOUT) if selector else []
            if not events:
                continue

            try:
                chunk = os.read(fd, READ_CHUNK)
            except BlockingIOError:
                continue
            except InterruptedError:
                continue
            except PermissionError:
                # Permission context có thể thay đổi sau khi FIFO được mở.
                # Không loop nóng; đóng và retry trong cửa sổ hữu hạn.
                if selector is not None:
                    try:
                        selector.close()
                    except OSError:
                        pass
                    selector = None
                if fd is not None:
                    try:
                        os.close(fd)
                    except OSError:
                        pass
                    fd = None
                if time.monotonic() >= deadline:
                    return 1
                time.sleep(0.10)
                continue
            except OSError as exc:
                if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK, errno.EINTR):
                    continue
                return 1

            if not chunk:
                # EOF sau khi đã connected = Cava đóng đầu ghi.
                # EOF khi chưa connected có thể là race open-before-writer.
                if not connected and time.monotonic() < deadline:
                    if selector is not None:
                        try:
                            selector.close()
                        except OSError:
                            pass
                        selector = None
                    if fd is not None:
                        try:
                            os.close(fd)
                        except OSError:
                            pass
                        fd = None
                    time.sleep(0.05)
                    continue
                break

            connected = True
            buffer.extend(chunk)
            emit_complete_frames(buffer, bars)

    except KeyboardInterrupt:
        return 130
    except (OSError, RuntimeError):
        # Reader là helper phụ; tuyệt đối không để traceback làm bẩn protocol
        # stdout mà CavaService đang parse.
        return 1
    finally:
        if selector is not None:
            try:
                selector.close()
            except OSError:
                pass
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
