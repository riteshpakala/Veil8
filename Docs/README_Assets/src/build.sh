#!/bin/zsh
# Rebuilds the README's hero, Docs/README_Assets/hero.png, from HTML rendered by Google Chrome through
# Playwright (pip install playwright; it drives the installed Chrome), as Braid's README images are.
set -euo pipefail
repo=${0:A:h:h:h:h}
cd "$repo"
python3 -I Docs/README_Assets/src/build.py Docs/README_Assets
