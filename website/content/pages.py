"""TraceRook documentation guides.

Sections contain authored HTML. No user input or remote source is rendered here.
"""
from html import escape

PAGES = []

RELEASE_URL = 'https://github.com/kleprevost/tracerook/releases/tag/v0.1.0-beta.1'


WALKTHROUGH = '<section class="walkthrough" id="walkthrough" aria-labelledby="walkthrough-title"><div class="section-heading"><div><span class="eyebrow">A minute inside TraceRook</span><h2 id="walkthrough-title">See the native app in action.</h2></div><p>A 60-second tour of sessions, findings, and a timed Block review.</p></div><figure class="walkthrough-player"><video controls playsinline preload="none" width="1920" height="1080" poster="/assets/tracerook-walkthrough-poster.jpg" aria-label="TraceRook native app walkthrough with demo data" aria-describedby="walkthrough-caption"><source src="/assets/tracerook-walkthrough.mp4" type="video/mp4"><track kind="captions" src="/assets/tracerook-walkthrough.vtt" srclang="en" label="English" default><p><a href="/assets/tracerook-walkthrough.mp4">Download the walkthrough video</a>.</p></video><figcaption id="walkthrough-caption">Recorded in the native app using labeled demo scenarios. No real commands execute in this walkthrough; the Codex scenes are simulations.</figcaption></figure><div class="walkthrough-links"><a class="text-link" href="/assets/tracerook-walkthrough.mp4" download>Download video</a><a class="text-link" href="/assets/tracerook-walkthrough-transcript.txt">Read transcript</a></div></section>'

def page(slug, title, group, description, *sections):
    PAGES.append(dict(slug=slug, title=title, group=group, description=description, sections=sections))


def table(headers, rows):
    return '<div class="table-wrap"><table><thead><tr>' + ''.join('<th scope="col">'+escape(h)+'</th>' for h in headers) + '</tr></thead><tbody>' + ''.join('<tr>'+''.join('<td>'+escape(c)+'</td>' for c in row)+'</tr>' for row in rows) + '</tbody></table></div>'


def code(text):
    return '<div class="code-wrap"><pre><code>'+escape(text)+'</code></pre><button class="copy-code" type="button" aria-label="Copy code example">Copy</button></div>'


HOOK_CONFIG = '''{
  "hooks": {
    "PreToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "\\"/Applications/TraceRook.app/Contents/MacOS/tracerook-hook\\" --adapter claude_code --host-version 2.1.290 --timeout-ms 80000",
        "timeout": 85
      }]
    }]
  }
}'''

# ---------------------------------------------------------------------------------------- Start here

page('introduction', 'Meet TraceRook', 'Start here', 'A second look at every action your coding agent proposes, before it runs.',
('purpose', 'A second look before execution', '''<p>Coding agents edit files, run commands, contact services and read instructions from sources you didn't write. TraceRook sits between the agent and your Mac. Every tool call the agent proposes is checked against your task and TraceRook's policy before it executes, and the risky ones are stopped or handed to you.</p><p>TraceRook is a native macOS app with a per-user background service. It plugs into Claude Code through its <code>PreToolUse</code> hook, so it sees each proposed action at the one moment it can still be prevented.</p>'''),
('pipeline', 'Three layers of judgment', '''<ul><li><strong>Local rules</strong> run on your Mac in milliseconds and catch concrete dangerous signatures: credential exfiltration, destructive commands outside the project, remote code execution, privilege escalation and attempts to disable TraceRook itself.</li><li><strong>TraceRook Cloud</strong> asks Anthropic Claude whether an ambiguous action still fits the task you gave the agent, and whether an untrusted instruction has redirected it.</li><li><strong>You</strong> make the call on high-risk actions in a native review window, with the evidence in front of you.</li></ul>'''),
('model', 'How TraceRook responds', table(['Risk', 'Response', 'Who decides'], [
    ('Critical', 'Blocked before execution', 'Enabled critical rule with concrete local evidence'),
    ('High', 'Paused for your review; expiry denies', 'Local evidence or Claude recommendation'),
    ('Medium', 'Allowed with a warning and a recorded finding', 'Local evidence or Claude recommendation'),
    ('Low', 'Allowed and recorded', 'No TraceRook override'),
])),
('scope', 'Where it works', '''<p>TraceRook supports local Claude Code sessions, in the terminal and in IDEs, wherever Claude Code runs its hooks. Codex support is coming soon. TraceRook reviews the tool calls that pass through the agent's hook; commands you type yourself are yours to run.</p>'''),
('requirements', 'Requirements', '''<ul><li>Apple Silicon Mac running macOS 26 or later.</li><li>Claude Code 2.1.290.</li><li>A TraceRook beta account for Cloud analysis. <a href="/pricing/">Beta access is $20/month.</a></li></ul><p>Ready? <a href="/docs/beta/">Install the beta</a>.</p>'''),
)

