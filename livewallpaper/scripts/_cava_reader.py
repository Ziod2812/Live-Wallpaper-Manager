#!/usr/bin/env python3
"""
_cava_reader.py <fifo_path> <bars>
-------------------------------------------------------------------------
Internal helper for CavaService.qml -- not meant to be run by hand.

cava (started by start_cava.sh) writes raw binary frames into <fifo_path>:
one unsigned byte (0-255) per bar, `bars` bytes per frame (see cava.conf:
output.method=raw, data_format=binary, bit_format=8bit). This process
opens the FIFO for reading (a blocking open until cava's write end
connects), then blocks on os.read() -- no polling, no busy loop -- and
prints one JSON array line per complete frame, e.g. [12,45,201,...],
flushing immediately so CavaService's SplitParser sees it right away.

Exits cleanly (no further output) once the FIFO's writer (cava) goes
away / EOF, so CavaService.qml's onExited can decide whether to retry.
"""
import json
import os
import sys


def main():
    if len(sys.argv) < 3:
        sys.exit(1)

    fifo_path = sys.argv[1]
    try:
        bars = int(sys.argv[2])
    except ValueError:
        sys.exit(1)
    if bars <= 0:
        sys.exit(1)

    try:
        fd = os.open(fifo_path, os.O_RDONLY)
    except OSError:
        sys.exit(1)

    buf = b""
    try:
        while True:
            need = bars - len(buf)
            chunk = os.read(fd, need if need > 0 else 4096)
            if not chunk:
                break  # writer (cava) closed the FIFO
            buf += chunk
            while len(buf) >= bars:
                frame, buf = buf[:bars], buf[bars:]
                sys.stdout.write(json.dumps(list(frame)))
                sys.stdout.write("\n")
                sys.stdout.flush()
    except (OSError, KeyboardInterrupt):
        pass
    finally:
        try:
            os.close(fd)
        except OSError:
            pass


if __name__ == "__main__":
    main()
