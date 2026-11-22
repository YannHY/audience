#!/usr/bin/env python3
"""Write the Sparkle release-notes pages from Resources/ReleaseNotes.json.

Sparkle only shows the notes of the newest item, so every page carries the
whole history up to its own version: someone updating from an older build
still sees everything they skipped.

Usage: release-notes.py DIRECTORY [--max-build N]
A page is written for each version whose ZIP is present in DIRECTORY and whose
build does not exceed N (by default the build in Resources/Info.plist).
"""
from datetime import date
from html import escape
from pathlib import Path
import argparse
import json
import plistlib

APP = Path(__file__).resolve().parents[1]
MONTHS = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
          'août', 'septembre', 'octobre', 'novembre', 'décembre']

STYLE = '''
:root {
  --ink: #1d1d1f; --ink-soft: #6e6e73; --bg: #ffffff; --bg-alt: #f5f5f7;
  --card: #ffffff; --line: rgba(0, 0, 0, 0.08); --accent: #4f46e5;
  --accent-soft: rgba(79, 70, 229, 0.1);
  --gradient: linear-gradient(100deg, #4f46e5 0%, #7c3aed 45%, #db2777 100%);
  --shadow: 0 18px 40px -24px rgba(15, 23, 42, 0.25);
  color-scheme: light dark;
}
@media (prefers-color-scheme: dark) {
  :root:not(.theme-light) {
    --ink: #f5f5f7; --ink-soft: #a1a1a6; --bg: #000000; --bg-alt: #101012;
    --card: #1c1c1e; --line: rgba(255, 255, 255, 0.1); --accent: #818cf8;
    --accent-soft: rgba(129, 140, 248, 0.16);
    --gradient: linear-gradient(100deg, #a5b4fc 0%, #c084fc 50%, #f472b6 100%);
    --shadow: 0 0 0 1px rgba(255, 255, 255, 0.08);
  }
}
:root.theme-dark {
  --ink: #f5f5f7; --ink-soft: #a1a1a6; --bg: #000000; --bg-alt: #101012;
  --card: #1c1c1e; --line: rgba(255, 255, 255, 0.1); --accent: #818cf8;
  --accent-soft: rgba(129, 140, 248, 0.16);
  --gradient: linear-gradient(100deg, #a5b4fc 0%, #c084fc 50%, #f472b6 100%);
  --shadow: 0 0 0 1px rgba(255, 255, 255, 0.08);
}
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body {
  margin: 0; background: var(--bg-alt); color: var(--ink);
  font: 15px/1.5 -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Inter', 'Segoe UI', Roboto, sans-serif;
  letter-spacing: -0.01em;
}
main { width: min(680px, calc(100% - 32px)); margin: 0 auto; padding: 28px 0 32px; }
header { display: flex; align-items: center; gap: 14px; margin-bottom: 22px; }
header img { width: 56px; height: 56px; flex: none; filter: drop-shadow(0 8px 16px rgba(15, 23, 42, 0.18)); }
.brand { margin: 0; font-family: 'Pacifico', 'Brush Script MT', cursive; font-size: 1.05rem; color: var(--ink-soft); line-height: 1.3; }
h1 {
  margin: 0; font-size: 1.9rem; line-height: 1.1; letter-spacing: -0.03em; font-weight: 700;
  background: var(--gradient); -webkit-background-clip: text; background-clip: text; -webkit-text-fill-color: transparent;
}
section {
  background: var(--card); border: 1px solid var(--line); border-radius: 18px;
  padding: 18px 20px 6px; margin-bottom: 14px; box-shadow: var(--shadow);
}
.head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 10px; margin-bottom: 4px; }
h2 { margin: 0; font-size: 1.15rem; letter-spacing: -0.02em; }
time { color: var(--ink-soft); font-size: 0.85rem; }
.pill {
  margin-left: auto; padding: 2px 10px; border-radius: 999px;
  background: var(--accent-soft); color: var(--accent); font-size: 0.75rem; font-weight: 600;
}
ul { margin: 0; padding: 0 0 0 1.1em; }
li { margin: 0 0 12px; }
li::marker { color: var(--accent); }
footer { margin-top: 20px; text-align: center; font-size: 0.85rem; color: var(--ink-soft); }
footer a { color: var(--accent); text-decoration: none; }
footer a:hover { text-decoration: underline; }
'''.strip()

THEME = ("try{const t=localStorage.getItem('audience-theme');"
         "if(t==='dark')document.documentElement.classList.add('theme-dark');"
         "else if(t==='light')document.documentElement.classList.add('theme-light');}catch(_){}")


def french_date(value):
    day = date.fromisoformat(value)
    return f'{"1er" if day.day == 1 else day.day} {MONTHS[day.month - 1]} {day.year}'


def section(entry, current):
    when = (f'<time datetime="{escape(entry["date"])}">{french_date(entry["date"])}</time>'
            if entry.get('date') else '')
    pill = '<span class="pill">Cette version</span>' if current else ''
    items = ''.join(f'\n      <li>{escape(note)}</li>' for note in entry['notes'])
    return (f'  <section>\n    <div class="head"><h2>Audience {escape(entry["version"])}</h2>{when}{pill}</div>\n'
            f'    <ul>{items}\n    </ul>\n  </section>\n')


def page(history):
    current = history[0]
    sections = ''.join(section(entry, index == 0) for index, entry in enumerate(history))
    return f'''<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Audience {escape(current["version"])} – Nouveautés</title>
<script>{THEME}</script>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Pacifico&display=swap" rel="stylesheet">
<style>
{STYLE}
</style>
</head>
<body>
<main>
  <header>
    <picture><source srcset="../img/app/icone-sombre.png" media="(prefers-color-scheme: dark)"><img src="../img/app/icone.png" alt="" width="56" height="56"></picture>
    <div><p class="brand">Audience pour Mac</p><h1>Nouveautés</h1></div>
  </header>
{sections}  <footer><a href="../app.html">Découvrir Audience pour Mac et iPad</a></footer>
</main>
</body>
</html>
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--max-build', type=int)
    args = parser.parse_args()
    max_build = args.max_build
    if max_build is None:
        with (APP / 'Resources/Info.plist').open('rb') as stream:
            max_build = int(plistlib.load(stream)['CFBundleVersion'])
    entries = json.loads((APP / 'Resources/ReleaseNotes.json').read_text())
    entries.sort(key=lambda entry: entry['build'], reverse=True)
    builds = [entry['build'] for entry in entries]
    assert len(builds) == len(set(builds)), 'Numéro de build en double dans ReleaseNotes.json'
    if max_build not in builds:
        raise SystemExit(f'Aucune note de version pour le build {max_build} dans Resources/ReleaseNotes.json.')
    for index, entry in enumerate(entries):
        name = f'Audience-{entry["version"]}-{entry["build"]}-macOS'
        if entry['build'] > max_build or not (args.directory / f'{name}.zip').is_file():
            continue
        (args.directory / f'{name}.html').write_text(page(entries[index:]))
        print(f'{name}.html')


if __name__ == '__main__':
    main()
