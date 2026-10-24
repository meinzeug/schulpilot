"""Own artificial images, no provider or cost-limit changes."""
import io

import pytest
from PIL import Image
from pydantic import ValidationError
from schulpilot.db import ProviderConfig
from schulpilot.model_routing import VisionBudget
from schulpilot.provider_cost_preflight import projection


def image(size=(1600, 1200), quality=95):
    data = io.BytesIO()
    Image.new('RGB', size, 'white').save(data, 'JPEG', quality=quality)
    return data.getvalue()


def configured(profile=True):
    config = ProviderConfig(provider='openrouter', model='openai/gpt-6.1-sol', max_output_tokens=4000,
        input_per_million_micros=2_000_000, output_per_million_micros=10_000_000,
        reserve_micros=150_000, routing_policy={})
    budget = VisionBudget(basis='operator_estimate', model=config.model,
        upstreams=['azure'], image_tokens=30_000, max_side=3200,
        max_pixels=16_000_000, evidence='Synthetic operator risk allowance; no provider guarantee.', approved_at=1)
    config._selected_route = {'route': {'upstreams': ['azure'], 'vision_budget': budget.model_dump() if profile else None}}
    return config


def test_approved_image_allowance_is_independent_of_jpeg_transport_bytes():
    cfg = configured()
    first = projection(cfg, 'extract', 12_000, image(), 900_000)
    second = projection(cfg, 'extract', 12_000, image(quality=75), 150_000)
    assert first == second
    assert first['projected_micros'] == 132_192 < first['reserved_micros']
    assert first['guaranteed_invoice_ceiling'] is False
    assert first['basis'] == 'operator_image_estimate' and len(first['profile_sha256']) == 64


@pytest.mark.parametrize('case', ['absent', 'too_wide', 'too_many_pixels', 'corrupt', 'other_function', 'other_provider',
    'other_model', 'other_upstream'])
def test_no_implicit_allowance_for_unapproved_requests(case):
    cfg = configured(profile=case != 'absent')
    data, function = image(), 'extract'
    if case == 'too_wide':
        data = image((3201, 900))
    elif case == 'too_many_pixels':
        cfg._selected_route['route']['vision_budget']['max_pixels'] = 1_000_000
    elif case == 'corrupt':
        data = b'not a picture'
    elif case == 'other_function':
        function = 'tutor'
    elif case == 'other_provider':
        cfg.provider = 'openai'
    elif case == 'other_model':
        cfg.model = 'openai/other-model'
    elif case == 'other_upstream':
        cfg._selected_route['route']['upstreams'] = ['other']
    value = projection(cfg, function, 12_000, data, 900_000)
    assert value['basis'] == 'encoded_bytes' and value['profile_sha256'] is None
    assert value['projected_micros'] > cfg.reserve_micros


def test_operator_estimate_does_not_bypass_text_output_or_reservation_guard():
    cfg = configured()
    assert projection(cfg, 'extract', 30_000, image(), 900_000)['projected_micros'] > cfg.reserve_micros
    cfg.max_output_tokens = 8000
    assert projection(cfg, 'extract', 12_000, image(), 900_000)['projected_micros'] > cfg.reserve_micros
    value = projection(cfg, 'unit', 12_000, None, 0)
    assert value['basis'] == 'text_bytes' and value['image_input_allowance'] == 0


@pytest.mark.parametrize('change', [{'basis':'provider_guaranteed'}, {'image_tokens':True},
    {'image_tokens':0}, {'max_side':3201}, {'approved_at':False}, {'surprise':1}])
def test_profile_is_explicit_strict_and_versioned(change):
    value = configured()._selected_route['route']['vision_budget']
    with pytest.raises(ValidationError):
        VisionBudget.model_validate({**value, **change})


@pytest.mark.parametrize('change', [{'model':'openai/another-model'}, {'upstreams':['another-upstream']},
    {'evaluated':False}, {'image_capable':False}])
def test_allowance_cannot_survive_route_model_or_upstream_change(change):
    from schulpilot.model_routing import ModelRoute
    from test_model_routing import policy

    route = policy()['routes']['sol']
    profile = configured()._selected_route['route']['vision_budget']
    route = {**route, 'model':profile['model'], 'upstreams':profile['upstreams'],
             'image_capable':True, 'evaluated':True, 'vision_budget':profile}
    assert ModelRoute.model_validate(route).vision_budget.model == profile['model']
    with pytest.raises(ValidationError):
        ModelRoute.model_validate({**route, **change})