page('beta', 'Install the beta', 'Start here', 'Download TraceRook, connect TraceRook Cloud and protect your first Claude Code session.',
('download', '1. Download and verify', f'''<p>Download the ZIP, its manifest and <code>SHA256SUMS</code> from <a href="{RELEASE_URL}">GitHub Releases</a>. In the folder containing all three, verify the download:</p>{code('shasum -a 256 -c TraceRook-0.1.0-beta.1-macOS-arm64-SHA256SUMS')}<p>Both entries report <code>OK</code>. Expand the ZIP and move <code>TraceRook.app</code> to your Applications folder.</p>'''),
('open', '2. Open the app', '''<p>Beta builds are distributed outside the Mac App Store, so macOS asks you to confirm the first launch. Open TraceRook once, then go to <strong>System Settings → Privacy &amp; Security</strong> and choose <strong>Open Anyway</strong> next to TraceRook. Apple explains the workflow in <a href="https://support.apple.com/en-us/102445">Safely open apps on your Mac</a>.</p>'''),
('service', '3. Start the background service', '''<p>Open <strong>Integrations → Enable Background Service</strong>. TraceRook shows the LaunchAgent it will install and the executable it will run; confirm to install <code>~/Library/LaunchAgents/com.tracerook.agent.local.plist</code> and start the service. Integrations shows the service as connected once it is running. If macOS asks for background-item approval, allow TraceRook in <strong>System Settings → General → Login Items</strong>.</p>'''),
('cloud', '4. Connect TraceRook Cloud', '''<p>Open <strong>Settings → AI Provider → TraceRook Cloud</strong>, enter the access code that came with your beta invitation, review the privacy consent and select <strong>Connect to TraceRook Cloud</strong>. You don't need an Anthropic API key; analysis runs on TraceRook's account.</p><p>The service keeps its device credential in memory, so you enter the access code again after the service restarts. Keep access codes out of agent configuration, shell history and screenshots.</p>'''),
('hook', '5. Add the Claude Code hook', f'''<p>Add a synchronous <code>PreToolUse</code> command hook to your Claude Code settings, alongside your existing settings and hooks:</p>{code(HOOK_CONFIG)}<p>Adjust the path if you installed the app somewhere else. The 85-second hook timeout leaves room for a full 45-second review. See the <a href="https://code.claude.com/docs/en/hooks">Claude Code hooks reference</a> for settings scopes and reload behavior.</p>'''),
('verify', '6. Run your first session', '''<p>Start a new Claude Code session and give it a task. Each tool call appears in <strong>Sessions</strong> with its decision. To see a review, ask the agent to fetch and run a remote script: TraceRook pauses the call, shows it in the menu bar and the Approvals queue, and waits for <strong>Allow once</strong> or <strong>Block</strong>.</p>'''),
)

page('cloud', 'TraceRook Cloud', 'Start here', 'Your account, access codes and devices for Claude-powered analysis.',
('what', 'What TraceRook Cloud does', '''<p>TraceRook Cloud is the hosted service at <code>api.tracerook.dev</code> that runs contextual analysis with Anthropic Claude Haiku 5.5. When local rules can't settle an action on their own, the background service sends TraceRook Cloud a privacy-preserving projection of it, and Claude returns a structured verdict: severity, categories, a short rationale, evidence and a recommendation.</p><p>TraceRook Cloud is included with <a href="/pricing/">beta access</a>. You never handle an Anthropic key.</p>'''),
('access', 'Access codes and devices', '''<p>Each beta account comes with an access code. Entering it in <strong>Settings → AI Provider → TraceRook Cloud</strong> enrolls that Mac and issues it a device credential, which the service holds in memory. An account can have up to three Macs.</p><ul><li><strong>Rotate device credential</strong> issues a fresh credential and invalidates the old one immediately.</li><li><strong>Disconnect</strong> revokes this Mac's credential.</li><li><strong>Delete cloud account data</strong> removes your account metadata and revokes every enrolled device.</li></ul>'''),
('controls', 'Pause and resume', '''<p>Cloud analysis has its own pause and resume controls in Settings. Choosing Demo or Local pauses Cloud in the service before the view changes. While Cloud is paused, local rules keep making every critical and high-risk decision on your Mac.</p>'''),
('usage', 'Usage', '''<p><strong>Refresh connection and usage</strong> shows today's analyses and token counts for your account. TraceRook Cloud applies per-device rate limits (120 requests per minute, two concurrent analyses) to keep the service fast for everyone.</p>'''),
('reliability', 'Reliability', '''<p>Every request carries a deadline shorter than the hook's, so a slow response never holds your agent hostage. Retries of the same request reuse a cached verdict for up to 10 minutes instead of calling Claude twice. If TraceRook Cloud is unreachable, the decision falls back to local policy and Settings shows the provider as unavailable.</p>'''),
)

