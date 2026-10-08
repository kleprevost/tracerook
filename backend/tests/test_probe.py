import asyncio
import importlib.util
import json
from pathlib import Path
import httpx
import pytest

spec=importlib.util.spec_from_file_location('probe_anthropic',Path(__file__).resolve().parents[1]/'scripts/probe_anthropic.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)

VERDICT=dict(schema_version=1,category=['unsafe_action'],severity='low',confidence=.8,suspicious=False,rationale='Synthetic routine UI test.',evidence=[],recommended_action='allow',session_drift=False,limitations=['Synthetic context only.'])
def response(**changes):
    b=dict(model=p.MODEL,usage=dict(input_tokens=123,output_tokens=80),stop_reason='end_turn',content=[dict(type='thinking',thinking='hidden'),dict(type='text',text=json.dumps(VERDICT))]);b.update(changes);return b

def run(handler,deadline=30):
    async def invoke():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
            return await p.probe(c,deadline_seconds=deadline)
    return asyncio.run(invoke())

def test_success_bounds_first_party_schema_and_block_selection():
    seen=[]
    def handler(request):
        seen.append(request)
        assert request.url.host=='api.anthropic.com' and request.url.scheme=='https'
        assert request.extensions['timeout']['read']==30
        if request.method=='GET':
            assert request.url.path=='/v1/models/'+p.MODEL
            return httpx.Response(200,json={'id':p.MODEL})
        body=json.loads(request.content)
        assert body['max_tokens']==800 and body['model']==p.MODEL
        assert body['output_config']['effort']=='low'
        assert body['output_config']['format']['schema']==p.VERDICT_JSON_SCHEMA
        assert not {'tools','fallbacks','temperature','top_p','top_k'} & body.keys()
        assert json.loads(body['messages'][0]['content'])=={'untrusted':p.CONTEXT}
        return httpx.Response(200,json=response())
    result=run(handler)
    assert result['status']=='ok' and result['verdict_validated']
    assert result['model']==p.MODEL and result['input_tokens']==123
    assert len(seen)==2

@pytest.mark.parametrize('status,code',[(401,'unauthorized'),(403,'forbidden'),(404,'model_unavailable'),(429,'rate_limited'),(500,'provider_unavailable'),(529,'overloaded'),(302,'provider_unavailable')])
def test_no_retries_and_no_error_leaks(status,code):
    seen=[]
    def handler(request):
        seen.append(request)
        return httpx.Response(status,json={'error':'SECRET upstream key raw payload'})
    result=run(handler)
    assert result['code']==code and len(seen)==1
    assert 'SECRET' not in json.dumps(result)

@pytest.mark.parametrize('changes,code',[
    ({'model':'claude-opus-5-5'},'model_mismatch'),
    ({'model':'SECRET raw text'},'model_mismatch'),
    ({'stop_reason':'refusal'},'refusal'),
    ({'stop_reason':'max_tokens'},'incomplete_response'),
    ({'content':[{'type':'text','text':'SECRET'}]},'invalid_response'),
    ({'content':[{'type':'text','text':json.dumps({**VERDICT,'unknown':'SECRET'})}]},'invalid_response'),
    ({'content':[{'type':'text','text':json.dumps({**VERDICT,'confidence':True})}]},'invalid_response'),
    ({'usage':{'input_tokens':True,'output_tokens':80}},'invalid_usage'),
    ({'content':[{'type':'text','text':'{"schema_version":1,"schema_version":1}'}]},'invalid_response'),
])
def test_validation_failure_no_fallback(changes,code):
    seen=[]
    def handler(request):
        seen.append(request)
        return httpx.Response(200,json={'id':p.MODEL} if request.method=='GET' else response(**changes))
    result=run(handler)
    assert result['code']==code and not result['verdict_validated'] and len(seen)==2
    assert 'SECRET' not in json.dumps(result)

def test_model_discovery_binding():
    seen=[]
    def handler(request):
        seen.append(request);return httpx.Response(200,json={'id':'claude-opus-5-5'})
    assert run(handler)['code']=='model_mismatch'
    assert len(seen)==1

def test_total_deadline():
    seen=[]
    async def handler(request):
        seen.append(request);await asyncio.sleep(.1)
        return httpx.Response(200,json={'id':p.MODEL})
    result=run(handler,deadline=.01)
    assert result['code']=='deadline_exceeded' and len(seen)==1 and result['elapsed_ms']<100

def test_bounded_upstream_response():
    def handler(request):
        return httpx.Response(200,headers={'content-type':'application/json'},content=b' '*65537)
    assert run(handler)['code']=='invalid_response'
