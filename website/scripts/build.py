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
SITE_URL = "https://tracerook.dev"
sys.path.insert(0, str(ROOT / "content"))
from pages import PAGES

def esc(value):
    return html.escape(str(value), quote=True)

def header(active=""):
    return f'''<a class="skip" href="#main">Skip to content</a>
<header class="site-header"><div class="nav-shell">
<a class="brand" href="/" aria-label="TraceRook home"><img src="/assets/tracerook.png" alt="" width="36" height="36">TraceRook</a>
<button class="menu-toggle" aria-expanded="false" aria-controls="main-nav">Menu</button>
<nav id="main-nav" aria-label="Main navigation"><a href="/#how-it-works">How it works</a><a href="/docs/privacy/">Privacy</a><a href="/docs/" {('aria-current="page"' if active == 'docs' else '')}>Documentation</a><a class="nav-cta" href="/docs/quickstart/">Explore the preview</a></nav>
</div></header>'''

def footer():
    return '''<footer class="site-footer"><div class="footer-top"><a class="brand" href="/"><img src="/assets/tracerook.png" alt="" width="32" height="32">TraceRook</a><p>Independent judgment. Before the next tool call.</p><div><a href="/docs/">Documentation</a><a href="/docs/roadmap/">Release status</a><a href="https://github.com/kleprevost/tracerook">GitHub</a></div></div><div class="footer-bottom"><span>© 2026 TraceRook</span><span>Native macOS · Apple Silicon · MVP2 development preview</span><span>Claude is a product of Anthropic. No affiliation or endorsement implied.</span></div></footer>'''

def shell(title, description, body, active="", extra="", path="/"):
    if path is not None:
        extra += f'<link rel="canonical" href="{SITE_URL}{esc(path)}"><meta property="og:url" content="{SITE_URL}{esc(path)}">'
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="dark"><meta name="description" content="{esc(description)}"><meta name="referrer" content="strict-origin-when-cross-origin"><meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'"><title>{esc(title)} · TraceRook</title><meta property="og:title" content="{esc(title)} · TraceRook"><meta property="og:description" content="{esc(description)}"><meta property="og:type" content="website"><link rel="icon" href="/assets/tracerook.png" type="image/png"><link rel="stylesheet" href="/assets/site.css"><script src="/assets/site.js" defer></script>{extra}<noscript><style>@media(max-width:680px){{.site-header{{height:auto;position:static}}.nav-shell{{flex-wrap:wrap;padding:18px 0}}.site-header nav{{display:flex;position:static;width:100%;padding:12px 0;background:transparent}}.menu-toggle,.docs-toggle{{display:none}}.docs-sidebar nav{{display:block;max-height:none}}}}</style></noscript></head><body>{header(active)}{body}{footer()}</body></html>'''

def build_home():
    body = (ROOT / "content" / "home.html").read_text()
    (DIST / "index.html").write_text(shell("A second look before your agent acts", "Native macOS guardrails designed around local policy and Anthropic Claude. Explore the native demo and completed MVP2 foundation; live protection remains pending.", body))

