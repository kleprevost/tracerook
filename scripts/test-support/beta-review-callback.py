#!/usr/bin/env python3
"""Actual Claude hook + service-owned high-risk review, with a local model double.
Requires a coordinated real native UI click; never writes a service resolution.
The parent must pair this host receipt with the persisted exact approval state.
"""
import argparse, http.server, json, os, pathlib, shlex, shutil, subprocess, tempfile, threading, time

parser = argparse.ArgumentParser()
parser.add_argument('--helper', required=True, type=pathlib.Path)
parser.add_argument('--coordinated', action='store_true')
parser.add_argument('--choice', choices=['allow', 'block'], required=True)
parser.add_argument('--receipt', required=True, type=pathlib.Path)
parser.add_argument('--ready-file', required=True, type=pathlib.Path)
args = parser.parse_args()
if not args.coordinated:
    parser.error('coordinate signed service availability and explicit host execution with the owner first')
helper = args.helper.resolve(strict=True)
receipt = args.receipt.resolve()
ready_file = args.ready_file.resolve()
if receipt == ready_file:
    parser.error('receipt and ready file must differ')
receipt.parent.mkdir(parents=True, exist_ok=True)
ready_file.parent.mkdir(parents=True, exist_ok=True)
for output in (receipt, ready_file):
    if output.exists():
        parser.error('choose fresh evidence paths; existing evidence is never overwritten')
if not os.access(helper, os.X_OK):
    parser.error('helper must be executable')
claude = shutil.which('claude')
if not claude:
    parser.error('Claude CLI unavailable')

