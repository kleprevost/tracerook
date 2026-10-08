# TraceRook website

The static site and documentation for [tracerook.dev](https://tracerook.dev): homepage, pricing, account pages and 18 guides. `dist/` is plain HTML, CSS, JavaScript, JSON and PNG with no framework or runtime server.

```sh
python3 website/scripts/build.py
python3 website/scripts/check.py
node --check website/dist/assets/site.js
node website/scripts/preview.mjs      # http://127.0.0.1:4173/
```

Python 3.9+ builds and validates the site; Node 18+ runs the local preview. Commit the regenerated `dist/` with source changes so the repository stays directly serveable.

## Editing

| Content | Source |
| --- | --- |
| Homepage | `content/home.html` |
| Pricing, Join the beta, Log in | `content/pricing.html`, `content/register.html`, `content/login.html` |
| Documentation guides | `content/pages.py` |
| Header, footer, page shell, sitemap | `scripts/build.py` |
| Styles and client behavior | `dist/assets/site.css`, `dist/assets/site.js` |
| Security headers and redirects | `dist/_headers`, `dist/_redirects` |

`scripts/check.py` validates every route, link, anchor, landmark, image, label and form, rejects external scripts and retired release-status wording, and confirms the pricing page and sitemap.

## Account forms

The Join the beta and Log in forms submit JSON with `fetch` to same-origin endpoints:

| Form | Endpoint | Body |
| --- | --- | --- |
| Join the beta | `POST /api/auth/register` | `{"name", "email", "password"}` |
| Log in | `POST /api/auth/login` | `{"email", "password"}` |

A 2xx response may include `{"redirect": "/path"}` to navigate after success; otherwise the form shows a confirmation. Error responses may include `{"error": {"message": "..."}}`, which is shown to the user. Any other failure shows a generic retry message. Content Security Policy allows `form-action 'self'` and `connect-src 'self'`, so the endpoints must be served from the same origin (for example as Cloudflare Pages Functions or a route to the Worker).

## Cloudflare Pages

Production deploys from `main` with:

- Framework preset: None
- Root directory: repository root
- Build command: `python3 website/scripts/build.py && python3 website/scripts/check.py && node --check website/dist/assets/site.js`
- Build output directory: `website/dist`

`_headers` applies the content security policy and privacy headers; `_redirects` maps retired guide URLs. Directory indexes and `404.html` handle routing. The site has no analytics, trackers, external fonts or third-party scripts.
