"""A downloaded file's type, read from its first bytes (#2242): only the few web_download keeps, each by the signature
its format starts with, never by the name or what the server says. Pure Python rather than `file --mime-type`:
Nightdrive doesn't install `file` (Fedora Minimal and the sandbox lack it), and these signatures are all it would look
at for these types.

    kind(head) -> (mime, extension) or None      head: the file's first HEAD bytes
"""

HEAD = 64
# Ogg carries video too (Theora): only these codecs' first packet, at byte 28 after the page header, is audio
OGG_AUDIO = (b"\x01vorbis", b"OpusHead", b"\x7fFLAC", b"Speex   ")


def mp3_frame(head):
    """An MPEG audio frame header at the start (an MP3 without an ID3 tag): the sync bits, a layer, and a bitrate and
    sample rate that aren't the reserved values."""
    if len(head) < 4 or head[0] != 0xFF or head[1] & 0xE0 != 0xE0:
        return False
    version, layer = (head[1] >> 3) & 3, (head[1] >> 1) & 3
    bitrate, rate = head[2] >> 4, (head[2] >> 2) & 3
    return version != 1 and layer != 0 and bitrate not in (0, 15) and rate != 3


def kind(head):
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png", "png"
    if head.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", "jpg"
    if head[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif", "gif"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "image/webp", "webp"
    if head[:4] == b"RIFF" and head[8:12] == b"WAVE":
        return "audio/wav", "wav"
    if head.startswith(b"%PDF-"):
        return "application/pdf", "pdf"
    if head[:4] in (b"PK\x03\x04", b"PK\x05\x06"):   # a zip, or an empty one
        return "application/zip", "zip"
    if head.startswith(b"fLaC"):
        return "audio/flac", "flac"
    if head.startswith(b"OggS") and any(head[28:28 + len(c)] == c for c in OGG_AUDIO):
        return "audio/ogg", "ogg"
    if head.startswith(b"ID3") or mp3_frame(head):
        return "audio/mpeg", "mp3"
    return None
