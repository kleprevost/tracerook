# TraceRook static website

Static product site and 21 documentation guides, based on the authoritative MVP1/MVP2 specifications and current acceptance records. MVP2.0 is complete locally with 43 automated tests; real protection remains pending. Anthropic Claude is prominent as the intended contextual analysis backend, with live BYOK and enforcement explicitly identified as future gates.

The shipped `dist/` contains ordinary HTML, CSS, JavaScript, JSON, and PNG assets. It requires no runtime application server, framework, database, package install, API keys, or backend. All reading and navigation work without JavaScript; documentation search, menu toggles, copying code, and fixed policy examples use a small same-origin client script.

From the repository root:

```sh
python3 website/scripts/build.py
python3 website/scripts/check.py
node --check website/dist/assets/site.js
node website/scripts/preview.mjs
```

Open `http://127.0.0.1:4173/`. Python 3.9+ is sufficient for generation and validation; Node 18+ runs the local preview. The generated static output is tracked so it can also be served directly without generation.

Edit homepage content in `content/home.html` and guides in `content/pages.py`, then regenerate. Shared templates and metadata live in `scripts/build.py`. Styling and client interactions are under `dist/assets/`. Screenshots are actual native app renders of explicitly labeled bundled Demo fixtures, not live protection evidence.

## Cloudflare Pages

The production site uses Cloudflare Pages on the free tier at `https://tracerook.dev`, connected to `kleprevost/tracerook`. Production deployments follow `main` using these settings:

- Framework preset: None
- Root directory: repository root (blank)
- Build command: `python3 website/scripts/build.py && python3 website/scripts/check.py && node --check website/dist/assets/site.js`
- Build output directory: `website/dist`
- Environment variables, Functions, Workers, paid bindings, and analytics: none required

Commit regenerated output with source changes so the repository remains directly serveable. Pages also regenerates and validates each deployment. `_headers` applies the static site's content policy and privacy restrictions; directory indexes and `404.html` handle routing without a SPA rewrite. Canonical URLs, `robots.txt`, and the sitemap use `https://tracerook.dev`.

The earlier private Sites preview is identified by `.openai/hosting.json`. That file is preview metadata and does not configure Cloudflare. Credentials never belong in files or shell arguments.

No tracking scripts, external fonts, analytics, forms, or provider requests are included. Documentation search fetches only the bundled index from the same origin. The website does not access local sessions or accept API keys. The hosting provider may retain ordinary access logs and enforce authentication for private previews.

For another static host, serve `dist/` at the origin root with directory `index.html` resolution and a 404 handler using `404.html`. No SPA rewrite or API route is needed. The owner authorized this public site and custom domain.

## Validation record — 2026-10-08

Static checks pass for 24 HTML pages, 1,300 local links/assets/anchors, unique landmarks and IDs, metadata, ARIA control targets, 21 search records, and over 8,600 words of guide content. Client JavaScript passes Node syntax validation. The validator also checks the current MVP2 status on each guide and compares packaged specification, acceptance, and implementation-plan copies with their sources.

The initial site checks exercised all alternate policy examples, documentation search and ranking, empty results, Escape reset, mobile navigation open/close, and code copying. The MVP2 update additionally checks the new guide, search results, roadmap, homepage and navigation at desktop width and 390px, with no document-level horizontal overflow or console errors. This is not a full accessibility certification or an enforcement test for the native application.

The guides link to packaged, unchanged copies of both authoritative specifications, the handoff, implementation record, acceptance matrix, PR2 plan, and security limitations. Engineering documents mirror the repository's relative layout; the original implementation-status URL remains available. These references are served as static files and need no API or database.
