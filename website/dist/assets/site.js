"use strict";
document.querySelectorAll(".menu-toggle,.docs-toggle").forEach(button => {
  const panel = document.getElementById(button.getAttribute("aria-controls"));
  button.addEventListener("click", () => {
    const expanded = button.getAttribute("aria-expanded") === "true";
    button.setAttribute("aria-expanded", String(!expanded));
    panel.classList.toggle("is-open", !expanded);
  });
  panel.querySelectorAll("a").forEach(link => link.addEventListener("click", () => {
    panel.classList.remove("is-open");
    button.setAttribute("aria-expanded", "false");
  }));
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && button.getAttribute("aria-expanded") === "true") {
      panel.classList.remove("is-open");
      button.setAttribute("aria-expanded", "false");
      button.focus();
    }
  });
});

const examples = {
  credentials: {
    verdict: "Block before execution", title: "A credential file is headed outside the project.",
    description: "A sensitive credential path and outbound upload in the same command are concrete local evidence. TraceRook denies the call before it runs, and Claude cannot downgrade the decision.",
    source: "Local deterministic rule", rule: "TR-CRED-EXFIL", review: "No quick allow for critical denials", severity: "critical"
  },
  remote: {
    verdict: "Pause for human review", title: "An external script is about to run.",
    description: "Fetching and executing remote code can change the project beyond the task. The call waits for your one-time review; if the 45 seconds run out, it is denied.",
    source: "Local high-risk evidence", rule: "TR-REMOTE-EXEC", review: "Allow once or Block · 45-second window", severity: "high"
  },
  drift: {
    verdict: "Review the mismatch", title: "A UI task turned into a production deployment.",
    description: "The action no longer matches your task. Local publishing evidence flags it, and Claude confirms the session has drifted, so TraceRook asks you before anything ships.",
    source: "Local evidence + Claude analysis", rule: "TR-PUBLISH-DEPLOY · session drift", review: "Decide on the exact action", severity: "high"
  },
  cleanup: {
    verdict: "Allow with no TraceRook override", title: "Ordinary cleanup stays ordinary.",
    description: "The action is scoped to disposable build output and fits the task. A destructive-looking command alone isn't evidence for a block, so your agent keeps working.",
    source: "Local scope and task evidence", rule: "Scoped cleanup", review: "No review needed", severity: "low"
  }
};
document.querySelectorAll("[data-scenario]").forEach(button => {
  button.addEventListener("click", () => {
    const example = examples[button.dataset.scenario];
    document.querySelectorAll("[data-scenario]").forEach(other => other.setAttribute("aria-pressed", String(other === button)));
    ["verdict", "title", "description", "source", "rule", "review"].forEach(key => {
      document.getElementById("scenario-" + key).textContent = example[key];
    });
    document.getElementById("scenario-verdict").dataset.severity = example.severity;
  });
});

document.querySelectorAll(".copy-code").forEach(button => {
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(button.parentElement.querySelector("code").textContent);
      button.textContent = "Copied";
    } catch {
      button.textContent = "Select text to copy";
    }
    setTimeout(() => { button.textContent = "Copy"; }, 2500);
  });
});

const search = document.getElementById("doc-search");
if (search) {
  const results = document.getElementById("search-results");
  const status = document.getElementById("search-status");
  const collections = document.getElementById("doc-collections");
  let indexPromise;
  let sequence = 0;
  async function updateSearch() {
    const current = ++sequence;
    const query = search.value.trim().toLowerCase().slice(0, 200);
    results.replaceChildren();
    results.hidden = !query;
    collections.hidden = Boolean(query);
    if (!query) { status.textContent = ""; return; }
    status.textContent = "Searching documentation…";
    try {
      indexPromise ||= fetch("/assets/search-index.json", {credentials:"same-origin"}).then(response => {
        if (!response.ok) throw new Error("Index unavailable");
        return response.json();
      }).catch(error => { indexPromise = undefined; throw error; });
      const index = await indexPromise;
      if (current !== sequence) return;
      const terms = query.split(/\s+/).filter(Boolean);
      const matches = index.map(page => {
        const title = page.title.toLowerCase();
        const description = page.description.toLowerCase();
        const all = (title + " " + description + " " + page.text).toLowerCase();
        if (!terms.every(term => all.includes(term))) return null;
        const score = terms.reduce((n, term) => n + (title.includes(term) ? 20 : description.includes(term) ? 8 : 0) + Math.min(6, all.split(term).length - 1), 0);
        return {page, score};
      }).filter(Boolean).sort((a,b) => b.score-a.score);
      status.textContent = matches.length ? `${matches.length} ${matches.length === 1 ? "guide" : "guides"} found${matches.length > 12 ? "; showing the first 12" : ""}.` : "No matching guides. Try a broader term, or clear search to browse all topics.";
      matches.slice(0,12).forEach(({page}) => {
        const link = document.createElement("a");
        link.className = "search-result";
        link.href = page.url;
        const group = document.createElement("span"); group.textContent = page.group;
        const title = document.createElement("h3"); title.textContent = page.title;
        const summary = document.createElement("p"); summary.textContent = page.description;
        link.append(group, title, summary); results.append(link);
      });
    } catch {
      if (current !== sequence) return;
      status.textContent = "Search is unavailable. Browse all guides below.";
      results.hidden = true; collections.hidden = false;
    }
  }
  search.addEventListener("input", updateSearch);
  document.addEventListener("keydown", event => {
    const editing = /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName) || document.activeElement.isContentEditable;
    if (event.key === "/" && !editing && !event.ctrlKey && !event.metaKey && !event.altKey) {event.preventDefault();search.focus();}
    if (event.key === "Escape" && document.activeElement === search) {search.value="";updateSearch();}
  });
}

document.querySelectorAll("[data-auth-form]").forEach(form => {
  const status = form.querySelector(".form-status");
  const submit = form.querySelector("button[type=submit]");
  const messages = {
    request: "Thanks. Your request is in, and we'll email you when an invitation is ready.",
    login: "Logged in."
  };
  form.addEventListener("submit", async event => {
    event.preventDefault();
    status.textContent = "";
    status.dataset.state = "";
    if (!form.checkValidity()) {
      const invalid = form.querySelector(":invalid");
      status.textContent = invalid.validationMessage;
      status.dataset.state = "error";
      invalid.focus();
      return;
    }
    const body = {};
    new FormData(form).forEach((value, key) => { body[key] = String(value); });
    submit.disabled = true;
    status.textContent = form.dataset.authForm === "request" ? "Sending your request…" : "Logging in…";
    try {
      const response = await fetch(form.getAttribute("action"), {
        method: "POST", credentials: "same-origin",
        headers: {"Content-Type": "application/json", "Accept": "application/json"},
        body: JSON.stringify(body)
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(result && result.error && typeof result.error.message === "string" ? result.error.message : "");
      if (typeof result.redirect === "string" && result.redirect.startsWith("/") && !result.redirect.startsWith("//")) {
        window.location.assign(result.redirect);
        return;
      }
      form.reset();
      status.textContent = messages[form.dataset.authForm];
      status.dataset.state = "success";
    } catch (error) {
      status.textContent = error.message || "We couldn't reach TraceRook right now. Please try again in a moment.";
      status.dataset.state = "error";
    } finally {
      submit.disabled = false;
    }
  });
});
