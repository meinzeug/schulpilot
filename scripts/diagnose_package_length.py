"""One explicitly requested paid package probe using ONLY this fixed artificial text.

Isolated SQLite ledger and actual provider adapter; no production records. The
raw synthetic response stays in a mode-0600 file for output-length diagnosis.
Each run uses a fresh local ledger and makes exactly one reserved model call.
"""
import argparse
import json
import os
import sys
import time
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES = {
    'biology': ('Biologie', 'Fotosynthese',
        "Pflanzen und Photosynthese\n\nPflanzen nehmen Wasser und Kohlenstoffdioxid auf.\n"
        "Mit Licht bilden sie Zucker und geben Sauerstoff ab.\n\n\\(\\mathrm{CO}_{2}\\)\n\\(\\mathrm{O}_{2}\\)"),
    'mathematics': ('Mathematik', 'Bruchteile',
        'Ein Bruch 1/2 beschreibt 1 von 2 gleich großen Teilen.\n'
        'Ein Bruch 2/3 beschreibt 2 von 3 gleich großen Teilen.'),
    'german': ('Deutsch', 'Wortbausteine',
        'Vorsilbe (Präfix) | + | Wortstamm | + | Nachsilbe (Suffix)'),
    'history': ('Geschichte', 'Handel in einer erfundenen Hafenstadt',
        'Eine erfundene Hafenstadt zeigt einen Handelsweg: Marktplatz → Hafen.\n'
        'Die Waren gelangen vom Marktplatz zum Hafen. Der Hafen liegt am Meer.\n'
        'Am Hafen werden Waren auf Schiffe geladen.'),
    'history_list': ('Geschichte', 'Alltag in einer erfundenen Hafenstadt',
        'Öffentliche künstliche Notizen\n'
        '• Im Dorf lebten mehrere Familien.\n'
        '• Die Menschen stellten Schalen aus Ton her.\n'
        '• Auf dem Markt wurden Waren getauscht.'),
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, required=True, help='New private local directory')
    parser.add_argument('--case', choices=tuple(CASES), default='biology')
    parser.add_argument('--study', action='store_true', help='Run the fixed artificial history study-stage probe')
    parser.add_argument('--schema-probe', action='store_true', help='Test one fixed artificial schema-boundary request')
    parser.add_argument('--key-file', type=Path, default=Path.home() / 'or.txt')
    args = parser.parse_args()
    if args.study and args.case not in ('history', 'history_list'):
        parser.error('--study is available only for the fixed artificial history case')
    subject, topic, source = CASES[args.case]
    directory = args.directory.resolve()
    directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    from cryptography.fernet import Fernet

    os.environ.update(DATABASE_URL='sqlite:///' + str(directory / 'probe.sqlite'),
        DATA_DIR=str(directory / 'data'), MASTER_KEY=Fernet.generate_key().decode(), ENVIRONMENT='test',
        OPENROUTER_API_KEY=args.key_file.read_text().strip(), SYNTHETIC_AI_ENABLED='true',
        SYNTHETIC_PAID_PROBE='true', SYNTHETIC_TEST_BUDGET_MICROS='5000000')
    sys.path[:0] = [str(ROOT / 'backend')]
    import httpx
    from schulpilot import fixtures, visual_references
    from schulpilot.db import DB, Child, Family, Installation, Job, ProviderConfig, Usage, User, init_db, now, uid
    from schulpilot.model_routing import RoutingPolicy, select_route
    from schulpilot.providers import ProviderError, Result, request_provider, reserve, settle
    from schulpilot.security import password_hash
    from sqlalchemy import select

    init_db()
    routes = {}
    with httpx.Client(timeout=30, follow_redirects=False) as client:
        eligible = client.get('https://openrouter.ai/api/v1/endpoints/zdr',
            headers={'Authorization': 'Bearer ' + os.environ['OPENROUTER_API_KEY']})
        eligible.raise_for_status()
        zdr = {(e['model_id'], e['tag']) for e in eligible.json()['data']}
        for tier, model, upstream in [('luna', 'openai/gpt-6-luna', 'azure'),
                                      ('sol', 'openai/gpt-6.1-sol', 'azure/eu')]:
            response = client.get('https://openrouter.ai/api/v1/models/' + model + '/endpoints')
            response.raise_for_status()
            data = response.json()['data']
            endpoint = next(e for e in data['endpoints'] if e['tag'] == upstream and e['status'] == 0
                            and (model, upstream) in zdr)
            if not {'reasoning', 'response_format', 'structured_outputs'} <= set(endpoint['supported_parameters']):
                raise RuntimeError('The fixed upstream lacks a required parameter')
            rates = [int((Decimal(endpoint['pricing'][k]) * 10**12).to_integral_value())
                     for k in ('prompt', 'completion')]
            routes[tier] = {'model': model, 'upstreams': [upstream],
                'input_per_million_micros': rates[0], 'output_per_million_micros': rates[1],
                'max_output_tokens': 8000 if tier == 'sol' else 4000, 'reserve_micros': 1000000,
                'image_capable': 'image' in data['architecture']['input_modalities'],
                'capability_evidence': 'Verified endpoint metadata for isolated artificial package probe',
                'pricing_evidence': 'https://openrouter.ai/api/v1/models/' + model + '/endpoints',
                'verified_at': int(now()), 'evaluated': False, 'under13_approved': False}
    policy = RoutingPolicy(version=1, enabled=True, revision='fixed-biology-package-diagnostic-1', routes=routes,
        budget={'eur_per_usd': '1.00', 'fx_evidence': 'Synthetic test bound; not a real exchange rate',
                'fx_checked_at': int(now()), 'fee_reserve_bps': 800}).model_dump()
    with DB.begin() as db:
        db.get(Installation, 1).completed = True
        family = Family(name='Artificial package diagnostic', synthetic=True, call_limit=2, budget_micros=5000000)
        user = User(username='artificial-probe', display_name='Artificial probe', role='child',
                    verified=True, password_hash=password_hash(os.urandom(24).hex()))
        db.add_all([family, user])
        db.flush()
        child = Child(family_id=family.id, user_id=user.id, grade=6, subjects=[subject], preferences={})
        db.add(child)
        db.flush()
        references = visual_references.candidates(db, subject, topic + ' ' + source, package_prepared=True)
        payload = {'package_partition': 1, 'package_plan_digest': 'a' * 64,
            'grade': 6, 'preferences': {'session_minutes': 10},
            'selected_groups': [{'id': 'g1', 'subject': subject, 'estimated_minutes': 8}],
            'materials': [{'subject': subject, 'group_id': 'g1', 'topic': topic, 'content': source}],
            'visual_context': {'required': True, 'references': references,
                'sources': [{'ref': 'p1', 'material_id': 'b' * 32, 'revision': 1,
                    'source_refs': [{'block_id': 'c' * 32}], 'subject': subject,
                    'group_id': 'g1', 'topic': topic, 'content': source}]}}
        function = 'unit' if args.study else 'package'
        if args.study:
            payload = {'grade': 6, 'required_subject': subject, 'required_topic': topic,
                'material': {'subject': subject, 'topic': topic, 'content': source, 'uncertainties': []},
                'study_block': {'mode': 'understand', 'question_count': 2,
                    'tasks': [{'number': 1, 'action': 'Beschreibe den belegten Weg.', 'source_excerpt': source},
                              {'number': 2, 'action': 'Erkläre eine belegte Station.', 'source_excerpt': source}]},
                'previous_prompts': [],
                'visual_context': {'required': True, 'references': references,
                    'sources': [{'ref': 'p1', 'material_id': 'b' * 32, 'revision': 1,
                        'source_refs': [{'block_id': 'c' * 32}], 'subject': subject,
                        'group_id': None, 'topic': topic, 'content': source}]}}
        config = db.get(ProviderConfig, 1)
        config.provider, config.model, config.routing_policy = 'openrouter', routes['sol']['model'], policy
        config.emergency_stop, config.production_block_reason = False, 'Artificial probe only'
        config.reserve_micros, config.max_output_tokens = 1000000, 8000
        config.global_limit_micros = 5000000
        config.revision += 1
        job = Job(id=uid(), child_id=child.id, kind=function, payload={}, status='running',
                  idempotency='fixed-artificial-package-' + args.case)
        db.add(job)
        db.flush()
        usage = reserve(db, family, child.id, job.id, function, synthetic_fixture=True, probe_tier='sol')
        routed = select_route(config, function, snapshot=usage.route_snapshot)
        job_id = job.id
    # This process replaces only the trusted server fixture with the fixed
    # artificial payload above. Caller-controlled production data are rejected.
    def fixed(request_function, fixture_id):
        expected = fixtures.FIXTURE_ID if args.study else fixtures.PACKAGE_FIXTURE_ID
        if request_function != function or fixture_id != expected:
            raise ValueError('Only the fixed artificial package is allowed')
        return payload
    fixtures.trusted_payload = fixed
    original_post = httpx.Client.post
    def capture(client, url, *args, **kwargs):
        response = original_post(client, url, *args, **kwargs)
        if url in ('https://openrouter.ai/api/v1/chat/completions', 'https://eu.openrouter.ai/api/v1/chat/completions') and response.status_code == 200:
            target = directory / 'synthetic-response.json'
            target.write_text(response.text, encoding='utf-8')
            target.chmod(0o600)
        return response
    httpx.Client.post = capture
    started = time.monotonic()
    result, error = None, None
    try:
        if args.schema_probe:
            from schulpilot.ai_accounting import response_metrics
            from schulpilot.model_routing import selection

            route = selection(routed)
            host = {'standard': 'openrouter.ai', 'eu': 'eu.openrouter.ai', 'us': 'us.openrouter.ai'}[route['region']]
            body = {'model': routed.model, 'max_tokens': 2000,
                'messages': [{'role': 'system', 'content': 'Dies ist ein künstlicher Schema-Test. Gib fünf verschiedene lange Tiernamen aus.'},
                             {'role': 'user', 'content': 'Gib fünf verschiedene lange Tiernamen als Liste aus.'}],
                'provider': {'only': route['route']['upstreams'], 'allow_fallbacks': False,
                             'require_parameters': True, 'data_collection': 'deny', 'zdr': True,
                             'max_price': {'prompt': routed.input_per_million_micros / 1_000_000,
                                           'completion': routed.output_per_million_micros / 1_000_000, 'request': 0}},
                'reasoning': {'effort': 'medium', 'exclude': True}, 'store': False,
                'response_format': {'type': 'json_schema', 'json_schema': {'name': 'bounded_test', 'strict': True,
                    'schema': {'type': 'object', 'properties': {'items': {'type': 'array', 'minItems': 1, 'maxItems': 1,
                        'items': {'type': 'string', 'maxLength': 4}}}, 'required': ['items'], 'additionalProperties': False}}}}
            with httpx.Client(timeout=155, follow_redirects=False) as client:
                response = client.post('https://' + host + '/api/v1/chat/completions',
                    headers={'Authorization': 'Bearer ' + os.environ['OPENROUTER_API_KEY']}, json=body)
            if response.status_code != 200:
                error = 'Synthetic schema probe HTTP ' + str(response.status_code)
                result = Result({}, cost_source='unknown')
            else:
                raw = response.json()
                result = Result({}, **response_metrics(raw, (time.monotonic() - started) * 1000,
                    response.headers.get('x-request-id')))
                choice = (raw.get('choices') or [{}])[0]
                try:
                    values = json.loads(choice['message']['content'])['items']
                    result.data = {'finish': choice.get('finish_reason'), 'items': len(values),
                                   'string_lengths': [len(value) for value in values]}
                except (ValueError, KeyError, TypeError):
                    error = 'Synthetic schema response incomplete'
        else:
            result = request_provider(routed, function, {}, synthetic_fixture=True, private_probe=True)
    except ProviderError as exc:
        result, error = exc.billing_result, str(exc)
    with DB.begin() as db:
        usage = db.scalar(select(Usage).where(Usage.job_id == job_id))
        settle(db, usage, result, failed=bool(error))
        report = {'synthetic_only': True, 'case': args.case, 'status': 'failed' if error else 'completed', 'error': error,
            'elapsed_seconds': round(time.monotonic() - started, 2), 'cost_micros_usd': usage.cost_micros,
            'input_tokens': usage.input_tokens, 'output_tokens': usage.output_tokens, 'telemetry': usage.telemetry,
            **({'schema_probe': result.data} if args.schema_probe and result and result.data else {})}
        db.get(Job, job_id).status = report['status']
    (directory / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    (directory / 'report.json').chmod(0o600)
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
