import asyncio
import json
from uuid import uuid4
import httpx
import pytest
from fastapi.testclient import TestClient
from tracerook_backend.mock import create_mock_app, fixture

@pytest.fixture
def client():
    with TestClient(create_mock_app(),base_url="http://127.0.0.1:8787") as c:
        yield c

def enroll(c):
    r=c.post('/mock/v1/alpha/enroll',json=dict(invitation_id='local-demo',consent=True,privacy_policy_version=2))
    assert r.status_code==200
    b=r.json()
    return b['device_id'],{'Authorization':'Bearer '+b['device_token']}

def payload(device, scenario='benign'):
    return dict(schema_version=1,simulation=True,request_id=str(uuid4()),device_id=device,session_pseudonym=str(uuid4()),source='claude_code',event='pre_tool_use',deadline_ms=3000,privacy_policy_version=2,scenario=scenario,context=fixture(scenario))

def test_auth_rotation_delete(client):
    d,h=enroll(client)
    assert client.get('/mock/v1/usage').status_code==401
    assert client.get('/mock/v1/capabilities',headers=h).json()['provider_ready'] is False
    assert client.post('/mock/v1/device/rotate',json={'device_id':str(uuid4())},headers=h).status_code==403
    rotated=client.post('/mock/v1/device/rotate',json={'device_id':d},headers=h).json()
    assert client.get('/mock/v1/usage',headers=h).status_code==401
    h={'Authorization':'Bearer '+rotated['device_token']}
    assert client.post('/mock/v1/privacy/delete',json={'device_id':d,'confirm':False},headers=h).status_code==400
    assert client.post('/mock/v1/privacy/delete',json={'device_id':d,'confirm':True},headers=h).json()['deleted']
    assert client.get('/mock/v1/usage',headers=h).status_code==401

def test_expiry():
    now=[0]
    with TestClient(create_mock_app(clock=lambda:now[0]),base_url='http://127.0.0.1:8787') as c:
        d,h=enroll(c);now[0]=3600
        assert c.get('/mock/v1/usage',headers=h).status_code==401

def test_boundary(client):
    for headers in [{'Origin':'null'},{'Host':'evil.example'},{'Host':'127.0.0.1:9999'}]:
        assert client.get('/mock/v1/healthz',headers=headers).status_code==403
    assert client.get('/mock/v1/healthz?x=1').status_code==403
    assert client.get('/v1/analyze').status_code==404
    assert client.put('/mock/v1/healthz').status_code==405
    for raw in [b'{"consent":true,"consent":false}',b'\xff',b'{"x":NaN}',b'{"nested":{"x":1,"x":2}}']:
        assert client.post('/mock/v1/alpha/enroll',content=raw,headers={'Content-Type':'application/json'}).status_code==400
    assert client.post('/mock/v1/alpha/enroll',content=b' '*32769,headers={'Content-Type':'application/json'}).status_code==413

def test_fixture_idempotency_quota(client):
    d,h=enroll(client);p=payload(d)
    r=client.post('/mock/v1/analysis',json=p,headers=h)
    assert r.status_code==200
    b=r.json();assert b['usage']==dict(input_tokens=0,output_tokens=0,billed_units=0)
    assert b['provenance']['provider']=='fixture' and b['simulation']
    assert client.post('/mock/v1/analysis',json=p,headers=h).json()==b
    p['deadline_ms']=2000
    assert client.post('/mock/v1/analysis',json=p,headers=h).status_code==409
    p=payload(d);p['context']['proposed_action_summary']='real arbitrary payload'
    assert client.post('/mock/v1/analysis',json=p,headers=h).status_code==400
    p=payload(d);p['unknown']=True
    assert client.post('/mock/v1/analysis',json=p,headers=h).status_code==400
    for _ in range(29):
        assert client.post('/mock/v1/analysis',json=payload(d),headers=h).status_code==200
    assert client.get('/mock/v1/usage',headers=h).json()['fixture_evaluations']==30
    assert client.post('/mock/v1/analysis',json=payload(d),headers=h).status_code==429

@pytest.mark.parametrize('scenario,status',[('provider_unavailable',503),('quota_exhausted',429),('deadline_exceeded',504)])
def test_scenarios(client,scenario,status):
    d,h=enroll(client);p=payload(d,scenario)
    r=client.post('/mock/v1/analysis',json=p,headers=h)
    assert r.status_code==status and r.json()['error']['code']==scenario
    assert client.post('/mock/v1/analysis',json=p,headers=h).json()==r.json()
    assert client.get('/mock/v1/usage',headers=h).json()['fixture_evaluations']==0

def test_concurrent_duplicate():
    async def run():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=create_mock_app()),base_url='http://127.0.0.1:8787') as c:
            r=await c.post('/mock/v1/alpha/enroll',json=dict(invitation_id='local-demo',consent=True,privacy_policy_version=2))
            d=r.json();h={'Authorization':'Bearer '+d['device_token']};p=payload(d['device_id'])
            results=await asyncio.gather(*[c.post('/mock/v1/analysis',json=p,headers=h) for _ in range(10)])
            assert all(r.status_code==200 for r in results)
            assert len({json.dumps(r.json(),sort_keys=True) for r in results})==1
            assert (await c.get('/mock/v1/usage',headers=h)).json()['fixture_evaluations']==1
    asyncio.run(run())

def test_revoke_and_strict_principal(client):
    d,h=enroll(client)
    p=payload(str(uuid4()))
    assert client.post('/mock/v1/analysis',json=p,headers=h).status_code==403
    p=payload(d);p['schema_version']=True
    assert client.post('/mock/v1/analysis',json=p,headers=h).status_code==400
    p=payload(d);p['context']['contains_code_excerpts']=0
    assert client.post('/mock/v1/analysis',json=p,headers=h).status_code==400
    assert client.post('/mock/v1/device/revoke',json={'device_id':d},headers=h).json()['revoked']
    assert client.get('/mock/v1/capabilities',headers=h).status_code==401
