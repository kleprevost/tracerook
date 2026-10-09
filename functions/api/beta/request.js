// Cloudflare Pages Function for POST /api/beta/request.
// Stores each invitation request in D1 and, when Resend is configured, emails the founders.
// If neither works, the site falls back to a prefilled email.
//
// Pages bindings and environment (all optional; any one makes requests succeed):
//   DB              D1 binding to tracerook-signups (table beta_requests, see website/README.md)
//   RESEND_API_KEY  secret for a notification email
//   INVITE_FROM     sender on a Resend-verified domain (default below)
//   INVITE_TO       comma-separated recipients (default below)

const DEFAULT_FROM = "TraceRook <invites@tracerook.dev>";
const DEFAULT_TO = "kyle@tracerook.dev,john@tracerook.dev";
const MAX_BODY = 4096;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function reply(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {"Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"}
  });
}

const fail = (status, message) => reply(status, {error: {message}});

function field(value, max) {
  return typeof value === "string" ? value.replace(/[\u0000-\u001f\u007f]+/g, " ").trim().slice(0, max) : "";
}

export async function onRequestPost({request, env}) {
  const origin = request.headers.get("Origin");
  if (origin && origin !== new URL(request.url).origin) return fail(403, "Requests must come from tracerook.dev.");
  if (!(request.headers.get("Content-Type") || "").startsWith("application/json")) return fail(415, "Send the request as JSON.");

  const raw = await request.text();
  if (raw.length > MAX_BODY) return fail(413, "That request is too long.");
  let input;
  try { input = JSON.parse(raw); } catch { return fail(400, "That request couldn't be read."); }
  if (!input || typeof input !== "object") return fail(400, "That request couldn't be read.");

  const name = field(input.name, 120);
  const email = field(input.email, 254);
  const useCase = field(input.use_case, 280);
  if (!name) return fail(400, "Enter your name.");
  if (!EMAIL.test(email)) return fail(400, "Enter a valid email address.");

  const stored = env.DB ? await env.DB
    .prepare("INSERT INTO beta_requests (name, email, use_case) VALUES (?1, ?2, ?3) ON CONFLICT (email) DO NOTHING")
    .bind(name, email, useCase).run().then(() => true, () => false) : false;
  const emailed = env.RESEND_API_KEY ? await notify(env, name, email, useCase) : false;
  // An empty message tells the site to offer the prefilled email instead.
  if (!stored && !emailed) return fail(env.DB || env.RESEND_API_KEY ? 502 : 503, "");
  return reply(200, {ok: true});
}

async function notify(env, name, email, useCase) {
  const to = (env.INVITE_TO || DEFAULT_TO).split(",").map(address => address.trim()).filter(Boolean);
  const sent = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {"Authorization": `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json"},
    body: JSON.stringify({
      from: env.INVITE_FROM || DEFAULT_FROM,
      to,
      reply_to: email,
      subject: `Beta invitation request: ${name}`,
      text: `Name: ${name}\nEmail: ${email}\nHow they use coding agents: ${useCase || "(not provided)"}\n\nReply to this email to respond directly.`
    })
  }).catch(() => null);
  return Boolean(sent && sent.ok);
}
