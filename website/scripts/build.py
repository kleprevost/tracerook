#!/usr/bin/env python3
"""Generate portable static HTML. Python standard library only; no runtime server."""
import html
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
CONTENT = ROOT / "content"
SITE_URL = "https://tracerook.dev"
RELEASE = "0.1.0-beta.1"
sys.path.insert(0, str(CONTENT))
from pages import PAGES, WALKTHROUGH

# Standalone pages: (route, content file, title, description, active nav key, form page)
STANDALONE = [
    ("/pricing/", "pricing.html", "Pricing", "TraceRook is in an invitation-only private beta. The planned price is $5/month, including TraceRook Cloud analysis with Anthropic Claude.", "pricing", False),
    ("/register/", "register.html", "Request an invitation", "Request an invitation to the TraceRook private beta.", "register", True),
]


def esc(value):
    return html.escape(str(value), quote=True)


def current(active, key):
    return 'aria-current="page"' if active == key else ''


def header(active=""):
    return f'''<a class="skip" href="#main">Skip to content</a>
<header class="site-header"><div class="nav-shell">
<a class="brand" href="/" aria-label="TraceRook home"><img src="/assets/tracerook.png" alt="" width="36" height="36">TraceRook</a>
<button class="menu-toggle" aria-expanded="false" aria-controls="main-nav">Menu</button>
<nav id="main-nav" aria-label="Main navigation"><a href="/#how-it-works">How it works</a><a href="/#about">About</a><a href="/pricing/" {current(active, 'pricing')}>Pricing</a><a href="/docs/" {current(active, 'docs')}>Documentation</a><a class="nav-cta" href="/register/" {current(active, 'register')}>Request an invitation</a></nav>
</div></header>'''


def footer():
    return f'''<footer class="site-footer"><div class="footer-top"><a class="brand" href="/"><img src="/assets/tracerook.png" alt="" width="32" height="32">TraceRook</a><p>Independent judgment. Before the next tool call.</p><div><a href="/#about">About</a><a href="/pricing/">Pricing</a><a href="/docs/">Documentation</a><a href="/docs/privacy/">Privacy</a><a href="mailto:kyle@tracerook.dev">Contact</a><a href="https://github.com/kleprevost/tracerook">GitHub</a></div></div><div class="footer-bottom"><span>© 2026 TraceRook</span><span>Private beta {RELEASE} · Native macOS · Apple Silicon</span><span>Claude is a product of Anthropic. No affiliation or endorsement implied.</span></div></footer>'''


