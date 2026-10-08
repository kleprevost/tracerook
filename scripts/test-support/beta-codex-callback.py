#!/usr/bin/env python3
"""Actual installed Codex callbacks; deterministic loopback Responses double only."""
import argparse, http.server, json, os, pathlib, shlex, shutil, subprocess, tempfile, threading

p = argparse.ArgumentParser()
p.add_argument('--helper', type=pathlib.Path, required=True)
p.add_argument('--coordinated', action='store_true')
p.add_argument('--review-hooks', action='store_true', help='Open isolated native Codex TUI for /hooks trust review before exec')
p.add_argument('--case', choices=['deny', 'timeout', 'outage'], default='deny')
a = p.parse_args()
if not a.coordinated: p.error('coordinate stable signed bundle/service with owner first')
helper = a.helper.resolve(strict=True)
if not os.access(helper, os.X_OK): p.error('helper is not executable')
codex = shutil.which('codex')
if not codex: p.error('Codex unavailable')
version = subprocess.check_output([codex, '--version'], text=True).strip()
with tempfile.TemporaryDirectory(prefix='tracerook-beta-codex-') as temporary:
    root = pathlib.Path(temporary); root.chmod(0o700)
    project = root / 'project'; project.mkdir()
    config = root / 'config'; config.mkdir()
    records_file = root / 'callbacks.jsonl'
    (project / '.claude').mkdir()
    (project / '.claude/settings.local.json').write_text('{}')
    commands = ['printf benign > benign-sentinel', 'rm -f .claude/settings.local.json; printf denied > denied-sentinel'] if a.case == 'deny' else ['sudo --version; printf denied > denied-sentinel']
    wrapper = root / 'callback.py'
    wrapper.write_text('''import json,subprocess,sys
raw=sys.stdin.buffer.read()
r=subprocess.run(sys.argv[1:],input=raw,capture_output=True)
with open(''' + repr(str(records_file)) + ''','a') as out:
 out.write(json.dumps({'payload':json.loads(raw),'exit':r.returncode,'stdout':r.stdout.decode(errors='replace')})+'\\n')
sys.stdout.buffer.write(r.stdout);sys.stderr.buffer.write(r.stderr);sys.exit(r.returncode)
''')
    callback = shlex.join([shutil.which('python3'), str(wrapper), str(helper), '--adapter', 'codex', '--host-version', version, '--timeout-ms', '4000' if a.case == 'timeout' else '80000'])
    (config / 'hooks.json').write_text(json.dumps({'hooks': {'PreToolUse': [{'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': callback, 'timeout': 10 if a.case != 'outage' else 5}]}]}}))
    class Responses(http.server.BaseHTTPRequestHandler):
        calls = 0
        offered = []
        def log_message(self, *_): pass
        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            raw = self.rfile.read(length)
            if self.headers.get('Content-Encoding') == 'gzip':
                import gzip
                raw = gzip.decompress(raw)
            request = json.loads(raw)
            tools = request.get('tools', [])
            def functions(items):
                for item in items:
                    if item.get('type') == 'function': yield item
                    elif item.get('type') == 'namespace': yield from functions(item.get('tools', []))
            available = list(functions(tools))
            Responses.offered = [f.get('name', '') for f in available]
            index = Responses.calls; Responses.calls += 1
            if index < len(commands):
                tool = next((f for f in available if f.get('name', '').split('.')[-1] in ['shell_command','exec_command','shell']), None)
                if tool is None:
                    self.send_response(422); self.end_headers(); return
                name = tool['name']; leaf = name.split('.')[-1]
                arguments = {'cmd' if leaf == 'exec_command' else 'command': commands[index]}
                properties = tool.get('parameters', {}).get('properties', {})
                if 'workdir' in properties: arguments['workdir'] = str(project)
                if 'login' in properties: arguments['login'] = False
                output = {'type':'function_call','id':'fc_beta_'+str(index),'call_id':'call_beta_'+str(index),'name':name,'arguments':json.dumps(arguments),'status':'completed'}
            else:
                output = {'type':'message','id':'msg_beta_'+str(index),'role':'assistant','status':'completed','content':[{'type':'output_text','text':'Done.','annotations':[]}]}
            response = {'id':'resp_beta_'+str(index),'object':'response','created_at':1,'status':'completed','model':request.get('model','gpt-test'), 'output':[output], 'usage':{'input_tokens':1,'output_tokens':1,'total_tokens':2}}
            self.send_response(200); self.send_header('Content-Type','text/event-stream'); self.end_headers()
            def emit(kind, body):
                self.wfile.write(('event: '+kind+'\ndata: '+json.dumps(dict(type=kind, **body))+'\n\n').encode()); self.wfile.flush()
            emit('response.created', {'response':dict(response,status='in_progress',output=[])})
            initial = dict(output, status='in_progress')
            initial['arguments' if output['type'] == 'function_call' else 'content'] = '' if output['type'] == 'function_call' else []
            emit('response.output_item.added', {'output_index':0,'item':initial})
            if output['type'] == 'function_call':
                emit('response.function_call_arguments.delta', {'output_index':0,'item_id':output['id'],'delta':output['arguments']})
                emit('response.function_call_arguments.done', {'output_index':0,'item_id':output['id'],'arguments':output['arguments']})
            else:
                emit('response.output_text.delta', {'output_index':0,'item_id':output['id'],'content_index':0,'delta':'Done.'})
            emit('response.output_item.done', {'output_index':0,'item':output})
            emit('response.completed', {'response':response})
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Responses)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    # This is an isolated subprocess config location, never an assignment to the
    # owner's shell CODEX_HOME. File-only auth avoids Keychain credential storage.
    (config / 'config.toml').write_text('''model = "gpt-test"
model_provider = "beta_local"
cli_auth_credentials_store = "file"
approval_policy = "never"
sandbox_mode = "workspace-write"
[shell_environment_policy]
inherit = "none"
[model_providers.beta_local]
name = "Private loopback test double"
base_url = "http://127.0.0.1:''' + str(server.server_port) + '''/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
request_max_retries = 0
stream_max_retries = 0
''')
    env = {'PATH':os.environ.get('PATH','/usr/bin:/bin'), 'TMPDIR':temporary, 'CODEX_HOME':str(config)}
    try:
        if a.review_hooks:
            print('Review the exact private PreToolUse hook using /hooks in the native CLI, then exit the TUI. No model prompt is needed.', flush=True)
            review = subprocess.run([codex, '--no-daemon', '--cd', str(project)], cwd=project, env=env)
            if review.returncode:
                raise SystemExit(review.returncode)
        run = subprocess.run([codex,'--no-daemon','exec','--strict-config','--ignore-rules','--skip-git-repo-check','--ephemeral','--json','--cd',str(project),'Execute the supplied test tools.'],cwd=project,env=env,capture_output=True,timeout=60)
        records = [json.loads(line) for line in records_file.read_text().splitlines()] if records_file.exists() else []
        def denied(record):
            if record['exit'] == 2: return True
            try:
                out = json.loads(record['stdout']).get('hookSpecificOutput', {})
                return out.get('hookEventName') == 'PreToolUse' and out.get('permissionDecision') == 'deny'
            except (ValueError, AttributeError): return False
        actual_denial = any(r['payload'].get('tool_input', {}).get('command') == commands[-1] and denied(r) for r in records)
        benign = (project/'benign-sentinel').exists() if a.case == 'deny' else None
        absent = not (project/'denied-sentinel').exists()
        result = {'kind':'actual_codex_callback_local_model_double','case':a.case,'host_version':version,'host_exit':run.returncode,'callback_count':len(records),'benign_executed':benign,'dangerous_denied':actual_denial,'denied_sentinel_absent':absent,'model_requests':Responses.calls,'offered_shell_tools':[t for t in Responses.offered if t.split('.')[-1] in ['shell_command','exec_command','shell']]}
        print(json.dumps(result,sort_keys=True))
        # Isolated stderr can contain generated project paths; only emit bounded
        # issue categories for a failed protocol/config gate, never full raw logs.
        if run.returncode or not (absent and actual_denial and (benign or a.case != 'deny')):
            print(json.dumps({'diagnostic_categories':[word for word in ['unknown','unrecognized','trust','authentication','stream','configuration','error','failed'] if word in run.stderr.decode(errors='replace').lower()]}))
            raise SystemExit(1)
    finally:
        server.shutdown()
