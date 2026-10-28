"""Builds the README's hero from HTML, rendered by the installed Google Chrome through Playwright.

    Docs/README_Assets/src/build.sh       # runs this

Inputs:  this folder's rr-mark.png; Playfair Display Italic from ~/Library/Fonts; the golden
         vector's first words, from Tests/Veil8Tests/Fixtures/rgb-veil8.json.
Outputs: hero.png in argv[1], 2400×1260 (1200×630 at scale 2), in the style of Braid's hero.
"""

import json
import math
import os
import sys
import tempfile

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(sys.argv[1])
FIXTURE = os.path.join(HERE, "..", "..", "..", "Tests", "Veil8Tests", "Fixtures", "rgb-veil8.json")
PLAYFAIR = os.path.expanduser("~/Library/Fonts/PlayfairDisplay-Italic-VariableFont_wght.ttf")

# Braid's hero colours (RaoLM's og-image), with a red for the picture's red channel.
RED, GREEN, BLUE, GOLD, LINE = "#d4625b", "#28a883", "#5e8fda", "#c7a659", "#cbc8c0"

Y = 469          # the motif's centre line, as in Braid's hero
VEIL = (566, 618)  # where the strands go in and the words come out
WORDS_END = 1040   # the words stop here; a short line runs on to the gold mark at 1102

# The mark's ink, the strands, the subtitle and the legend start at x 66.
# The title's and the subtitle's first ink sit on EDGE: an italic first glyph overhangs, or sits in, by its own
# amount, so the page measures it with the font and places each line by it.
EDGE = 66
ALIGN = f"""document.fonts.ready.then(() => {{ const ctx = document.createElement('canvas').getContext('2d');
    for (const el of document.querySelectorAll('.title, .sub')) {{ const cs = getComputedStyle(el), text = el.textContent.trim();
        ctx.font = `italic ${{cs.fontWeight}} ${{cs.fontSize}} Playfair`;
        el.style.left = ({EDGE} - parseFloat(cs.paddingLeft) + ctx.measureText(text[0]).actualBoundingBoxLeft) + 'px'; }} }})"""


def shoot(browser, page_html, path, viewport=(1200, 630), scale=2, prepare=None):
    """Writes `page_html` beside the inputs (so relative URLs resolve) and screenshots it, after
    the fonts load and `prepare` (JavaScript) has run."""
    with tempfile.NamedTemporaryFile("w", suffix=".html", dir=HERE, delete=False, encoding="utf-8") as f:
        f.write(page_html)
        name = f.name
    try:
        page = browser.new_page(device_scale_factor=scale, viewport={"width": viewport[0], "height": viewport[1]})
        page.goto("file://" + name)
        page.evaluate("document.fonts.ready.then(() => true)")
        page.evaluate(ALIGN)
        if prepare:
            page.evaluate(prepare)
        page.wait_for_timeout(150)
        page.screenshot(path=path, full_page=True)
        page.close()
    finally:
        os.unlink(name)


def strand_path(phase, x0=68, x1=VEIL[0], y=Y, amplitude=40, period=184):
    """A strand that narrows into the centre line as it reaches the veil (Braid's braid)."""
    points = []
    x = x0
    while x <= x1:
        t = (x - x0) / (x1 - x0)
        a = amplitude * (1 - t) ** 1.25
        points.append((x, y + a * math.sin(2 * math.pi * (x - x0) / period + phase)))
        x += 3
    return "M" + " L".join(f"{px:.1f},{py:.1f}" for px, py in points)


def veil():
    """A curtain of fine vertical threads, each with a slight fold, fading at both ends."""
    threads = []
    x0, x1 = VEIL
    count = 10
    for i in range(count):
        x = x0 + (x1 - x0) * i / (count - 1)
        points = []
        for step in range(0, 61):
            y = Y - 62 + 124 * step / 60
            fold = 2.2 * math.sin(2 * math.pi * (y - Y) / 70 + i * 0.9)
            points.append(f"{x + fold:.1f},{y:.1f}")
        opacity = 0.16 + 0.22 * math.sin(math.pi * (i + 0.5) / count)
        threads.append(f'<polyline points="{" ".join(points)}" fill="none" stroke="{LINE}" '
                       f'stroke-width="1.15" stroke-opacity="{opacity:.2f}" mask="url(#fade)"/>')
    return "".join(threads)


