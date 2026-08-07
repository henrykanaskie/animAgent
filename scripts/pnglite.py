"""Minimal PNG decode/encode. Python 3 stdlib only — zlib + struct.

Exists because the art pipeline must run with no pip install (see
docs/04-ART-DIRECTION.md: the palette pass is a committed script, so it has to
work on a clean checkout with nothing but python3).

Scope is deliberately narrow: 8-bit-per-channel, non-interlaced PNGs, which is
what every file in the LimeZu packs is (verified at M0 — all 1047 PNGs are
bit depth 8, colour type 6, interlace 0). Anything else raises rather than
guessing, because a silently mis-decoded sprite is worse than a crash.

Images are represented as (width, height, pixels) where pixels is a flat
bytearray of RGBA, 4 bytes per pixel, row-major. Small enough for 32x48
sprites; we are not building an image library.
"""

import struct
import zlib

PNG_SIG = b"\x89PNG\r\n\x1a\n"

_CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


class PNGError(Exception):
    pass


def read_header(path):
    """Return (width, height, bitdepth, colourtype, interlace) from IHDR only.

    Cheap: reads 33 bytes. Used for inventory passes over hundreds of files
    where decoding every pixel would be wasteful.
    """
    with open(path, "rb") as f:
        if f.read(8) != PNG_SIG:
            raise PNGError("%s: not a PNG" % path)
        f.read(4)  # IHDR length, always 13
        if f.read(4) != b"IHDR":
            raise PNGError("%s: first chunk is not IHDR" % path)
        w, h, bd, ct, _comp, _filt, il = struct.unpack(">IIBBBBB", f.read(13))
    return w, h, bd, ct, il


def _chunks(data):
    pos = 8
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        ctype = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        yield ctype, body
        pos += 12 + length


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _unfilter(raw, width, height, bpp):
    """Reverse the per-scanline PNG filters. Returns unfiltered scanline bytes."""
    stride = width * bpp
    out = bytearray(height * stride)
    pos = 0
    for y in range(height):
        ft = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride
        base = y * stride
        prev = base - stride
        if ft == 0:
            pass
        elif ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ft == 2:
            if y > 0:
                for i in range(stride):
                    line[i] = (line[i] + out[prev + i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = out[prev + i] if y > 0 else 0
                line[i] = (line[i] + ((a + b) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = out[prev + i] if y > 0 else 0
                c = out[prev + i - bpp] if (y > 0 and i >= bpp) else 0
                line[i] = (line[i] + _paeth(a, b, c)) & 0xFF
        else:
            raise PNGError("unknown filter type %d on row %d" % (ft, y))
        out[base : base + stride] = line
    return out


def load(path):
    """Decode a PNG to (width, height, RGBA bytearray)."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != PNG_SIG:
        raise PNGError("%s: not a PNG" % path)

    width = height = None
    bitdepth = colourtype = interlace = None
    idat = bytearray()
    palette = None
    trns = None

    for ctype, body in _chunks(data):
        if ctype == b"IHDR":
            width, height, bitdepth, colourtype, _c, _f, interlace = struct.unpack(
                ">IIBBBBB", body
            )
        elif ctype == b"PLTE":
            palette = body
        elif ctype == b"tRNS":
            trns = body
        elif ctype == b"IDAT":
            idat += body
        elif ctype == b"IEND":
            break

    if bitdepth != 8:
        raise PNGError("%s: bit depth %s unsupported (only 8)" % (path, bitdepth))
    if interlace != 0:
        raise PNGError("%s: interlaced PNGs unsupported" % path)
    if colourtype not in _CHANNELS:
        raise PNGError("%s: colour type %s unsupported" % (path, colourtype))

    bpp = _CHANNELS[colourtype]
    raw = _unfilter(zlib.decompress(bytes(idat)), width, height, bpp)

    n = width * height
    rgba = bytearray(n * 4)

    if colourtype == 6:
        rgba[:] = raw
    elif colourtype == 2:
        for i in range(n):
            rgba[i * 4 : i * 4 + 3] = raw[i * 3 : i * 3 + 3]
            rgba[i * 4 + 3] = 255
    elif colourtype == 0:
        for i in range(n):
            g = raw[i]
            rgba[i * 4 : i * 4 + 4] = bytes((g, g, g, 255))
    elif colourtype == 4:
        for i in range(n):
            g, a = raw[i * 2], raw[i * 2 + 1]
            rgba[i * 4 : i * 4 + 4] = bytes((g, g, g, a))
    elif colourtype == 3:
        if palette is None:
            raise PNGError("%s: indexed PNG with no PLTE" % path)
        for i in range(n):
            idx = raw[i]
            rgba[i * 4 : i * 4 + 3] = palette[idx * 3 : idx * 3 + 3]
            rgba[i * 4 + 3] = trns[idx] if (trns and idx < len(trns)) else 255

    return width, height, rgba


def _chunk(ctype, body):
    return (
        struct.pack(">I", len(body))
        + ctype
        + body
        + struct.pack(">I", zlib.crc32(ctype + body) & 0xFFFFFFFF)
    )


def save(path, width, height, rgba):
    """Encode RGBA to an 8-bit colour-type-6 PNG.

    Filter 0 (None) on every scanline and a fixed zlib level, so the same
    pixels always produce the same bytes. That byte-determinism is what makes
    the import pass idempotent — rerunning it must not churn the working tree.
    """
    if len(rgba) != width * height * 4:
        raise PNGError("pixel buffer is %d bytes, expected %d" % (len(rgba), width * height * 4))
    stride = width * 4
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += rgba[y * stride : (y + 1) * stride]
    out = bytearray(PNG_SIG)
    out += _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    out += _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    out += _chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(out)


def new(width, height, rgba=(0, 0, 0, 0)):
    """A blank RGBA buffer filled with one colour."""
    return bytearray(bytes(rgba) * (width * height))


def put(buf, width, x, y, rgba):
    i = (y * width + x) * 4
    buf[i : i + 4] = bytes(rgba)


def fill_rect(buf, width, height, x0, y0, w, h, rgba):
    """Clipped axis-aligned rectangle fill. Clipping is the point — the
    placeholder generator draws shapes by arithmetic and must not raise when a
    shape runs off canvas."""
    px = bytes(rgba)
    for y in range(max(0, y0), min(height, y0 + h)):
        row = y * width
        for x in range(max(0, x0), min(width, x0 + w)):
            i = (row + x) * 4
            buf[i : i + 4] = px
