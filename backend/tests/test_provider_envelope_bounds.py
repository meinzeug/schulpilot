"""Fictional encrypted metadata; no model call and no hidden reasoning text."""
import httpx
import pytest
from schulpilot import providers
from test_presentation_capability_paths import SCENE, _config, _scene_unit, _transport


@pytest.mark.parametrize('field',['reasoning','reasoning_details'])
def test_bounded_reasoning_metadata_does_not_reject_small_valid_learning_output(monkeypatch,field):
    value=_scene_unit()
    calls=_transport(monkeypatch,'openrouter',value)
    original=providers.httpx.Client
    class Client(original):
        def post(self,url,**kwargs):
            response=super().post(url,**kwargs)
            raw=response.json()
            raw['usage']['cost']=0.001
            raw['choices'][0]['message'][field]=('SYNTHETIC-METADATA-'*35000 if field=='reasoning'
                else [{'type':'reasoning.encrypted','format':'openai-responses-v1','data':'x'*650000}])
            return httpx.Response(200,json=raw)
    monkeypatch.setattr(providers.httpx,'Client',Client)
    result=providers.request_provider(_config('openrouter'),'unit',{'material':{
        'subject':value['subject'],'topic':value['topic'],'content':SCENE['source']}})
    assert len(calls)==1 and result.data['questions']
    assert 'reasoning_details' not in result.data and 'SYNTHETIC-METADATA' not in str(result.telemetry)
    assert calls[0]['reasoning']=={'effort':'medium','exclude':True}


@pytest.mark.parametrize('fault',['visible_content','unrelated_metadata','entire_envelope'])
def test_larger_learning_text_and_unbounded_envelopes_still_fail_once(monkeypatch,fault):
    value=_scene_unit()
    calls=_transport(monkeypatch,'openrouter',value)
    original=providers.httpx.Client
    class Client(original):
        def post(self,url,**kwargs):
            response=super().post(url,**kwargs)
            raw=response.json()
            raw['usage']['cost']=0.001
            if fault=='visible_content':
                raw['choices'][0]['message']['content']='x'*600000
            elif fault=='unrelated_metadata':
                raw['extra']='x'*600000
            else:
                raw['choices'][0]['message']['reasoning_details']=[{'type':'reasoning.encrypted','data':'x'*4000001}]
            return httpx.Response(200,json=raw)
    monkeypatch.setattr(providers.httpx,'Client',Client)
    with pytest.raises(providers.ProviderError) as error:
        providers.request_provider(_config('openrouter'),'unit',{'material':{
            'subject':value['subject'],'topic':value['topic'],'content':SCENE['source']}})
    assert len(calls)==1
    if fault!='entire_envelope':
        assert error.value.billing_result is not None
        assert error.value.billing_result.cost_micros is not None
    assert 'xxxx' not in str(error.value)
