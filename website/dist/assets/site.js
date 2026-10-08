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
    description: "A sensitive credential path and outbound upload in the same effective command supply concrete local evidence. Claude cannot downgrade this critical denial.",
    source: "Local deterministic rule", rule: "TR-CRED-EXFIL", review: "No quick allow for critical denials", severity: "critical"
  },
  remote: {
    verdict: "Pause for human review", title: "An external script is about to run.",
    description: "Fetching and executing remote code can change the project beyond the task. The proposed action should wait for a bound, one-time review; expiry denies the high-risk request.",
    source: "Local high-risk evidence", rule: "TR-REMOTE-EXEC", review: "Allow once or block · 45-second window", severity: "high"
  },
  drift: {
    verdict: "Review the mismatch", title: "A UI task turned into a production deployment.",
    description: "The action no longer matches the user's task anchor. In the planned live flow, local publishing evidence and Claude's contextual assessment can recommend review. A model verdict alone cannot create a critical denial.",
    source: "Local evidence + Claude context (planned)", rule: "TR-PUBLISH-DEPLOY / TR-TASK-DRIFT", review: "Require a decision on the exact action", severity: "high"
  },
  cleanup: {
    verdict: "Allow with no TraceRook override", title: "Ordinary cleanup stays ordinary.",
    description: "The action is scoped to disposable build output and fits the task. A destructive-looking command token alone is insufficient evidence for a critical block. Native agent permissions still apply.",
    source: "Local scope and task evidence", rule: "Benign near-miss / scoped cleanup", review: "No extra review in this example", severity: "low"
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