def build_docs():
    groups = list(dict.fromkeys(p["group"] for p in PAGES))
    for i, p in enumerate(PAGES):
        nav = ''
        for group in groups:
            nav += f'<div class="doc-group"><p>{esc(group)}</p>'
            for page in PAGES:
                if page['group'] == group:
                    current = 'aria-current="page"' if page is p else ''
                    nav += f'<a href="/docs/{page["slug"]}/" {current}>{esc(page["title"])}</a>'
            nav += '</div>'
        sections = ''.join(f'<section id="{s[0]}"><h2><a href="#{s[0]}">{esc(s[1])}</a></h2>{s[2]}</section>' for s in p['sections'])
        toc = ''.join(f'<a href="#{s[0]}">{esc(s[1])}</a>' for s in p['sections'])
        adjacent = '<nav class="doc-adjacent" aria-label="Adjacent documentation">'
        for index, label in ((i-1, 'Previous'), (i+1, 'Next')):
            if 0 <= index < len(PAGES):
                q = PAGES[index]
                adjacent += f'<a href="/docs/{q["slug"]}/"><small>{label}</small><strong>{esc(q["title"])}</strong></a>'
        adjacent += '</nav>'
        body = f'''<div class="docs-layout"><aside class="docs-sidebar"><div class="docs-top"><a href="/docs/">Documentation</a><button class="docs-toggle" aria-expanded="false" aria-controls="docs-nav">Browse topics</button></div><nav id="docs-nav" aria-label="Documentation">{nav}</nav></aside><main id="main" class="doc-main"><div class="doc-eyebrow">{esc(p['group'])} <span>MVP2 / foundation</span></div><h1>{esc(p['title'])}</h1><p class="doc-lead">{esc(p['description'])}</p><div class="doc-status"><strong>Development preview</strong><span>MVP2 foundation complete. Live hooks, enforcement, and Anthropic BYOK are pending. Planned behavior is labeled separately from working features.</span></div><div class="mobile-toc"><details><summary>On this page</summary>{toc}</details></div><article class="doc-article">{sections}</article><div class="doc-source">Based on the <a href="/reference/TraceRook_MVP1_Architecture_Spec.md">MVP1 specification</a>, the additive <a href="/reference/TraceRook_MVP2_Architecture_Implementation_Spec.md">MVP2 specification</a>, and the <a href="/reference/docs/MVP2_ACCEPTANCE.md">acceptance matrix</a> · October 8, 2026.</div>{adjacent}</main><aside class="docs-toc" aria-label="On this page"><p>On this page</p>{toc}<a class="toc-bottom" href="https://github.com/kleprevost/tracerook">GitHub project</a></aside></div>'''
        out = DIST / 'docs' / p['slug']
        out.mkdir(parents=True, exist_ok=True)
        (out/'index.html').write_text(shell(p['title'], p['description'], body, 'docs', path=f'/docs/{p["slug"]}/'))
    cards = ''
    for group in groups:
        cards += f'<section class="docs-collection"><h2>{esc(group)}</h2><div class="docs-card-grid">'
        for page in PAGES:
            if page['group'] == group:
                cards += f'<a class="doc-card" href="/docs/{page["slug"]}/"><h3>{esc(page["title"])}</h3><p>{esc(page["description"])}</p><span>Read guide</span></a>'
        cards += '</div></section>'
    body = f'''<main id="main" class="docs-index wrap"><div class="eyebrow">The TraceRook field guide</div><h1>Understand every<br><span class="muted">decision.</span></h1><p class="intro">From your first native demo to the MVP2 foundation and the gates for real protection. Product guides and engineering references grounded in the specifications and measured implementation.</p><div class="search-area"><label for="doc-search">Search documentation</label><div class="search-box"><input id="doc-search" type="search" placeholder="Try MVP2, privacy, or Claude…" autocomplete="off"><kbd>/</kbd></div><p id="search-status" role="status" aria-live="polite"></p><div id="search-results" hidden></div><noscript><p>Browse the guides below. Search requires JavaScript; every guide is available without it.</p></noscript></div><div id="doc-collections">{cards}</div></main>'''
    (DIST/'docs'/'index.html').write_text(shell('Documentation', 'Comprehensive TraceRook guides for the native macOS preview, Claude analysis, privacy, integrations, policy, and engineering.', body, 'docs', path='/docs/'))
    index = [{"title":p['title'],"url":f"/docs/{p['slug']}/","group":p['group'],"description":p['description'],"text":html.unescape(re.sub(r'<[^>]+>', ' ', ' '.join(s[2] for s in p['sections'])))} for p in PAGES]
    (DIST/'assets'/'search-index.json').write_text(json.dumps(index, ensure_ascii=False))

def build():
    DIST.mkdir(exist_ok=True)
    references = DIST / 'reference'
    references.mkdir(exist_ok=True)
    for source in ('TraceRook_MVP1_Architecture_Spec.md', 'TraceRook_MVP2_Architecture_Implementation_Spec.md',
                   'TraceRook_MVP2_Agent_Handoff.md', 'SECURITY_LIMITATIONS.md', 'docs/IMPLEMENTATION_STATUS.md',
                   'docs/MVP2_ACCEPTANCE.md', 'docs/MVP2_PR2_PLAN.md', 'docs/AGENT_COMPATIBILITY.md',
                   'docs/ARCHITECTURE.md', 'docs/DEVELOPMENT.md', 'docs/PRIVACY.md', 'docs/THREAT_MODEL.md',
                   'website/README.md', 'docs/LOCAL_MOCK_API_HANDOFF.md', 'docs/LOCAL_API_CLIENT_PREPARATION.md',
                   'docs/MVP2_SERVICE_EVIDENCE.md', 'docs/MVP2_RULES_EVIDENCE.md',
                   'TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Claude_Cloud_Alpha_Spec.md'):
        path = ROOT.parent / source
        destination = references / source
        destination.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            shutil.copyfile(path, destination)
        elif not destination.exists():
            raise FileNotFoundError(f'Reference document missing: {source}')
    # Keep the original public reference URL working while preserving relative
    # Markdown links in the new mirrored engineering documents.
    shutil.copyfile(references / 'docs/IMPLEMENTATION_STATUS.md', references / 'IMPLEMENTATION_STATUS.md')
    build_home()
    build_docs()
    (DIST/'404.html').write_text(shell('Page not found', 'Find your way back to TraceRook.', '<main id="main" class="not-found wrap"><div class="eyebrow">404 / Off the board</div><h1>This page moved<br>out of play.</h1><p>Find what you need in the documentation, or start at home.</p><div class="button-row"><a class="button primary" href="/">Back to TraceRook</a><a class="button" href="/docs/">Browse documentation</a></div></main>', extra='<meta name="robots" content="noindex">', path=None))
    routes = ['/', '/docs/'] + [f'/docs/{page["slug"]}/' for page in PAGES]
    (DIST/'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'  <url><loc>{SITE_URL}{route}</loc></url>\n' for route in routes) + '</urlset>\n')
    (DIST/'robots.txt').write_text(f'User-agent: *\nAllow: /\nSitemap: {SITE_URL}/sitemap.xml\n')
    print(f'Generated homepage, documentation index, {len(PAGES)} guides, and 404 page.')

if __name__ == '__main__':
    build()