page('dashboard', 'The dashboard', 'Start here', 'Sessions, incidents, reviews and integration health in one native window.',
('overview', 'Overview and menu bar', '''<p>Overview summarizes recent findings, pending reviews, integration status and the analysis provider. The menu bar companion is the quick way into the dashboard and the review queue, and its status follows the background service and your integrations.</p>'''),
('sessions', 'Sessions and timelines', '''<p>A session ties activity to the agent, its session ID and, when present, a subagent. Its task anchor is a short redacted summary of what you asked for. The timeline connects each proposed action to its local evidence, any Claude analysis, the decision and what happened next.</p>'''),
('incidents', 'Incidents', '''<p>Each incident answers four questions: what was attempted, what evidence raised concern, how the action related to the task, and what TraceRook did. Rule IDs and Claude's rationale explain the decision; the risk score routes it.</p>'''),
('approvals', 'Approvals and the review window', '''<p>The review window shows one pending action: the agent and project, a redacted preview of the exact action, the evidence, task relevance and a countdown. <strong>Allow once</strong> and <strong>Block</strong> apply to that exact call. Read <a href="/docs/approvals/">One-time approvals</a> for the full rules.</p><figure class="review-figure"><img src="/assets/app-review.png" alt="TraceRook review window with evidence, exact action binding, a 45-second deadline and Block and Allow once buttons" width="1360" height="1560" loading="lazy"><figcaption>The native review window · demo mode</figcaption></figure>'''),
('settings', 'Integrations and settings', '''<p>Integrations manages the background service and shows each agent's status. Settings covers the analysis provider and TraceRook Cloud, appearance, the privacy preview (<strong>What leaves my Mac?</strong>) and local history. <strong>Explore Demo</strong> loads sample sessions so you can try every view without a live agent.</p>'''),
)

# ----------------------------------------------------------------------------------- Protection

page('how-it-works', 'The decision pipeline', 'Protection', 'Follow a proposed tool call from the hook to a decision.',
('intercept', '1. The hook presents the proposal', '''<p>Claude Code runs TraceRook's <code>PreToolUse</code> hook before every tool call. The <code>tracerook-hook</code> bridge reads the JSON with strict bounds and forwards a deadline-bound request to the background service over a private socket. This is the moment an action can still be prevented.</p>'''),
('inspect', '2. Local policy inspects the original action', '''<p>The policy engine examines the exact action in memory: command structure, pipelines, sensitive paths, network destinations, mutation scope and task-related features. Concrete catastrophic evidence produces an immediate denial. Routine work, like cleaning a build directory, stays routine.</p>'''),
('analyze', '3. Claude adds context', '''<p>When the local evidence is ambiguous, the service sends TraceRook Cloud a projection of the action (task category, action category and local signal codes) and Claude Haiku 5.5 returns a strictly validated verdict. Claude can recommend a warning or a human review; it can never lower a critical local decision.</p>'''),
('review', '4. Review binds to the pending call', '''<p>A high-risk decision creates a pending review bound to the exact action fingerprint and a per-invocation nonce, with a 45-second deadline. The app shows it in the review window, the menu bar and the Approvals queue. Allow once releases that call; Block or expiry denies it.</p>'''),
('return', '5. The decision goes back to the agent', '''<p>A denial is returned as <code>permissionDecision: "deny"</code> with a short reason the agent can read. No override returns empty output, handing the call back to Claude Code's own permission flow. The session timeline records what was intercepted, blocked, allowed and observed.</p>'''),
)

