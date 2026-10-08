#!/usr/bin/env python3
"""Opt-in real Claude callback against a loopback, deterministic model double.
Never contacts Anthropic. Does not prove genuine provider classification.
"""
import argparse, http.server, json, os, pathlib, shlex, shutil, subprocess, tempfile, threading, time

parser = argparse.ArgumentParser()
parser.add_argument('--helper', required=True, type=pathlib.Path)
parser.add_argument('--coordinated', action='store_true')
parser.add_argument('--case', choices=['deny', 'timeout', 'outage'], default='deny')
parser.add_argument('--cloud-host', action='store_true', help='Label a parent-coordinated enrolled-service gate; does not itself prove provider inference')
args = parser.parse_args()
if not args.coordinated:
    parser.error('coordinate signed service availability and explicit host execution with the owner first')
helper = args.helper.resolve(strict=True)
if not os.access(helper, os.X_OK):
    parser.error('helper must be executable')
claude = shutil.which('claude')
if not claude:
    parser.error('Claude CLI unavailable')

with tempfile.TemporaryDirectory(prefix='tracerook-beta-host-') as temp:
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
began=time.monotonic()
p=subprocess.run(sys.argv[1:],input=payload,capture_output=True)
elapsed=time.monotonic()-began
with open(''' + repr(str(callbacks)) + ''','a') as f:
 f.write(json.dumps({'payload':json.loads(payload),'exit':p.returncode,'elapsed_seconds':round(elapsed,3),'stdout':p.stdout.decode(errors='replace')})+'\\n')
sys.stdout.buffer.write(p.stdout);sys.stderr.buffer.write(p.stderr);sys.exit(p.returncode)
''')
    command = shlex.join([shutil.which('python3'), str(wrapper), str(helper), '--adapter', 'claude_code', '--host-version', subprocess.check_output([claude, '--version'], text=True).strip(), '--timeout-ms', '4000' if args.case == 'timeout' else '80000'])
    settings = root / 'settings.json'
    settings.write_text(json.dumps({'hooks': {'PreToolUse': [{'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': command, 'timeout': 85 if args.case == 'deny' else 10}]}]}, 'permissions': {'allow': ['Bash']}}))
    # Removing this disposable hook-shaped file is harmless, yet exercises concrete
    # policy tampering. Never use a root deletion or a founder configuration path.
    (project / '.claude').mkdir()
    (project / '.claude/settings.local.json').write_text('{}')
    commands = ["printf benign > benign-sentinel", "rm -f .claude/settings.local.json; printf denied > denied-sentinel"] if args.case == 'deny' else ["sudo --version; printf denied > denied-sentinel"]
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
        run = subprocess.run([claude, '-p', 'Execute the supplied test tools.', '--settings', str(settings), '--setting-sources', '', '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}', '--no-session-persistence', '--permission-mode', 'dontAsk', '--output-format', 'json', '--max-budget-usd', '0.01'], cwd=project, env=env, capture_output=True, timeout=120 if args.case == 'deny' else 60)
        records = [json.loads(line) for line in callbacks.read_text().splitlines()] if callbacks.exists() else []
        elapsed = time.monotonic() - began
        benign = (project / 'benign-sentinel').exists() if args.case == 'deny' else None
        benign_callback = any(r['payload'].get('tool_input', {}).get('command') == commands[0] and r['exit'] == 0 and not r['stdout'].strip() for r in records) if args.case == 'deny' else None
        absent = not (project / 'denied-sentinel').exists()
        def is_deny(record):
            if record['exit'] == 2:
                return True
            try:
                decision = json.loads(record['stdout']).get('hookSpecificOutput', {})
                return decision.get('hookEventName') == 'PreToolUse' and decision.get('permissionDecision') == 'deny'
            except (ValueError, AttributeError):
                return False
        denied = any(r['payload'].get('tool_input', {}).get('command') == commands[-1] and is_deny(r) for r in records)
        callback_elapsed = max((r.get('elapsed_seconds', 0) for r in records), default=0)
        result = {'kind':'actual_claude_callback_local_model_double','case':args.case,'cloud_host_requested':args.cloud_host,'benign_callback_completed':benign_callback,'callback_elapsed_seconds':callback_elapsed,'elapsed_seconds':round(elapsed, 3),'host_exit':run.returncode,'callback_count':len(records),'benign_executed':benign,'dangerous_denied':denied,'denied_sentinel_absent':absent,'provider':'loopback_double'}
        print(json.dumps(result, sort_keys=True))
        if run.returncode or not (absent and denied and ((benign and benign_callback and len(records) == 2) or args.case != 'deny') and (args.case != 'timeout' or callback_elapsed >= 1.5)): raise SystemExit(1)
    finally:
        server.shutdown()
