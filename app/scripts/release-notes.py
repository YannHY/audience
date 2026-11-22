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
{sections}  <footer><a href="../nouveautes.html">Toutes les nouveautés sur le site</a></footer>
</main>
</body>
</html>
'''


def site_release(entry, latest):
    when = (f'<time datetime="{escape(entry["date"])}">{french_date(entry["date"])}</time>'
            if entry.get('date') else '')
    pill = '<span class="nv-pill">Dernière version</span>' if latest else ''
    count = len(entry['notes'])
    label = f'{count} nouveauté{"s" if count > 1 else ""}'
    items = ''.join(f'\n                            <li>{escape(note)}</li>' for note in entry['notes'])
    return f'''                <article class="nv-release{' is-latest' if latest else ''} mac-reveal">
                    <header class="nv-meta">
                        <p class="nv-app">Audience</p>
                        <h2 class="nv-version">{escape(entry["version"])}</h2>
                        {when}
                        <p class="nv-count">{label}</p>
                        {pill}
                    </header>
                    <div class="nv-card">
                        <ul>{items}
                        </ul>
                    </div>
                </article>
'''


HISTORY_STYLE = '''
        .nv-hero { padding-bottom: clamp(40px, 6vw, 64px); }
        :root .page-mac .mac h1.nv-title { font-size: clamp(2.4rem, 6vw, 4.2rem); }
        .nv-history { padding: clamp(24px, 4vw, 48px) 0 clamp(72px, 10vw, 120px); }
        .nv-list { --nv-aside: 190px; --nv-gap: 72px; width: min(980px, calc(100% - 40px)); margin: 0 auto; }
        .nv-release { position: relative; display: grid; grid-template-columns: var(--nv-aside) 1fr; column-gap: var(--nv-gap); padding-bottom: 44px; }
        .nv-release::before { content: ''; position: absolute; left: calc(var(--nv-aside) + var(--nv-gap) / 2 - 1px); top: 0; bottom: 0; width: 2px; background: var(--mac-line); }
        .nv-release:first-child::before { top: 22px; background: linear-gradient(180deg, var(--mac-accent), var(--mac-line) 220px); }
        .nv-release:last-child::before { bottom: auto; height: 22px; }
        .nv-release:first-child:last-child::before { display: none; }
        .nv-release::after { content: ''; position: absolute; left: calc(var(--nv-aside) + var(--nv-gap) / 2 - 7px); top: 15px; width: 14px; height: 14px; border-radius: 50%; box-sizing: border-box; background: var(--mac-bg); border: 3px solid var(--mac-accent); }
        .nv-release.is-latest::after { border: 0; background: var(--mac-accent); box-shadow: 0 0 0 6px color-mix(in srgb, var(--mac-accent) 18%, transparent); }
        .nv-meta { text-align: right; padding-top: 4px; }
        .nv-meta p { margin: 0; }
        .nv-app { font-size: 0.85rem; font-weight: 600; color: var(--mac-ink-soft); text-transform: uppercase; letter-spacing: 0.08em; }
        :root .page-mac .mac h2.nv-version { font-size: 2.6rem; font-weight: 700; line-height: 1.05; letter-spacing: -0.04em; font-variant-numeric: tabular-nums; margin: 2px 0 6px; }
        :root .page-mac .mac .is-latest h2.nv-version { background: linear-gradient(100deg, #4f46e5 0%, #7c3aed 45%, #db2777 100%); -webkit-background-clip: text; background-clip: text; -webkit-text-fill-color: transparent; }
        .nv-meta time { display: block; font-size: 0.95rem; color: var(--mac-ink); }
        .nv-count { font-size: 0.85rem; color: var(--mac-ink-soft); }
        .nv-pill { display: inline-block; margin-top: 12px; padding: 4px 12px; border-radius: 999px; background: color-mix(in srgb, var(--mac-accent) 14%, transparent); color: var(--mac-accent); font-size: 0.8rem; font-weight: 600; }
        .nv-card { background: var(--mac-bg-alt); border: 1px solid var(--mac-line); border-radius: 22px; padding: 26px 30px 12px; }
        .is-latest .nv-card { background: linear-gradient(var(--mac-card), var(--mac-card)) padding-box, linear-gradient(120deg, #4f46e5, #7c3aed 50%, #db2777) border-box; border: 1.5px solid transparent; box-shadow: 0 24px 60px -30px rgba(79, 70, 229, 0.45); }
        .nv-card ul { list-style: none; margin: 0; padding: 0; }
        .nv-card li { position: relative; padding-left: 34px; margin: 0 0 16px; font-size: 1.04rem; line-height: 1.55; color: var(--mac-ink); }
        .nv-card li::before { content: ''; position: absolute; left: 0; top: 2px; width: 22px; height: 22px; border-radius: 50%; background: color-mix(in srgb, var(--mac-accent) 14%, transparent); }
        .nv-card li::after { content: ''; position: absolute; left: 8px; top: 7px; width: 5px; height: 9px; border: solid var(--mac-accent); border-width: 0 2px 2px 0; transform: rotate(45deg); }
        :root.theme-dark .page-mac .mac .is-latest h2.nv-version { background-image: linear-gradient(100deg, #a5b4fc 0%, #c084fc 50%, #f472b6 100%); }
        :root.theme-dark .is-latest .nv-card { background: linear-gradient(var(--mac-card), var(--mac-card)) padding-box, linear-gradient(120deg, #818cf8, #c084fc 50%, #f472b6) border-box; box-shadow: none; }
        @media (prefers-color-scheme: dark) {
            :root:not(.theme-light) .page-mac .mac .is-latest h2.nv-version { background-image: linear-gradient(100deg, #a5b4fc 0%, #c084fc 50%, #f472b6 100%); }
            :root:not(.theme-light) .is-latest .nv-card { background: linear-gradient(var(--mac-card), var(--mac-card)) padding-box, linear-gradient(120deg, #818cf8, #c084fc 50%, #f472b6) border-box; box-shadow: none; }
        }
        @media (max-width: 760px) {
            .nv-list { width: calc(100% - 32px); }
            .nv-release { grid-template-columns: 1fr; padding: 0 0 36px 30px; }
            .nv-release::before { left: 6px; }
            .nv-release::after { left: 0; top: 13px; }
            .nv-meta { text-align: left; display: flex; flex-wrap: wrap; align-items: baseline; gap: 2px 12px; margin-bottom: 14px; padding-top: 0; }
            .nv-app { flex-basis: 100%; }
            :root .page-mac .mac h2.nv-version { font-size: 2rem; margin: 0; }
            .nv-pill { margin-top: 0; }
            .nv-card { padding: 20px 20px 6px; border-radius: 18px; }
            .nv-card li { font-size: 1rem; }
        }
'''.rstrip()


def site_page(history):
    releases = ''.join(site_release(entry, index == 0) for index, entry in enumerate(history))
    return f'''<!DOCTYPE html>
<html lang="fr">
<head>
    <!-- Page générée par app/scripts/release-notes.py depuis app/Resources/ReleaseNotes.json : ne pas modifier à la main. -->
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nouveautés d’Audience</title>
    <meta name="description" content="L’évolution d’Audience pour Mac et iPad : toutes les versions et leurs nouveautés.">
    <link rel="icon" type="image/png" sizes="32x32" href="favicon-32.png?v=2">
    <link rel="icon" type="image/png" sizes="16x16" href="favicon-16.png?v=2">
    <link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png?v=2">
    <script>
        try {{
            const savedTheme = localStorage.getItem('audience-theme');
            if (savedTheme === 'dark') {{
                document.documentElement.classList.add('theme-dark');
            }} else if (savedTheme === 'light') {{
                document.documentElement.classList.add('theme-light');
            }} else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {{
                document.documentElement.classList.add('theme-dark');
            }}
        }} catch (_) {{}}
    </script>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Pacifico&display=swap" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css" referrerpolicy="no-referrer">
    <link rel="stylesheet" href="styles.css?v=20261121y">
    <link rel="stylesheet" href="app.css?v={SITE_CSS_VERSION}">
    <style>
{HISTORY_STYLE}
    </style>
</head>
<body class="page-mac">
    <div id="accountBar" class="account-bar"></div>

    <main class="mac">
        <section class="mac-hero nv-hero">
            <div class="mac-wrap">
                <picture>
                    <source srcset="img/app/icone-sombre.png" media="(prefers-color-scheme: dark)" data-dark-source>
                    <img class="mac-hero-icon" src="img/app/icone.png" alt="" width="128" height="128">
                </picture>
                <p class="mac-eyebrow">Audience pour Mac et iPad</p>
                <h1 class="mac-hero-title nv-title">Toutes les<br><span class="mac-gradient">nouveautés</span></h1>
                <p class="mac-lede">L’évolution d’Audience, version après version. Les mises à jour s’installent automatiquement depuis l’application.</p>
                <div class="mac-cta">
                    <a class="mac-button" href="mac/Audience-macOS.zip" download>
                        <i class="fa-brands fa-apple" aria-hidden="true"></i>
                        Télécharger la version {escape(history[0]["version"])}
                    </a>
                    <a class="mac-link" href="app.html">Découvrir l’application</a>
                </div>
            </div>
        </section>

        <section class="nv-history" aria-label="Historique des versions">
            <div class="nv-list">
{releases}            </div>
        </section>
    </main>

    <footer class="footer" data-site-footer></footer>

    <script src="site-nav.js?v=20261121v"></script>
    <script src="site-footer.js?v=20261121b"></script>
    <script src="theme.js?v=20261122a"></script>
    <script>
        (function() {{
            const root = document.documentElement;
            const sources = document.querySelectorAll('source[data-dark-source]');
            function syncSources() {{
                const media = root.classList.contains('theme-dark') ? 'all'
                    : root.classList.contains('theme-light') ? 'not all'
                    : '(prefers-color-scheme: dark)';
                sources.forEach(function(source) {{ source.media = media; }});
            }}
            syncSources();
            new MutationObserver(syncSources).observe(root, {{ attributes: true, attributeFilter: ['class'] }});
        }})();

        const revealed = document.querySelectorAll('.mac-reveal');
        if ('IntersectionObserver' in window) {{
            const observer = new IntersectionObserver(function(entries) {{
                entries.forEach(function(entry) {{
                    if (entry.isIntersecting) {{
                        entry.target.classList.add('is-visible');
                        observer.unobserve(entry.target);
                    }}
                }});
            }}, {{ rootMargin: '0px 0px -8% 0px', threshold: 0.08 }});
            revealed.forEach(function(element) {{ observer.observe(element); }});
        }} else {{
            revealed.forEach(function(element) {{ element.classList.add('is-visible'); }});
        }}
    </script>
</body>
</html>
'''


SITE_CSS_VERSION = '20261122a'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path, nargs='?')
    parser.add_argument('--max-build', type=int)
    parser.add_argument('--site', type=Path, help='écrit aussi la page « Nouveautés » du site à cet emplacement')
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
    if args.site:
        released = [entry for entry in entries if entry['build'] <= max_build]
        args.site.write_text(site_page(released))
        print(args.site)
    for index, entry in enumerate(entries if args.directory else []):
        name = f'Audience-{entry["version"]}-{entry["build"]}-macOS'
        if entry['build'] > max_build or not (args.directory / f'{name}.zip').is_file():
            continue
        (args.directory / f'{name}.html').write_text(page(entries[index:]))
        print(f'{name}.html')


if __name__ == '__main__':
    main()