page('rules', 'Local policy & rule families', 'Protection', 'Deterministic rules, severity routing and how they combine with Claude.',
('rules', 'Rule families', table(['Rule', 'What it catches', 'Response'], [
    ('TR-CRED-EXFIL', 'A credential source feeding an outbound transfer', 'Critical denial'),
    ('TR-DESTRUCT-OUTSIDE', 'Recursive deletion of user or system data outside the project', 'Critical denial; review for other paths outside the project'),
    ('TR-POLICY-TAMPER', 'Removing or disabling TraceRook or its hooks', 'Critical denial'),
    ('TR-REMOTE-EXEC', 'Remote content piped into an interpreter', 'High review'),
    ('TR-UNKNOWN-EGRESS', 'Uploads, remote copies and object-storage transfers', 'High review'),
    ('TR-SENSITIVE-READ', 'SSH, cloud, Keychain and token locations', 'High review'),
    ('TR-DOTENV-ACCESS', 'Private environment files', 'High review'),
    ('TR-PRIV-ESC', 'sudo, doas and privilege elevation', 'High review'),
    ('TR-SECURITY-CONFIG', 'Security configuration, ownership or permission changes', 'High review'),
    ('TR-PUBLISH-DEPLOY', 'Publishing, releasing or deploying', 'High review'),
    ('TR-ENCODED-COMMAND', 'Encoded content inside an execution pipeline', 'High review'),
    ('TR-REPEAT-DENIED', 'Another denied action proposed in the same session', 'High review'),
    ('TR-INSPECTION-INCOMPLETE', 'Dynamic syntax or nesting beyond inspection depth', 'High review'),
])),
('routing', 'Scores route decisions', table(['Score', 'Severity', 'Response'], [
    ('0–39', 'Low', 'Allow and record'),
    ('40–69', 'Medium', 'Allow and notify'),
    ('70–89', 'High', 'Human review'),
    ('90–100', 'Critical', 'Denial backed by concrete deterministic evidence'),
]) + '<p>Automatic critical blocking comes from an enabled catastrophic rule, never from a numeric score alone. Scores rank how urgently something deserves attention.</p>'),
('precedence', 'Evidence has precedence', '''<ol><li>A catastrophic deterministic match denies immediately.</li><li>Deterministic high-risk evidence requests review.</li><li>A Claude recommendation can request review or add a warning.</li><li>Medium risk warns while allowing; low risk records with no override.</li></ol><p>Claude can raise the level of scrutiny but never lowers a deterministic critical denial, and Allow once is never offered for one.</p>'''),
('interpretation', 'Commands are read as a shell reads them', '''<p>Rules consider paths, quoting, redirection, pipelines, wrappers such as <code>sudo</code> and <code>env</code>, embedded interpreter flags and relative path components. A sensitive path alone gets a review; a sensitive path flowing into an upload gets a block. Anything TraceRook can't fully inspect moves to review rather than being waved through.</p>'''),
('findings', 'Unsafe actions and agent behavior', '''<p>Findings fall into two categories. <strong>Unsafe action</strong> findings concern the proposed operation itself. <strong>Agent behavior</strong> findings concern the session: drift away from your task, instructions from repository content that redirected the agent, or repeated attempts at denied actions. Claude flags session drift directly in its verdict, and a finding can belong to both categories.</p>'''),
)

page('approvals', 'One-time approvals', 'Protection', 'Allow once releases one exact pending call, inside its deadline.',
('meaning', 'What Allow once means', '''<p><strong>Allow once</strong> releases the exact waiting tool call past TraceRook's review. It doesn't approve the session or similar future commands, and Claude Code's own permission prompts still apply afterwards. The binding covers provider, session, turn, tool-call ID, tool name, working directory and a canonical digest of the original input, plus a per-invocation nonce. A summary or a command substring is never enough to authorize anything.</p>'''),
('states', 'Each review resolves exactly once', table(['State', 'Meaning'], [
    ('pending', 'Waiting on a live, bound invocation before its deadline'),
    ('approved_once', 'The exact invocation was released past TraceRook'),
    ('denied', 'You blocked the invocation'),
    ('expired', 'The deadline passed; the call is denied'),
    ('aborted', 'The invocation disconnected, ended or changed'),
]) + '<p>Transitions are compare-and-swap writes in the service, so double-clicks, replays and simultaneous responses resolve one way only.</p>'),
('deadlines', 'Deadlines and disconnects', '''<p>You have 45 seconds to decide, inside the hook's 85-second timeout. Ending the session, disconnecting the hook or changing the action invalidates the review, and a late approval can never release a later retry. Expired reviews show <strong>No longer pending</strong> with the controls disabled.</p>'''),
('where', 'Where reviews appear', '''<p>Pending reviews open in the native review window and are listed in the menu bar and the Approvals queue, each with its countdown. Only the signed TraceRook app can resolve a review, over its authenticated connection to the background service.</p>'''),
('preview', 'You see exactly what you approve', '''<p>The review window shows the service-redacted preview of the exact pending action. If a readable preview isn't available, Allow once is disabled for that review.</p>'''),
)

page('coverage', 'What TraceRook reviews', 'Protection', 'The agents, tool calls and events that pass through TraceRook.',
('reviewed', 'Reviewed before execution', '''<p>Every tool call Claude Code sends through its <code>PreToolUse</code> hook: Bash commands, file writes and edits, and MCP tool calls. TraceRook decides before the tool body runs.</p>'''),
('status', 'Integration status', table(['Status', 'Meaning'], [
    ('Protected', 'The hook is configured and a recent pre-execution test passed'),
    ('Monitoring only', 'Events arrive; blocking for this tool class hasn\'t been tested yet'),
    ('Degraded', 'The service, provider or hook reports an error'),
    ('Verification not recent', 'The session has been idle since the last test'),
    ('Not integrated', 'No hook is connected for this agent'),
    ('Protection off', 'You paused TraceRook'),
]) + '<p>Provider health is separate from hook health: Cloud analysis paused means local rules only, not that hooks stopped working.</p>'),
('outage', 'When the service is unreachable', '''<p>The hook bridge carries the same rules as the service. If it can't reach the background service, it evaluates the action itself and denies anything with critical or high-risk evidence, plus any mutating or executing call it can't fully inspect. Everything else continues under Claude Code's own permissions.</p>'''),
('outside', 'Outside the hook', '''<p>TraceRook reviews what the agent proposes through its hook. Commands you run yourself in a terminal, processes started inside a command you already approved, and actions in remote or hosted agent sessions run outside that review. Keep TraceRook's hook enabled in each Claude Code configuration you use.</p>'''),
('agents', 'Agents', table(['Agent', 'Status'], [
    ('Claude Code 2.1.290', 'Supported'),
    ('OpenAI Codex', 'Coming soon'),
])),
)