def shell(title, description, body, active="", extra="", path="/", forms=False):
    if path is not None:
        extra += f'<link rel="canonical" href="{SITE_URL}{esc(path)}"><meta property="og:url" content="{SITE_URL}{esc(path)}">'
    form_action = "'self'" if forms else "'none'"
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="dark"><meta name="description" content="{esc(description)}"><meta name="referrer" content="strict-origin-when-cross-origin"><meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action {form_action}"><title>{esc(title)} · TraceRook</title><meta property="og:title" content="{esc(title)} · TraceRook"><meta property="og:description" content="{esc(description)}"><meta property="og:type" content="website"><meta property="og:site_name" content="TraceRook"><meta property="og:image" content="{SITE_URL}/assets/tracerook-social.png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="TraceRook: Let your agent build. Keep the next move in check."><meta name="twitter:card" content="summary_large_image"><link rel="icon" href="/assets/tracerook.png" type="image/png"><link rel="apple-touch-icon" href="/assets/apple-touch-icon.png"><link rel="stylesheet" href="/assets/site.css"><script src="/assets/site.js" defer></script>{extra}<noscript><style>@media(max-width:1000px){{.site-header{{height:auto;position:static}}.nav-shell{{flex-wrap:wrap;padding:18px 0}}.site-header nav{{display:flex;position:static;width:100%;padding:12px 0;background:transparent}}.menu-toggle,.docs-toggle{{display:none}}.docs-sidebar nav{{display:block;max-height:none}}}}</style></noscript></head><body>{header(active)}{body}{footer()}</body></html>'''


def write(route, document):
    out = DIST / route.strip('/') if route != '/' else DIST
    out.mkdir(parents=True, exist_ok=True)
    (out / 'index.html').write_text(document)


def build_home():
    body = (CONTENT / "home.html").read_text().replace("<!-- PRODUCT_WALKTHROUGH -->", WALKTHROUGH)
    write('/', shell("A second look before your agent acts", "TraceRook stops risky Claude Code actions before they run. Local rules on your Mac, contextual analysis with Anthropic Claude, and a native review for every high-risk call.", body))


def build_standalone():
    for route, source, title, description, active, forms in STANDALONE:
        body = (CONTENT / source).read_text()
        write(route, shell(title, description, body, active, path=route, forms=forms))


def build_docs():
    groups = list(dict.fromkeys(p["group"] for p in PAGES))
    for i, p in enumerate(PAGES):
        nav = ''
        for group in groups:
            nav += f'<div class="doc-group"><p>{esc(group)}</p>'
            for page in PAGES:
                if page['group'] == group:
                    selected = 'aria-current="page"' if page is p else ''
                    nav += f'<a href="/docs/{page["slug"]}/" {selected}>{esc(page["title"])}</a>'
            nav += '</div>'
        sections = ''.join(f'<section id="{s[0]}"><h2><a href="#{s[0]}">{esc(s[1])}</a></h2>{s[2]}</section>' for s in p['sections'])
        toc = ''.join(f'<a href="#{s[0]}">{esc(s[1])}</a>' for s in p['sections'])
        adjacent = '<nav class="doc-adjacent" aria-label="Adjacent documentation">'
        for index, label in ((i-1, 'Previous'), (i+1, 'Next')):
            if 0 <= index < len(PAGES):
                q = PAGES[index]
                adjacent += f'<a href="/docs/{q["slug"]}/"><small>{label}</small><strong>{esc(q["title"])}</strong></a>'
        adjacent += '</nav>'
        body = f'''<div class="docs-layout"><aside class="docs-sidebar"><div class="docs-top"><a href="/docs/">Documentation</a><button class="docs-toggle" aria-expanded="false" aria-controls="docs-nav">Browse topics</button></div><nav id="docs-nav" aria-label="Documentation">{nav}</nav></aside><main id="main" class="doc-main"><div class="doc-eyebrow">{esc(p['group'])} <span>Beta {RELEASE}</span></div><h1>{esc(p['title'])}</h1><p class="doc-lead">{esc(p['description'])}</p><div class="mobile-toc"><details><summary>On this page</summary>{toc}</details></div><article class="doc-article">{sections}</article>{adjacent}</main><aside class="docs-toc" aria-label="On this page"><p>On this page</p>{toc}<a class="toc-bottom" href="/register/">Request an invitation</a></aside></div>'''
        write(f'/docs/{p["slug"]}/', shell(p['title'], p['description'], body, 'docs', path=f'/docs/{p["slug"]}/'))
    cards = ''
    for group in groups:
        cards += f'<section class="docs-collection"><h2>{esc(group)}</h2><div class="docs-card-grid">'
        for page in PAGES:
            if page['group'] == group:
                cards += f'<a class="doc-card" href="/docs/{page["slug"]}/"><h3>{esc(page["title"])}</h3><p>{esc(page["description"])}</p><span>Read guide</span></a>'
        cards += '</div></section>'
    body = f'''<main id="main" class="docs-index wrap"><div class="eyebrow">The TraceRook field guide</div><h1>Understand every<br><span class="muted">decision.</span></h1><p class="intro">Install the beta, connect TraceRook Cloud, and learn how local rules, Claude analysis and native review work together to keep your agent on task.</p>{WALKTHROUGH}<div class="search-area"><label for="doc-search">Search documentation</label><div class="search-box"><input id="doc-search" type="search" placeholder="Try install, privacy, or Allow once…" autocomplete="off"><kbd>/</kbd></div><p id="search-status" role="status" aria-live="polite"></p><div id="search-results" hidden></div><noscript><p>Browse the guides below. Search requires JavaScript; every guide is available without it.</p></noscript></div><div id="doc-collections">{cards}</div></main>'''
    write('/docs/', shell('Documentation', 'TraceRook guides for installation, TraceRook Cloud, Claude analysis, privacy, approvals and Claude Code.', body, 'docs', path='/docs/'))
    index = [{"title": p['title'], "url": f"/docs/{p['slug']}/", "group": p['group'], "description": p['description'],
              "text": re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', ' '.join(s[2] for s in p['sections'])))).strip()} for p in PAGES]
    (DIST/'assets'/'search-index.json').write_text(json.dumps(index, ensure_ascii=False))


def build():
    DIST.mkdir(exist_ok=True)
    # Generated routes are rebuilt from scratch; assets and _headers are hand-maintained.
    for generated in ('docs', 'pricing', 'register', 'login', 'reference'):
        shutil.rmtree(DIST / generated, ignore_errors=True)
    build_home()
    build_standalone()
    build_docs()
    (DIST/'404.html').write_text(shell('Page not found', 'Find your way back to TraceRook.', '<main id="main" class="not-found wrap"><div class="eyebrow">404 / Off the board</div><h1>This page moved<br>out of play.</h1><p>Find what you need in the documentation, or start at home.</p><div class="button-row"><a class="button primary" href="/">Back to TraceRook</a><a class="button" href="/docs/">Browse documentation</a></div></main>', extra='<meta name="robots" content="noindex">', path=None))
    routes = ['/', '/pricing/', '/register/', '/docs/'] + [f'/docs/{page["slug"]}/' for page in PAGES]
    (DIST/'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'  <url><loc>{SITE_URL}{route}</loc></url>\n' for route in routes) + '</urlset>\n')
    (DIST/'robots.txt').write_text(f'User-agent: *\nAllow: /\nSitemap: {SITE_URL}/sitemap.xml\n')
    print(f'Generated homepage, {len(STANDALONE)} standalone pages, documentation index, {len(PAGES)} guides, and 404 page.')


if __name__ == '__main__':
    build()
