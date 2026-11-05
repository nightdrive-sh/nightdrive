#!/usr/bin/env python3
"""WAV files as Recorder writes them (pw-record: 48 kHz mono, 16-bit PCM), read and joined without ffmpeg.

    read(path) -> Info        its format and where its sound is: offset and length in bytes
    duration(path) -> float   seconds, 0.0 for a file that can't be read
    join(pieces, out)         the pieces' sound one after another in one file (all of one format)

Why not ffmpeg's concat: a piece whose pw-record was killed (a crash, a power cut) has a header that still says 0 bytes
or a size from before; read() takes its length from the file's size then, so join() keeps all of it, which is what
"(recovered)" is for. Joining is a copy, so a long recording costs no more than its size on disk.
"""

import struct
from collections import namedtuple
from pathlib import Path

Info = namedtuple("Info", "rate channels bits offset length")
COPY_BLOCK = 1 << 20   # bytes copied at a time: a long recording is never read into memory whole


class WavError(Exception):
    pass


def read(path):
    """The fmt chunk and the data chunk's place. A data chunk whose size runs past the end of the file (or is 0, as
    a header written at the start and never finished) is taken to the end of the file."""
    path = Path(path)
    size = path.stat().st_size
    with path.open("rb") as f:
        head = f.read(12)
        if len(head) < 12 or head[:4] != b"RIFF" or head[8:12] != b"WAVE":
            raise WavError(f"{path.name} isn't a WAV file.")
        fmt = None
        pos = 12
        while pos + 8 <= size:
            f.seek(pos)
            chunk_id, chunk_size = struct.unpack("<4sI", f.read(8))
            if chunk_id == b"fmt ":
                tag, channels, rate, _, _, bits = struct.unpack("<HHIIHH", f.read(16))
                if tag not in (1, 0xFFFE):   # PCM, or WAVE_FORMAT_EXTENSIBLE (still PCM from pw-record)
                    raise WavError(f"{path.name} isn't PCM sound.")
                fmt = (rate, channels, bits)
            elif chunk_id == b"data":
                if fmt is None:
                    raise WavError(f"{path.name} has no format before its sound.")
                offset = pos + 8
                length = chunk_size if 0 < chunk_size <= size - offset else size - offset
                frame = fmt[1] * fmt[2] // 8
                return Info(*fmt, offset, length - length % frame if frame else length)
            pos += 8 + chunk_size + (chunk_size & 1)
    raise WavError(f"{path.name} has no sound in it.")


def seconds(info):
    frame = info.channels * info.bits // 8
    return info.length / (info.rate * frame) if info.rate and frame else 0.0


def duration(path):
    try:
        return seconds(read(path))
    except (OSError, WavError, struct.error):
        return 0.0


def header(rate, channels, bits, length):
    """A plain 44-byte PCM header for length bytes of sound."""
    frame = channels * bits // 8
    return struct.pack("<4sI4s4sIHHIIHH4sI", b"RIFF", 36 + length, b"WAVE", b"fmt ", 16, 1, channels, rate,
                       rate * frame, frame, bits, b"data", length)


def join(pieces, out):
    """Writes out (a new file) from the pieces in order, and returns its Info. Empty or unreadable pieces are left
    out; if no piece has sound, nothing is written and WavError says so."""
    infos = []
    for p in pieces:
        try:
            info = read(p)
        except (OSError, WavError, struct.error):
            continue
        if info.length:
            infos.append((Path(p), info))
    if not infos:
        raise WavError("The recording has no sound in it.")
    rate, channels, bits = infos[0][1][:3]
    if any(i[:3] != (rate, channels, bits) for _, i in infos):
        raise WavError("The pieces of the recording aren't of one format.")
    total = sum(i.length for _, i in infos)
    out = Path(out)
    tmp = out.with_name(out.name + ".part")
    with tmp.open("wb") as w:
        w.write(header(rate, channels, bits, total))
        for p, info in infos:
            with p.open("rb") as r:
                r.seek(info.offset)
                left = info.length
                while left:
                    block = r.read(min(COPY_BLOCK, left))
                    if not block:
                        break
                    w.write(block)
                    left -= len(block)
    tmp.replace(out)
    return Info(rate, channels, bits, 44, total)