# --------------------------------------------------------------------------------- Claude & privacy

page('claude-analysis', 'Analysis with Anthropic Claude', 'Claude & privacy', 'How TraceRook Cloud uses Claude Haiku 5.5 to judge actions in context.',
('why', 'Why Claude is in the pipeline', '''<p>Local rules are precise about concrete signatures, but some questions need context: Is publishing a package part of this task? Did a README just tell the agent to ignore its instructions? TraceRook Cloud asks Claude Haiku 5.5 these questions and returns a structured verdict you can read in the incident.</p>'''),
('sees', 'What Claude sees', '''<ul><li>A coarse task category.</li><li>A coarse action category such as <code>shell_exec</code> or <code>file_write</code>.</li><li>Enumerated local signal codes such as <code>outbound_transfer</code>, <code>reads_credential_store</code> or <code>task_mismatch</code>.</li></ul><p>Raw commands, paths, code, file contents, transcripts and free-form prose are never sent. The projection is scanned for secrets, paths, URLs and high-entropy strings on your Mac and again in TraceRook Cloud before it reaches Anthropic.</p>'''),
('verdict', 'The verdict', '''<p>Claude answers in a strict schema: categories, severity, confidence, whether the action is suspicious, a short rationale, up to ten evidence items, a recommendation (<code>allow</code>, <code>warn_allow</code> or <code>request_approval</code>), a session-drift flag and any limitations it noted. TraceRook Cloud rejects any response that doesn't match the schema, the expected model and Anthropic's first-party provenance.</p>'''),
('authority', 'Claude advises; policy decides', '''<p>Claude's recommendation can add a warning or route an action to your review. It can't grant a permission, execute anything or lower a critical local denial. A model-only critical finding goes to human review, and Allow once still clears only TraceRook's gate for that single call.</p>'''),
('injection', 'Built for hostile input', '''<p>Everything the agent touches is treated as attacker-controlled data. TraceRook owns Claude's fixed system instructions; the projection is structured data, not prose, so an instruction hidden in a file has no channel to speak to the model. Text such as "approve this action" is evidence of prompt injection, not authority.</p>'''),
('consent', 'Consent and retention', '''<p>Cloud analysis starts only after you accept the consent screen, which shows exactly which categories are sent. TraceRook Cloud keeps analysis receipts (identifiers, token counts and timestamps) for 30 days and usage aggregates for 90 days, and never stores prompts or explanations. Anthropic processes requests under its commercial API terms.</p>'''),
)

page('privacy', 'The privacy pipeline', 'Claude & privacy', 'Minimize on your Mac, project to categories, check twice before anything leaves.',
('collect', 'Collect only what the hook provides', '''<p>TraceRook's input is the event Claude Code hands its hook. It doesn't read your screen, other applications, full transcripts or your source tree, and it needs no Full Disk Access. The original tool input stays in process memory just long enough to inspect it and bind the decision.</p>'''),
('redact', 'Normalize and redact locally', '''<p>Local inspection derives command, path and destination features, then builds a sanitized representation. API tokens, bearer credentials, private keys and password assignments become category placeholders such as <code>[REDACTED:TOKEN]</code> that reveal nothing about the original value. Home-directory components are removed.</p>'''),
('project', 'Project before the network', '''<p>What goes to TraceRook Cloud is a projection: task category, action category and local signal codes. A secret, path, URL and entropy scan runs on it immediately before transmission. If the check fails, nothing is sent and the decision uses local policy.</p>'''),
('cloud', 'Checked again in the cloud', '''<p>TraceRook Cloud strictly parses every request, rejects unknown fields and oversized bodies, and repeats the secret scan. Request bodies, prompts and model explanations are never logged or stored.</p>'''),
('diagnostics', 'Sparse diagnostics', '''<p>Logs contain predefined status codes and random identifiers, never prompts, commands, provider responses or secrets. This website has no third-party analytics, trackers or external fonts.</p>'''),
)

