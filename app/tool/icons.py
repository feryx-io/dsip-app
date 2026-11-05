#!/usr/bin/env python3
"""DSIP's app icon, drawn in pure Python so anyone can draw it again: `python3 tool/icons.py`.

A white key (your identity is a key you hold, not an account) on a rounded square in the app's teal, for macOS (the
AppIcon set), Windows (app_icon.ico), Linux (linux/packaging/dsip.png, the installers' icon) and Android (the launcher's
mipmaps); on a full, opaque square for iOS (the AppIcon set), which rounds the corners itself and refuses an alpha
channel. The approach is Anvil's (its app/tool/icons.py)."""

import math
import os
import struct
import zlib

TEAL = (0x00, 0x6B, 0x5F)  # the theme's primary from Colors.teal as its seed, near enough
SS = 4  # samples per pixel, each way


def key(x, y):
    """Whether (x, y), in a unit square centred on 0, is on the key: a ring (its bow) upper left, a shaft to the lower
    right, two teeth off the shaft's end."""
    u = (x + y) / math.sqrt(2)  # along the key
    v = (y - x) / math.sqrt(2)  # across it
    r = math.hypot(u + 0.22, v)
    if 0.075 <= r <= 0.165:
        return True
    if -0.07 <= u <= 0.33 and abs(v) <= 0.042:
        return True
    return any(a <= u <= b and 0 <= v <= 0.12 for a, b in ((0.17, 0.225), (0.265, 0.33)))


def tile(x, y):
    """A rounded square with a margin, as macOS lays out an app icon."""
    half, radius = 0.40, 0.13
    dx, dy = max(abs(x) - (half - radius), 0), max(abs(y) - (half - radius), 0)
    return math.hypot(dx, dy) <= radius


def square(x, y):
    """The whole square: iOS draws its own corners."""
    return True


def render(size, ss=SS, shape=tile, scale=1.3, opaque=False):
    rows = []
    for py in range(size):
        row = bytearray([0])  # PNG filter: none
        for px in range(size):
            inside = white = 0
            for sy in range(ss):
                for sx in range(ss):
                    x = (px + (sx + 0.5) / ss) / size - 0.5
                    y = (py + (sy + 0.5) / ss) / size - 0.5
                    if shape(x, y):
                        inside += 1
                        if key(x * scale, y * scale):
                            white += 1
            alpha = inside / (ss * ss)
            w = white / inside if inside else 0
            rgb = [round(c * (1 - w) + 255 * w) for c in TEAL]
            row += bytes(rgb if opaque else rgb + [round(alpha * 255)])
        rows.append(bytes(row))
    return png(size, b"".join(rows), opaque)


def png(size, raw, opaque=False):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", size, size, 8, 2 if opaque else 6, 0, 0, 0)  # 8-bit RGB, or RGBA
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def ico(images):
    """An ICO holding PNG images (Windows Vista and later)."""
    out = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    data = b""
    for size, image in images:
        out += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(image), offset + len(data))
        data += image
    return out + data


def main():
    app = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    icons = {size: render(size, ss=4 if size <= 256 else 2) for size in (16, 32, 48, 64, 128, 256, 512, 1024)}
    mac = os.path.join(app, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for size in (16, 32, 64, 128, 256, 512, 1024):
        with open(os.path.join(mac, f"app_icon_{size}.png"), "wb") as f:
            f.write(icons[size])
    with open(os.path.join(app, "windows", "runner", "resources", "app_icon.ico"), "wb") as f:
        f.write(ico([(s, icons[s]) for s in (16, 32, 48, 64, 128, 256)]))
    linux = os.path.join(app, "linux", "packaging")
    os.makedirs(linux, exist_ok=True)
    with open(os.path.join(linux, "dsip.png"), "wb") as f:
        f.write(icons[512])
    res = os.path.join(app, "android", "app", "src", "main", "res")
    for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        with open(os.path.join(res, f"mipmap-{density}", "ic_launcher.png"), "wb") as f:
            f.write(render(size))
    ios = os.path.join(app, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for name in sorted(os.listdir(ios)):
        if name.startswith("Icon-App-") and name.endswith(".png"):
            # Icon-App-83.5x83.5@2x.png: 83.5 points at 2x is 167 pixels. The key a little larger: the square has no
            # margin.
            points, scale = name[len("Icon-App-"):-len(".png")].split("@")
            size = round(float(points.split("x")[0]) * int(scale[:-1]))
            with open(os.path.join(ios, name), "wb") as f:
                f.write(render(size, ss=4 if size <= 256 else 2, shape=square, scale=1.05, opaque=True))


if __name__ == "__main__":
    main()
