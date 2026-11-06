#!/usr/bin/env python3
"""Draws the Sus-o-meter app icon (70s game-show marquee) into
ios/Runner/Assets.xcassets/AppIcon.appiconset at every size Contents.json lists.

Uses the bundled Bowlby One SC font (OFL). Icons are opaque RGB, as the App
Store requires. Needs Pillow: python3 tool/gen_icon.py
"""

import json
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
ICONSET = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
FONT = os.path.join(ROOT, "assets", "fonts", "BowlbyOneSC-Regular.ttf")

MUSTARD = (0xF2, 0xB3, 0x3D)
INK = (0x2A, 0x16, 0x0C)
CREAM = (0xFF, 0xF4, 0xDF)
TOMATO = (0xD9, 0x41, 0x2B)
BULB = (0xFF, 0xE9, 0xA8)


def master(size=1024):
    img = Image.new("RGB", (size, size), MUSTARD)
    d = ImageDraw.Draw(img)
    s = size / 1024
    border = int(26 * s)

    # Board with a hard ink drop shadow.
    x0, y0, x1, y1 = int(120 * s), int(210 * s), int(904 * s), int(780 * s)
    radius = int(90 * s)
    d.rounded_rectangle((x0, y0 + int(40 * s), x1, y1 + int(40 * s)), radius, fill=INK)
    d.rounded_rectangle((x0, y0, x1, y1), radius, fill=TOMATO, outline=INK, width=border)

    # Marquee bulbs along the top and bottom of the board.
    r = int(30 * s)
    for row_y in (y0 + int(78 * s), y1 - int(78 * s)):
        count = 6
        for i in range(count):
            cx = x0 + int(130 * s) + i * (x1 - x0 - int(260 * s)) / (count - 1)
            d.ellipse((cx - r, row_y - r, cx + r, row_y + r), fill=BULB, outline=INK, width=int(10 * s))

    # "SUS" with an ink outline.
    font = ImageFont.truetype(FONT, int(300 * s))
    text = "SUS"
    box = d.textbbox((0, 0), text, font=font, stroke_width=int(16 * s))
    tw, th = box[2] - box[0], box[3] - box[1]
    tx = (size - tw) / 2 - box[0]
    ty = (y0 + y1) / 2 - th / 2 - box[1]
    d.text((tx, ty), text, font=font, fill=CREAM, stroke_width=int(16 * s), stroke_fill=INK)

    # A little needle meter under the board.
    my = int(890 * s)
    d.rounded_rectangle((int(300 * s), my - int(26 * s), int(724 * s), my + int(26 * s)), int(26 * s),
                        fill=CREAM, outline=INK, width=int(12 * s))
    d.rounded_rectangle((int(300 * s), my - int(26 * s), int(610 * s), my + int(26 * s)), int(26 * s),
                        fill=TOMATO, outline=INK, width=int(12 * s))
    return img


def main():
    contents = json.load(open(os.path.join(ICONSET, "Contents.json")))
    big = master(1024)
    done = set()
    for image in contents["images"]:
        name = image.get("filename")
        if not name or name in done:
            continue
        points = float(image["size"].split("x")[0])
        scale = float(image["scale"].rstrip("x"))
        px = int(round(points * scale))
        big.resize((px, px), Image.LANCZOS).save(os.path.join(ICONSET, name), "PNG")
        done.add(name)
        print(f"{name}: {px}px")


if __name__ == "__main__":
    main()