page('data-retention', 'History, credentials & deletion', 'Claude & privacy', 'What TraceRook keeps, for how long, and how to remove it.',
('local', 'Private local history', '''<p>The background service is the only writer of <code>~/Library/Application Support/TraceRook/history.sqlite3</code>, inside a <code>0700</code> directory with <code>0600</code> database files. Only sanitized event summaries and review metadata are stored; raw commands, transcripts, model output and credentials are not.</p>'''),
('retention', 'Retention', table(['Data', 'Kept for'], [
    ('Sanitized event summaries', '14 days'),
    ('Incidents and reviews', '30 days'),
    ('Session records', 'Until their events and incidents expire'),
    ('Cloud analysis receipts', '30 days'),
    ('Cloud usage aggregates', '90 days'),
    ('Cloud verdict cache', '10 minutes'),
    ('Cloud account and device digests', 'Until you delete your account'),
])),
('credentials', 'Credentials', '''<p>Your Cloud device credential lives only in the background service's memory and is never written to disk, logs or the history database. Rotate or disconnect it from Settings at any time.</p>'''),
('delete', 'Deletion controls', '''<ul><li><strong>Delete All Local History</strong> removes retained sessions, events, findings and reviews, aborting any pending review first.</li><li><strong>Delete cloud account data</strong> removes your TraceRook Cloud account metadata and revokes every device.</li><li><strong>Disable Service</strong> in Integrations stops the background service and removes its LaunchAgent.</li></ul>'''),
('independent', 'Independent controls', '''<p>Each control does one thing: clearing history doesn't disconnect Cloud, and deleting your Cloud account doesn't touch local history on any Mac. Your Claude Code settings are yours; TraceRook never rewrites them.</p>'''),
)

# ------------------------------------------------------------------------------------------- Agents

page('claude-code', 'Claude Code', 'Agents', 'Connect TraceRook to Claude Code and keep it connected.',
('scope', 'Supported sessions', '''<p>TraceRook supports local Claude Code 2.1.290 sessions in the terminal and in IDEs, wherever Claude Code runs its hooks. Each session, including subagents, appears in the dashboard with its task anchor and timeline.</p>'''),
('configure', 'Configure the hook', f'''<p>Add TraceRook as a synchronous <code>PreToolUse</code> command hook, keeping your existing settings:</p>{code(HOOK_CONFIG)}<p>The <code>matcher: "*"</code> sends every tool call to TraceRook. The hook's 85-second timeout sits above TraceRook's 80-second budget so a 45-second human review always finishes inside the callback.</p>'''),
('decisions', 'Decisions Claude Code receives', '''<p>No override exits successfully with empty stdout and Claude Code continues with its own permission flow. A denial returns <code>hookSpecificOutput.permissionDecision = "deny"</code> with a short, sanitized reason that Claude Code shows the model, so the agent can choose a safer approach. TraceRook never grants permissions and never writes debugging text to stdout.</p>'''),
('check', 'Check the connection', '''<p>With the service running, start a new Claude Code session and run a harmless command. It appears in <strong>Sessions</strong> within a moment. Start a new session after upgrading Claude Code or moving the app so the hook path and version stay current.</p>'''),
('remove', 'Remove TraceRook', '''<p>Delete TraceRook's entry from the <code>PreToolUse</code> hooks in your Claude Code settings; every other key, matcher and hook stays as it was. <strong>Disable Service</strong> in Integrations stops the background service.</p>'''),
)

page('codex', 'Codex', 'Agents', 'OpenAI Codex support is coming soon.',
('status', 'Coming soon', '''<p>Codex support is in development. TraceRook already normalizes Codex <code>PreToolUse</code> events for Bash and <code>apply_patch</code>, and the dashboard, rules and review flow are shared with Claude Code. We'll announce Codex support to beta members when it ships.</p>'''),
('trust', 'How it will work', '''<p>Codex asks you to trust each new user hook in its <code>/hooks</code> review. TraceRook's setup will walk you through that step, and Integrations will show installation and trust as separate states so you always know where things stand.</p>'''),
('output', 'Decisions', '''<p>Codex receives the same decisions as Claude Code: a <code>deny</code> with a short reason, or no override, which leaves Codex's own approval policy in charge. TraceRook never returns permission grants.</p>'''),
('today', 'Using Codex today', '''<p>Until Codex support ships, Codex sessions run without TraceRook's review. Use Claude Code for sessions you want TraceRook to protect.</p>'''),
)

