# TraceRook website

The static site and documentation for [tracerook.dev](https://tracerook.dev): homepage with the About section, pricing and invitation pages, and 18 guides. `dist/` is plain HTML, CSS, JavaScript, JSON and PNG with no framework; the only server code is the invitation Pages Function in `/functions`.

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
| Pricing, Request an invitation | `content/pricing.html`, `content/register.html` |
| Documentation guides | `content/pages.py` |
| Header, footer, page shell, sitemap | `scripts/build.py` |
| Styles and client behavior | `dist/assets/site.css`, `dist/assets/site.js` |
| Security headers, redirects, Function routes | `dist/_headers`, `dist/_redirects`, `dist/_routes.json` |
| Invitation endpoint | `../functions/api/beta/request.js` |

`scripts/check.py` validates every route, link, anchor, landmark, image, label and form, rejects external scripts, non-HTTPS links, contact addresses outside `@tracerook.dev` and retired release-status wording, and confirms the pricing page states invitation-only access and inactive billing, the About section lists both founders, and the sitemap is complete.

## Invitation requests

The Request an invitation form submits `{"name", "email", "use_case"}` as JSON with `fetch` to `POST /api/beta/request` (`use_case` may be empty). The Cloudflare Pages Function in `functions/api/beta/request.js` validates it, stores it in the `tracerook-signups` D1 database and, if Resend is configured, also emails the founders with `reply_to` set to the requester. Nothing is sent to the requester. A repeat request from the same email (any letter case) is accepted without creating a duplicate.

| Pages binding or variable | Purpose |
| --- | --- |
| `DB` | D1 binding to `tracerook-signups`. Table: `website/signups-schema.sql` |
| `RESEND_API_KEY` | Optional secret for a notification email |
| `INVITE_FROM` | Optional sender on a Resend-verified domain. Default `TraceRook <invites@tracerook.dev>` |
| `INVITE_TO` | Optional comma-separated recipients. Default `kyle@tracerook.dev,john@tracerook.dev` |

A request succeeds when it is stored or emailed. Validation errors return `{"error": {"message": "..."}}`, which the form shows. If neither storage nor email works, the form offers a prefilled email to the addresses in its `data-fallback-to`, so the requester always has a working path. `_routes.json` limits Function invocations to `/api/*`; everything else is served as static files. `/login/` redirects to the install guide.

Read requests in the Cloudflare dashboard (Storage & Databases → D1 → `tracerook-signups` → Console) or from the command line:

```sh
npx wrangler d1 execute tracerook-signups --remote \
  --command "SELECT created_at, name, email, use_case FROM beta_requests ORDER BY created_at DESC"
```

## Cloudflare Pages

Production deploys from `main` with:

- Framework preset: None
- Root directory: repository root
- Build command: `python3 website/scripts/build.py && python3 website/scripts/check.py && node --check website/dist/assets/site.js`
- Build output directory: `website/dist`
- Functions: `functions/` at the repository root. Add the `DB` binding under Settings → Bindings and any variables under Settings → Variables and Secrets

`_headers` applies the content security policy and privacy headers; `_redirects` maps retired guide URLs. Directory indexes and `404.html` handle routing. The site has no analytics, trackers, external fonts or third-party scripts.