with tempfile.TemporaryDirectory(prefix='tracerook-beta-review-') as temp:
    root = pathlib.Path(temp)
    root.chmod(0o700)
    project = root / 'project'
    project.mkdir()
    config = root / 'config'
    config.mkdir()
    callbacks = root / 'callbacks.jsonl'
    wrapper = root / 'callback.py'
    wrapper.write_text('''import json,subprocess,sys,time
payload=sys.stdin.buffer.read()
with open(''' + repr(str(ready_file)) + ''','x') as f:
 f.write(json.dumps({'phase':'awaiting_native_ui_review','expected_choice':''' + repr(args.choice) + ''','host':'claude_code','tool':'Bash','command':'sudo --version; printf reviewed > review-sentinel'})+'\\n')
began=time.monotonic()
p=subprocess.run(sys.argv[1:],input=payload,capture_output=True)
elapsed=time.monotonic()-began
with open(''' + repr(str(callbacks)) + ''','a') as f:
 f.write(json.dumps({'payload':json.loads(payload),'exit':p.returncode,'elapsed_seconds':round(elapsed,3),'stdout':p.stdout.decode(errors='replace')})+'\\n')
sys.stdout.buffer.write(p.stdout);sys.stderr.buffer.write(p.stderr);sys.exit(p.returncode)
''')
    command = shlex.join([shutil.which('python3'), str(wrapper), str(helper), '--adapter', 'claude_code', '--host-version', subprocess.check_output([claude, '--version'], text=True).strip(), '--timeout-ms', '50000'])
    settings = root / 'settings.json'
    settings.write_text(json.dumps({'hooks': {'PreToolUse': [{'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': command, 'timeout': 60}]}]}, 'permissions': {'allow': ['Bash']}}))
    # High-risk privilege elevation with no mutation from sudo; the only
    # mutation is a disposable sentinel, which must follow the user's review.
    commands = ["sudo --version; printf reviewed > review-sentinel"]
    class Model(http.server.BaseHTTPRequestHandler):
        calls = 0
        def log_message(self, *_): pass
        def do_POST(self):
            payload = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
            index = Model.calls
            Model.calls += 1
            blocks = [{'type': 'tool_use', 'id': 'toolu_beta_' + str(index), 'name': 'Bash', 'input': {'command': commands[index]}}] if index < len(commands) else [{'type': 'text', 'text': 'Done.'}]
            reply = {'id': 'msg_beta_' + str(index), 'type': 'message', 'role': 'assistant', 'model': payload.get('model', 'local-test'), 'content': blocks, 'stop_reason': 'tool_use' if index < len(commands) else 'end_turn', 'stop_sequence': None, 'usage': {'input_tokens': 1, 'output_tokens': 1}}
            self.send_response(200)
            if not payload.get('stream'):
                self.send_header('Content-Type', 'application/json'); self.end_headers(); self.wfile.write(json.dumps(reply).encode()); return
            self.send_header('Content-Type', 'text/event-stream'); self.end_headers()
            def emit(kind, value): self.wfile.write(('event: '+kind+'\ndata: '+json.dumps(value)+'\n\n').encode()); self.wfile.flush()
            start = dict(reply, content=[], stop_reason=None)
            emit('message_start', {'type':'message_start','message':start})
            for i, block in enumerate(blocks):
                initial = dict(block)
                initial['input' if block['type']=='tool_use' else 'text'] = {} if block['type']=='tool_use' else ''
                emit('content_block_start', {'type':'content_block_start','index':i,'content_block':initial})
                delta = {'type':'input_json_delta','partial_json':json.dumps(block['input'])} if block['type']=='tool_use' else {'type':'text_delta','text':block['text']}
                emit('content_block_delta', {'type':'content_block_delta','index':i,'delta':delta})
                emit('content_block_stop', {'type':'content_block_stop','index':i})
            emit('message_delta', {'type':'message_delta','delta':{'stop_reason':reply['stop_reason'],'stop_sequence':None},'usage':{'output_tokens':1}})
            emit('message_stop', {'type':'message_stop'})
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Model)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    # Fresh env strips all founder credential/provider overrides. Explicit dummy
    # API key selects API-key authentication; config is private and disposable.
    env = {'PATH': os.environ.get('PATH', '/usr/bin:/bin'), 'TMPDIR': temp,
           'CLAUDE_CONFIG_DIR': str(config), 'ANTHROPIC_API_KEY': 'local-test-no-credential',
           'ANTHROPIC_BASE_URL': 'http://127.0.0.1:'+str(server.server_port),
           'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1', 'DISABLE_AUTOUPDATER': '1'}
    try:
        began = time.monotonic()
        run = subprocess.run([claude, '-p', 'Execute the supplied test tools.', '--settings', str(settings), '--setting-sources', '', '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}', '--no-session-persistence', '--permission-mode', 'dontAsk', '--output-format', 'json', '--max-budget-usd', '0.01'], cwd=project, env=env, capture_output=True, timeout=75)
        records = [json.loads(line) for line in callbacks.read_text().splitlines()] if callbacks.exists() else []
        elapsed = time.monotonic() - began
        sentinel = (project / 'review-sentinel').exists()
        def is_deny(record):
            if record['exit'] == 2:
                return True
            try:
                decision = json.loads(record['stdout']).get('hookSpecificOutput', {})
                return decision.get('hookEventName') == 'PreToolUse' and decision.get('permissionDecision') == 'deny'
            except (ValueError, AttributeError):
                return False
        matching = [r for r in records if r['payload'].get('tool_input', {}).get('command') == commands[0]]
        callback = matching[0] if len(matching) == 1 else None
        callback_elapsed = callback.get('elapsed_seconds', 0) if callback else 0
        denied = bool(callback and is_deny(callback))
        no_override = bool(callback and callback['exit'] == 0 and not callback['stdout'].strip())
        timely = bool(callback and callback_elapsed < 42)
        expected_behavior = (sentinel and no_override) if args.choice == 'allow' else (not sentinel and denied)
        success = run.returncode == 0 and len(records) == 1 and timely and expected_behavior
        result = {'kind':'actual_claude_review_callback_local_model_double', 'expected_choice':args.choice,
                  'host_version':subprocess.check_output([claude, '--version'], text=True).strip(),
                  'callback_elapsed_seconds':callback_elapsed,'elapsed_seconds':round(elapsed,3),
                  'host_exit':run.returncode,'callback_count':len(records), 'review_sentinel_present':sentinel,
                  'hook_denied':denied,'hook_no_override':no_override,'returned_before_review_expiry':timely,
                  'host_behavior_passed':success,'native_ui_choice_requires_persisted_approval_evidence':True,
                  'host_model_provider':'loopback_double','cloud_must_be_paused_by_operator':True}
        receipt.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
        print(json.dumps(result, sort_keys=True), flush=True)
        if not success: raise SystemExit(1)
    finally:
        server.shutdown()