def hero(browser, words):
    strands = "".join(
        f'<path d="{strand_path(phase)}" fill="none" stroke="url(#into-{name})" stroke-width="3.6" stroke-linecap="round"/>'
        for name, phase in [("red", math.pi * 0.62), ("green", math.pi * 1.95), ("blue", math.pi * 1.28)])
    gradients = "".join(
        f'<linearGradient id="into-{name}" gradientUnits="userSpaceOnUse" x1="68" y1="0" x2="{VEIL[0]}" y2="0">'
        f'<stop offset="0" stop-color="{colour}"/><stop offset="0.78" stop-color="{colour}"/>'
        f'<stop offset="1" stop-color="{colour}" stop-opacity="0.18"/></linearGradient>'
        for name, colour in [("red", RED), ("green", GREEN), ("blue", BLUE)])
    page = f"""<!doctype html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: "Playfair"; font-style: italic; font-weight: 400 900; src: url("file://{PLAYFAIR}") format("truetype"), local("Playfair Display Italic"); }}
html, body {{ margin: 0; width: 1200px; height: 630px; overflow: hidden; }}
body {{ position: relative; font-family: "Playfair", Georgia, serif; font-style: italic;
       background: radial-gradient(ellipse 90% 100% at 22% 20%, #20201c 0%, #191917 45%, #121211 100%); }}
.mark {{ position: absolute; left: 57.5px; top: 52px; width: 72px; }}
.caption {{ position: absolute; left: 143.5px; top: 72px; letter-spacing: .3em; font-size: 16.5px; color: #8b8a84; font-variant-numeric: lining-nums; }}
.title {{ position: absolute; left: 34px; top: 112px; padding-left: 40px; font-size: 220px; line-height: 1; font-weight: 500; letter-spacing: -.005em;
         font-variant-numeric: lining-nums;
         background: linear-gradient(100deg, #8d9097 0%, #c8cad0 35%, #f2f3f6 58%, #b6b9c1 100%);
         -webkit-background-clip: text; background-clip: text; color: transparent; padding-right: 30px; }}
.sub {{ position: absolute; left: 65.5px; top: 334px; font-size: 45px; color: #9b9991; }}
svg {{ position: absolute; left: 0; top: 0; }}
.words {{ position: absolute; left: {VEIL[1] + 22}px; top: {Y - 21}px; height: 40px;
          white-space: nowrap; font-size: 31px; line-height: 40px; letter-spacing: .02em; word-spacing: .12em; color: {LINE};
          -webkit-mask-image: linear-gradient(90deg, rgba(0,0,0,.45) 0%, #000 24%); }}
.legend {{ position: absolute; left: 66px; top: 543px; width: 1050px; display: flex; gap: 32px; align-items: baseline; font-size: 24px; color: #8b8a84;
           font-variant-numeric: lining-nums; }}
.legend b {{ font-weight: 400; color: #e9e7e0; }}
.dot {{ display: inline-block; width: 13px; height: 13px; border-radius: 50%; margin-right: 10px; transform: translateY(-1px); }}
.dots {{ display: inline-flex; margin-right: 10px; transform: translateY(-1px); }}
.dots .dot {{ margin-right: -4px; box-shadow: 0 0 0 2px #191917; }}
.dots .dot:last-child {{ margin-right: 0; }}
.threads {{ display: inline-block; width: 15px; height: 17px; margin-right: 10px; transform: translateY(2px); }}
.tag {{ margin-left: auto; }}
</style></head><body>
<img class="mark" src="rr-mark.png">
<div class="caption">A ONE-WAY IMAGE ENCODING</div>
<div class="title">Veil8</div>
<div class="sub">every pixel, eight keyed bits, and no way back</div>
<svg width="1200" height="630">
  <defs>{gradients}
    <linearGradient id="fade-y" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="0.3" stop-color="#fff"/>
      <stop offset="0.7" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
    <mask id="fade" maskUnits="userSpaceOnUse" x="0" y="{Y - 70}" width="1200" height="140">
      <rect x="0" y="{Y - 62}" width="1200" height="124" fill="url(#fade-y)"/></mask>
    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="{LINE}" stop-opacity="0.10"/><stop offset="1" stop-color="{LINE}" stop-opacity="0"/></radialGradient>
  </defs>
  <ellipse cx="{sum(VEIL) / 2}" cy="{Y}" rx="56" ry="70" fill="url(#glow)"/>
  {strands}
  {veil()}
  <line id="tail" x1="{WORDS_END}" y1="{Y}" x2="1092" y2="{Y}" stroke="{LINE}" stroke-width="3" stroke-linecap="round"/>
  <circle cx="1102" cy="{Y}" r="9.5" fill="none" stroke="{GOLD}" stroke-width="2.4"/>
  <circle cx="1102" cy="{Y}" r="4" fill="{GOLD}"/>
</svg>
<div class="words">{" ".join(words)}</div>
<div class="legend">
  <span><i class="dots"><i class="dot" style="background:{RED}"></i><i class="dot" style="background:{GREEN}"></i><i class="dot" style="background:{BLUE}"></i></i><b>Pixels</b> · 5×5 RGB</span>
  <span><svg class="threads" viewBox="0 0 15 17" style="position:static"><path d="M2 1 V16 M7.5 1 V16 M13 1 V16" stroke="{LINE}" stroke-width="1.4" stroke-opacity=".7"/></svg><b>Key</b> · 32 bytes</span>
  <span><i class="dot" style="background:{LINE}"></i><b>Words</b> · 8 bits each</span>
  <span class="tag">similar pictures, similar words</span>
</div>
</body></html>"""
    # Drop words from the end until the last one ends short of the gold mark, then run Braid's
    # silver line from the last word into the mark.
    fit = f"""(() => {{ const w = document.querySelector('.words'); const limit = {WORDS_END};
        while (w.getBoundingClientRect().right > limit) w.textContent = w.textContent.replace(/ ?\\S+$/, '');
        document.getElementById('tail').setAttribute('x1', String(Math.round(w.getBoundingClientRect().right + 16))); }})()"""
    shoot(browser, page, os.path.join(OUT, "hero.png"), prepare=fit)


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(FIXTURE, encoding="utf-8") as f:
        words = json.load(f)["head"].split()
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome")
        hero(browser, words)
        browser.close()
    path = os.path.join(OUT, "hero.png")
    with Image.open(path) as im:
        print(f"hero.png: {im.size[0]}×{im.size[1]}, {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    main()