page('troubleshooting', 'Troubleshooting', 'Agents', 'Fix common setup, connection and review issues.',
('open', "macOS won't open the app", '''<p>Open TraceRook once, then choose <strong>Open Anyway</strong> in <strong>System Settings → Privacy &amp; Security</strong>. If the option is missing, your Mac may be managed by an organization policy. Verify the checksum before opening, and report any malware or damaged-app warning instead of overriding it.</p>'''),
('service', "The service won't connect", '''<p>Open <strong>Integrations</strong> and select <strong>Enable Background Service</strong>. If macOS asks for approval, allow TraceRook under <strong>System Settings → General → Login Items</strong>. Make sure the app is in its final location before enabling the service, and enable it again after moving the app.</p>'''),
('cloud', 'Cloud analysis is unavailable', '''<p>After the service restarts, enter your access code again in <strong>Settings → AI Provider → TraceRook Cloud</strong>. Check that Cloud isn't paused, then use <strong>Refresh connection and usage</strong>. Local rules keep protecting you while Cloud is unavailable.</p>'''),
('hook', 'Sessions are empty', '''<p>Confirm the hook entry is in the Claude Code settings scope you're using and that the path points at <code>TraceRook.app/Contents/MacOS/tracerook-hook</code>. Then start a new Claude Code session so it reloads its settings.</p>'''),
('reviews', "I didn't see a review", '''<p>Pending reviews are listed in the menu bar and the Approvals queue. A review that expires before you respond denies its call; the agent receives the denial and can try another approach.</p>'''),
('report', 'Reporting a problem', '''<p>Include the app version, macOS version, Claude Code version, integration status and reproduction steps. Leave out access codes, raw hook payloads, transcripts and private source. Security issues go to <a href="https://github.com/kleprevost/tracerook/security/advisories/new">GitHub security advisories</a>.</p>'''),
)

# ---------------------------------------------------------------------------------------- Reference

page('architecture', 'Architecture', 'Reference', 'Three native processes, one hosted service, and the transports between them.',
('processes', 'Processes', '''<div class="architecture-flow"><ol><li><strong>tracerook-hook</strong>Runs once per hook call: bounded stdin, normalization, emergency rules, a deadline-bound request to the service and host-format output.</li><li><strong>TraceRookAgent</strong>The per-user LaunchAgent: local policy, pending reviews and deadlines, private SQLite history and the TraceRook Cloud client.</li><li><strong>TraceRook.app</strong>SwiftUI dashboard, menu bar companion and the review window.</li><li><strong>TraceRook Cloud</strong>A Cloudflare Worker at api.tracerook.dev that authenticates devices, scans requests and runs Claude Haiku 5.5.</li></ol></div>'''),
('modules', 'Swift modules', table(['Module', 'Responsibility'], [
    ('TraceRookContracts', 'Event envelopes, bounded JSON, IPC v2 framing, replies, budgets and typed errors'),
    ('TraceRookPrivacy', 'Redaction, remote preflight and status-code logging'),
    ('TraceRookAgentAdapters', 'Claude Code and Codex normalization, denial output and action fingerprints'),
    ('TraceRookRules', 'Deterministic policy shared by the service and the hook bridge'),
    ('TraceRookCore', 'Domain records, review transitions, analysis providers and Cloud DTOs'),
    ('TraceRookFixtures', 'Sample data for demo mode'),
])),
('transports', 'Transports', '''<ul><li><strong>Hook socket</strong>: a private Unix socket (<code>0700</code> directory, <code>0600</code> socket) with kernel peer credentials. It carries events and decisions only.</li><li><strong>XPC</strong>: code-signing requirements on both sides. It carries status, Cloud controls and review resolutions.</li><li><strong>Cloud</strong>: HTTPS with an opaque bearer device token, strict JSON and a 32 KiB body limit.</li></ul>'''),
('concurrency', 'Concurrency and state', '''<p>Service state lives in Swift actors and UI state on the main actor, under Swift 6 strict concurrency. The service is the single writer of local history and uses transactional compare-and-swap updates for reviews. In TraceRook Cloud, a SQLite Durable Object serializes usage accounting and device-scoped idempotency, and D1 holds account and device digests.</p>'''),
('dependencies', 'Dependencies', '''<p>The Mac app has no third-party runtime dependencies, no root daemon and no system extension, and needs no Full Disk Access, Accessibility or Screen Recording permission. The Cloud Worker has no runtime npm dependencies.</p>'''),
)

page('protocols', 'Events & IPC', 'Reference', 'Bounded input, normalized events, exact fingerprints and host output.',
('input', 'Bounded input', '''<p>The hook bridge reads at most 1 MiB of stdin, limits nesting to 32 levels, caps strings, objects and arrays, rejects duplicate keys at every depth and invalid UTF-8, and keeps numbers as precise decimals so two different actions can never share a fingerprint.</p>'''),
('framing', 'IPC v2 framing', table(['Property', 'Value'], [
    ('Framing', 'Four-byte big-endian length prefix, one JSON packet'),
    ('Request cap', '1 MiB'),
    ('Reply cap', '16 KiB'),
    ('Invocation nonce', '128-bit system-random, 32 lowercase hex characters'),
    ('Replies', 'no_override or deny, matching the request ID'),
    ('Budgets', 'Hook 80 s, model 8 s, review 45 s, output reserve 1 s'),
])),
('fingerprint', 'Action fingerprints', '''<p>A review binds to a SHA-256 digest of the canonical, unmodified tool input together with provider, session, turn, tool-call ID, tool name and working directory. The original input lives only in memory for the duration of the decision.</p>'''),
('output', 'Host output', '''<p>No override is an empty stdout with exit code 0. A denial is <code>{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "…"}}</code>. Diagnostics go to sanitized stderr and never contaminate stdout.</p>'''),
('cloud', 'Cloud API', '''<p>The service calls <code>https://api.tracerook.dev/v1</code>: <code>alpha/enroll</code>, <code>capabilities</code>, <code>usage</code>, <code>analysis</code>, <code>device/rotate</code>, <code>device/revoke</code> and <code>privacy/delete</code>. Requests are strict JSON up to 32 KiB with a client deadline; responses carry a server trace ID and <code>Cache-Control: no-store</code>. The full contract is in <a href="https://github.com/kleprevost/tracerook/blob/main/cloud/CONTRACT.md">cloud/CONTRACT.md</a>.</p>'''),
)

