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

class Document(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.refs = []
        self.controls = []
        self.h1 = 0
        self.main = 0
        self.description = False
        self.title = False
        self.language = False
        self.script_sources = []
        self.inline_scripts = 0
        self.forms = 0
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
        if tag in ('a','link') and 'href' in attr: self.refs.append(attr['href'])
        if tag in ('img','script') and 'src' in attr: self.refs.append(attr['src'])
        if tag == 'img':
            assert 'alt' in attr, 'Image has no alt text'
            assert 'width' in attr and 'height' in attr, 'Image dimensions missing'
            self.images.append(attr)
        if 'aria-controls' in attr: self.controls.extend(attr['aria-controls'].split())
        if tag == 'script':
            if 'src' in attr: self.script_sources.append(attr['src'])
            else: self.inline_scripts += 1
        if tag == 'form': self.forms += 1

def resolve(path):
    target = DIST / unquote(path).lstrip('/')
    return target / 'index.html' if target.is_dir() else target

def check():
    paths = sorted(DIST.rglob('*.html'))
    expected = {DIST / 'index.html', DIST / 'docs/index.html', DIST / '404.html'}
    expected.update(DIST / 'docs' / page['slug'] / 'index.html' for page in PAGES)
    assert set(paths) == expected, 'Generated route set does not match the authored guides'
    documents = {path:Document(path.read_text()) for path in paths}
    refs = 0
    for path, document in documents.items():
        assert document.h1 == 1 and document.main == 1, f'Invalid primary landmarks: {path}'
        assert document.language and document.title and document.description, f'Metadata missing: {path}'
        assert document.forms == 0 and document.inline_scripts == 0, f'Static boundaries violated: {path}'
        assert all(url.startswith('/assets/') for url in document.script_sources), f'External script: {path}'
        for control in document.controls:
            assert control in document.ids, f'Unresolved ARIA control: {path}: {control}'
        for ref in document.refs:
            url = urlsplit(ref)
            if url.scheme or url.netloc:
                assert url.scheme == 'https', f'Unexpected external link: {ref}'
                continue
            target = resolve(url.path) if url.path else path
            assert target.is_file(), f'Broken reference in {path}: {ref}'
            if url.fragment:
                assert target in documents and unquote(url.fragment) in documents[target].ids, f'Broken anchor: {path}: {ref}'
            refs += 1
        if path.parent.parent.name == 'docs':
            assert 'MVP2 foundation complete.' in path.read_text(), f'Milestone missing: {path}'
            assert 'Live hooks, enforcement, and Anthropic BYOK are pending.' in path.read_text(), f'Status missing: {path}'
    index = json.loads((DIST/'assets/search-index.json').read_text())
    assert len(index) == len(PAGES)
    assert len({page['url'] for page in index}) == len(PAGES)
    for page in index:
        assert resolve(page['url']) in documents
        assert len(page['text']) > 1000, f'Guide lacks substantive content: {page["title"]}'
    text = ' '.join(p['text'] for p in index)
    assert len(text.split()) > 7000, 'Documentation is not extensive'
    assert not re.search(r'sk-ant-[A-Za-z0-9_-]{16,}', text), 'Unexpected credential-like value'
    script = (DIST/'assets/site.js').read_text()
    assert 'https://' not in script and 'http://' not in script, 'Unexpected remote endpoint in client script'
    assert 'localStorage' not in script and 'sessionStorage' not in script, 'Unexpected client persistence'
    manifest = json.loads((ROOT/'.openai/hosting.json').read_text())
    assert manifest['static']['directory'] == 'dist'
    assert not any(key in manifest for key in ('d1','r2','plugins','connectors')), 'Unexpected runtime capability'
    for source in ['TraceRook_MVP2_Architecture_Implementation_Spec.md', 'docs/MVP2_ACCEPTANCE.md', 'docs/MVP2_PR2_PLAN.md']:
        assert (DIST/'reference'/source).read_bytes() == (ROOT.parent/source).read_bytes(), f'Stale authoritative reference: {source}'
    roadmap = (DIST/'docs/roadmap/index.html').read_text()
    assert '43' in roadmap and 'MVP2.0' in roadmap and 'Pending' in roadmap, 'Roadmap loses current evidence or pending gates'
    print(f'PASS: {len(paths)} HTML pages, {refs} local links/assets/anchors, {len(index)} searchable guides, {len(text.split())} documentation words, static privacy boundaries.')

if __name__ == '__main__':
    check()
