"""Actual loopback HTTP check, including factory isolation and bearer verification."""
import subprocess
import time
from pathlib import Path
import httpx
from test_mock import payload

def test_local_http():
    backend=Path(__file__).resolve().parents[1]
    process=subprocess.Popen([str(backend/'.venv/bin/python'),'-m','uvicorn','tracerook_backend.app:app_factory','--factory','--host','127.0.0.1','--port','8787','--no-access-log'],cwd=backend,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        with httpx.Client(base_url='http://127.0.0.1:8787',timeout=2) as c:
            for _ in range(50):
                if process.poll() is not None:
                    raise AssertionError('Local server exited; port must be free')
                try:
                    health=c.get('/mock/v1/healthz')
                    break
                except httpx.ConnectError:
                    time.sleep(.05)
            else:
                raise AssertionError('Local server did not start')
            assert health.json()['simulation'] and not health.json()['provider_ready']
            assert c.get('/v1/plans').status_code==404
            e=c.post('/mock/v1/alpha/enroll',json=dict(invitation_id='local-demo',consent=True,privacy_policy_version=2)).json()
            h={'Authorization':'Bearer '+e['device_token']}
            assert c.get('/mock/v1/usage',headers={'Authorization':'Bearer mock_invalid'}).status_code==401
            r=c.post('/mock/v1/analysis',json=payload(e['device_id'],'credential_transfer'),headers=h)
            assert r.status_code==200 and r.json()['usage']['billed_units']==0
            assert r.json()['provenance']['provider']=='fixture'
            assert c.get('/mock/v1/usage',headers=h).json()['fixture_evaluations']==1
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill();process.wait(timeout=5)