page('build', 'Build from source', 'Reference', 'Build, run and test TraceRook yourself.',
('requirements', 'Requirements', '''<p>An Apple Silicon Mac with macOS 26 or later, Swift 6 and the macOS 27 SDK. Full Xcode 27 builds archives; Command Line Tools build the app with the repository scripts.</p>'''),
('build', 'Build and run', code('''./scripts/build.sh
open build/TraceRook.app
open build/TraceRook.app --args --demo''') + '<p><code>./scripts/build.sh release</code> builds the optimized configuration. Open <code>TraceRook.xcodeproj</code> and select the TraceRook scheme to work in Xcode.</p>'),
('test', 'Tests', code('''./scripts/test.sh
./scripts/smoke-test.sh
./scripts/ui-smoke-test.sh''') + '<p>The smoke test builds all three executables and checks packaged helpers and bundle resources. The UI smoke test renders every dashboard destination in light and dark appearance under <code>build/ui-smoke/</code>.</p>'),
('cloud', 'TraceRook Cloud and the local API', code('''cd cloud && npm ci && npm test
cd backend && python3 -m venv .venv && .venv/bin/pip install -e '.[dev]' && .venv/bin/pytest -q''') + '<p>Cloud tests run inside workerd with real D1 and Durable Object bindings and a fake Anthropic transport. The Python local API serves fixture-backed Cloud flows on <code>127.0.0.1:8787</code> for development.</p>'),
('demo', 'Demo mode', '''<p>Launch with <code>--demo</code>, or choose <strong>Explore Demo</strong>, to load sample sessions, incidents and a sample review with a 45-second deadline. Demo data stays separate from real activity and can't approve a real action.</p>'''),
)

page('faq', 'FAQ', 'Reference', 'Straight answers about TraceRook, Claude and your data.',
('faq', 'Questions', '''<details><summary>Do I need an Anthropic API key?</summary><p>No. Beta access includes TraceRook Cloud, which runs Claude on TraceRook's Anthropic account. You connect with an access code.</p></details><details><summary>Does my code leave my Mac?</summary><p>No. TraceRook Cloud receives a task category, an action category and local signal codes. Commands, paths, code, file contents and transcripts stay on your Mac.</p></details><details><summary>Can Claude approve an action?</summary><p>No. Claude's verdict can add a warning or ask for your review. Only you can Allow once, and only for one exact pending call.</p></details><details><summary>What happens if I don't respond to a review?</summary><p>After 45 seconds the review expires and the call is denied. The agent receives the denial and can try another approach.</p></details><details><summary>Does Allow once skip Claude Code's permissions?</summary><p>No. It clears TraceRook's review for that call; Claude Code's own permission prompts still apply.</p></details><details><summary>Does it work offline?</summary><p>Yes. Local rules and native review run entirely on your Mac. Only contextual Claude analysis needs TraceRook Cloud.</p></details><details><summary>Which agents are supported?</summary><p>Claude Code 2.1.290 today. Codex support is coming soon.</p></details><details><summary>How much does it cost?</summary><p>Beta access is $20/month and includes TraceRook Cloud. See <a href="/pricing/">pricing</a>.</p></details>'''),
('glossary', 'Glossary', table(['Term', 'Meaning'], [
    ('Task anchor', 'A short redacted summary of what you asked the agent to do'),
    ('Projection', 'The category-and-signal form of an action that TraceRook Cloud analyzes'),
    ('Fingerprint', 'SHA-256 digest binding a review to one exact tool call'),
    ('Allow once', "Releases one pending call past TraceRook's review"),
    ('Drift', 'Agent behavior moving away from the task anchor'),
    ('Critical rule', 'A deterministic rule that denies automatically on concrete evidence'),
])),
('contact', 'Contact', '''<p>Beta members can reach us through the channel in their invitation. Report security issues through <a href="https://github.com/kleprevost/tracerook/security/advisories/new">GitHub security advisories</a>.</p>'''),
)
