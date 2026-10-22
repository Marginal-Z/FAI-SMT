#!/usr/bin/env python3
"""Renders the app icon (assets/icon/source/*.svg, from the 多尺寸预览 design,
variant A) with headless Chrome and writes the launcher icons for Android,
Windows and Linux.

    python3 tool/gen_icons.py
"""
import os
import subprocess
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'assets', 'icon', 'source')


def render(name, tmp):
    out = os.path.join(tmp, name + '.png')
    subprocess.run([
        'google-chrome', '--headless=new', '--no-sandbox', '--disable-gpu', '--hide-scrollbars',
        '--default-background-color=00000000', '--window-size=1024,1024',
        '--screenshot=' + out, 'file://' + os.path.join(SRC, name + '.svg'),
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return Image.open(out).convert('RGBA')


def save(img, size, *path):
    target = os.path.join(ROOT, *path)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(target)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        full, full_b, bg, fg = (render(n, tmp) for n in ('full_A', 'full_B', 'bg_A', 'fg'))

    res = ('android', 'app', 'src', 'main', 'res')
    for density, scale in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
        save(full, round(48 * scale), *res, 'mipmap-' + density, 'ic_launcher.png')
        save(fg, round(108 * scale), *res, 'mipmap-' + density, 'ic_launcher_foreground.png')
        save(bg, round(108 * scale), *res, 'mipmap-' + density, 'ic_launcher_background.png')
    with open(os.path.join(ROOT, *res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')

    ico = os.path.join(ROOT, 'windows', 'runner', 'resources', 'app_icon.ico')
    full.save(ico, sizes=[(s, s) for s in (16, 20, 24, 32, 40, 48, 64, 128, 256)])

    save(full, 256, 'assets', 'icon', 'app_icon.png')
    save(full, 64, 'assets', 'icon', 'app_icon_64.png')
    save(full, 1024, 'assets', 'icon', 'app_icon_1024.png')
    save(full_b, 1024, 'assets', 'icon', 'app_icon_b_1024.png')


if __name__ == '__main__':
    main()
