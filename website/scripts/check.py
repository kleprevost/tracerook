#!/usr/bin/env python3
"""Check all shipped routes, anchors, assets, metadata, and static-site boundaries."""
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / 'dist'
sys.path.insert(0, str(ROOT / 'content'))
from pages import PAGES

FORM_PAGES = {'register': '/api/beta/request', 'login': '/api/auth/login'}
FOUNDERS = ('Kyle LePrevost', 'mailto:kyle@tracerook.dev', 'https://hardcidr.com', 'John Yang', 'mailto:john@tracerook.dev', 'https://www.linkedin.com/in/johnwyang/')
# Retired release-status language must not reappear in shipped copy.
RETIRED_PHRASES = ('Now open', 'Join the beta', 'MVP', 'development preview', 'Development preview', 'release gate', 'acceptance gate',
                   'remains unverified', 'remains pending', 'not notarized', 'Phase 0', 'Phase 1')


class Document(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.refs = []
        self.controls = []
        self.labels = set()
        self.inputs = []
        self.h1 = 0
        self.main = 0
        self.description = False
        self.title = False
        self.language = False
        self.script_sources = []
        self.inline_scripts = 0
        self.forms = []
        self.images = []
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        attr = dict(attrs)
        if 'id' in attr:
            assert attr['id'] not in self.ids, f'Duplicate id: {attr["id"]}'
            self.ids.add(attr['id'])
        if tag == 'html': self.language = attr.get('lang') == 'en'
        if tag == 'h1': self.h1 += 1
        if tag == 'main': self.main += 1
        if tag == 'title': self.title = True
        if tag == 'meta' and attr.get('name') == 'description':
            self.description = bool(attr.get('content'))
        if tag in ('a', 'link') and 'href' in attr: self.refs.append(attr['href'])
        if tag in ('img', 'script') and 'src' in attr: self.refs.append(attr['src'])
        if tag == 'img':
            assert 'alt' in attr, 'Image has no alt text'
            assert 'width' in attr and 'height' in attr, 'Image dimensions missing'
            self.images.append(attr)
        if 'aria-controls' in attr: self.controls.extend(attr['aria-controls'].split())
        if tag == 'script':
            if 'src' in attr: self.script_sources.append(attr['src'])
            else: self.inline_scripts += 1
        if tag == 'form': self.forms.append(attr)
        if tag == 'label' and 'for' in attr: self.labels.add(attr['for'])
        if tag == 'input': self.inputs.append(attr)


def resolve(path):
    target = DIST / unquote(path).lstrip('/')
    return target / 'index.html' if target.is_dir() else target


def check():
    paths = sorted(DIST.rglob('*.html'))
    expected = {DIST / 'index.html', DIST / 'docs/index.html', DIST / '404.html'}
    expected.update(DIST / name / 'index.html' for name in ('pricing', 'register', 'login'))
    expected.update(DIST / 'docs' / page['slug'] / 'index.html' for page in PAGES)
    assert set(paths) == expected, f'Generated route set does not match: {sorted(map(str, set(paths) ^ expected))}'
    documents = {path: Document(path.read_text()) for path in paths}
    refs = 0
    for path, document in documents.items():
        text = path.read_text()
        assert document.h1 == 1 and document.main == 1, f'Invalid primary landmarks: {path}'
        assert document.language and document.title and document.description, f'Metadata missing: {path}'
        assert document.inline_scripts == 0, f'Inline script: {path}'
        assert all(url.startswith('/assets/') for url in document.script_sources), f'External script: {path}'
        for phrase in RETIRED_PHRASES:
            assert phrase not in text, f'Retired status language "{phrase}" in {path}'
        route = path.parent.name if path.parent != DIST else ''
        if route in FORM_PAGES and path.parent.parent == DIST:
            assert len(document.forms) == 1 and document.forms[0].get('action') == FORM_PAGES[route], f'Unexpected form: {path}'
            assert document.forms[0].get('method') == 'post', f'Form must POST: {path}'
            assert "form-action 'self'" in text, f'Form CSP missing: {path}'
            for field in document.inputs:
                assert field.get('id') in document.labels, f'Unlabeled input in {path}: {field.get("name")}'
                assert 'autocomplete' in field, f'Input without autocomplete in {path}: {field.get("name")}'
        else:
            assert not document.forms and "form-action 'none'" in text, f'Form outside account pages: {path}'
        for control in document.controls:
            assert control in document.ids, f'Unresolved ARIA control: {path}: {control}'
        for ref in document.refs:
            url = urlsplit(ref)
            if url.scheme == 'mailto':
                assert ref.endswith('@tracerook.dev'), f'Contact address outside the domain: {ref}'
                continue
            if url.scheme or url.netloc:
                assert url.scheme == 'https', f'Unexpected external link: {ref}'
                continue
            target = resolve(url.path) if url.path else path
            assert target.is_file(), f'Broken reference in {path}: {ref}'
            if url.fragment:
                assert target in documents and unquote(url.fragment) in documents[target].ids, f'Broken anchor: {path}: {ref}'
            refs += 1
    index = json.loads((DIST/'assets/search-index.json').read_text())
    assert len(index) == len(PAGES)
    assert len({page['url'] for page in index}) == len(PAGES)
    for page in index:
        assert resolve(page['url']) in documents
        assert len(page['text']) > 600, f'Guide lacks substantive content: {page["title"]}'
    text = ' '.join(p['text'] for p in index)
    assert len(text.split()) > 4000, 'Documentation is not extensive'
    assert not re.search(r'sk-ant-[A-Za-z0-9_-]{16,}', text), 'Unexpected credential-like value'
    script = (DIST/'assets/site.js').read_text()
    assert 'https://' not in script and 'http://' not in script, 'Unexpected remote endpoint in client script'
    assert 'localStorage' not in script and 'sessionStorage' not in script, 'Unexpected client persistence'
    headers = (DIST/'_headers').read_text()
    assert "form-action 'self'" in headers and "frame-ancestors 'none'" in headers, 'Header policy changed'
    sitemap = (DIST/'sitemap.xml').read_text()
    for route in ('/pricing/', '/register/', '/login/'):
        assert route in sitemap, f'Sitemap missing {route}'
    pricing = (DIST/'pricing/index.html').read_text()
    assert '$20' in pricing and '/register/' in pricing, 'Pricing page lost its plan or call to action'
    assert 'Invitation only' in pricing and "Billing isn't active" in pricing, 'Pricing must state invitation-only access and inactive billing'
    home = (DIST/'index.html').read_text()
    assert 'id="about"' in home and all(item in home for item in FOUNDERS), 'Homepage About section is missing founder identity or contact'
    print(f'PASS: {len(paths)} HTML pages, {refs} local links/assets/anchors, {len(index)} searchable guides, {len(text.split())} documentation words, static and form boundaries.')


if __name__ == '__main__':
    check()
