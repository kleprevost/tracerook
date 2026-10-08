# TraceRook static website

MVP1 product site and 20 documentation guides, based on the authoritative architecture specification v1.0 and the current implementation acceptance record. Anthropic Claude is prominent as the intended contextual analysis backend. Pending live BYOK and enforcement are explicitly identified.

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

Static checks pass for 23 HTML pages, 1,172 local links/assets/anchors, unique landmarks and IDs, metadata, ARIA control targets, 20 search records, and approximately 7,800 words of guide content. Client JavaScript passes Node syntax validation. HTTP checks return 200 for a guide and 404 for a missing route.

Browser checks exercised all alternate policy examples, documentation search and ranking, empty results, Escape reset, mobile navigation open/close, and code copying. Home and guide layouts were inspected at the default desktop width and at 390px; the protocol reference was checked at 320px without document-level horizontal overflow. No console errors were observed. This is not a full accessibility certification or an enforcement test for the native application.

The guides link to packaged, unchanged copies of the authoritative spec, implementation record, and security limitations. These references do not depend on native source files having been pushed to GitHub.
