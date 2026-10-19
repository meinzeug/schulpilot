"""Produce a content/credential-free report from the isolated artificial ledger."""

import json
import sqlite3
from decimal import Decimal
from pathlib import Path


def main():
    folder = Path.home() / '.local/share/schulpilot-evaluation'
    db = sqlite3.connect('file:' + str(folder / 'evaluation.sqlite') + '?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    if db.execute('SELECT count(*) FROM families WHERE synthetic=0').fetchone()[0]:
        raise SystemExit('Only an entirely artificial ledger is permitted')
    rows = [dict(r) for r in db.execute('SELECT model, function, status, cost_micros, reserved_micros, input_tokens, output_tokens, telemetry FROM usage')]
    models = {}
    for row in rows:
        item = models.setdefault(row['model'], {'reserved_requests': 0, 'known_billed_requests': 0, 'billed_micros_usd': 0,
            'unknown_cost_requests': 0, 'input_tokens': 0, 'completion_tokens_including_reasoning': 0, 'reasoning_tokens_subset': 0,
            'cached_tokens': 0, 'latencies_ms': []})
        item['reserved_requests'] += 1
        item['known_billed_requests'] += row['cost_micros'] is not None
        item['unknown_cost_requests'] += row['cost_micros'] is None
        item['billed_micros_usd'] += row['cost_micros'] or 0
        item['input_tokens'] += row['input_tokens'] or 0
        item['completion_tokens_including_reasoning'] += row['output_tokens'] or 0
        details = json.loads(row['telemetry'])
        item['reasoning_tokens_subset'] += details.get('reasoning_tokens') or 0
        item['cached_tokens'] += details.get('cached_tokens') or 0
        if details.get('latency_ms') is not None:
            item['latencies_ms'].append(details['latency_ms'])
    for item in models.values():
        values = sorted(item.pop('latencies_ms'))
        item['p50_ms'] = values[(len(values) - 1) // 2] if values else None
        item['p95_ms'] = values[(len(values) * 95 + 99) // 100 - 1] if values else None
    # Exact, labelled token/fee assumptions; not a measured invoice or FX quote.
    per_call = Decimal('.70') * Decimal('.00115') + Decimal('.28') * Decimal('.023') + Decimal('.02') * Decimal('.115')
    scenarios = []
    for name, calls in [('normal_24_days_20_calls', 480), ('exam_14_normal_10_intensive_days', 680), ('intensive_24_days_40_calls', 960)]:
        inference = per_call * calls
        scenarios.append({'name': name, 'calls_all_subjects_and_background_total': calls,
            'inference_usd': str(inference), 'with_standard_fee_5_5_percent_usd': str(inference * Decimal('1.055')),
            'with_business_fee_8_percent_usd': str(inference * Decimal('1.08'))})
    data = {'date': '2026-10-19', 'synthetic_only': True, 'budget_cap_usd': '0.25', 'models': models,
        'billed_inference_micros_usd': sum(r['cost_micros'] or 0 for r in rows),
        'held_micros_usd_including_unknown': sum(r['cost_micros'] if r['cost_micros'] is not None else r['reserved_micros'] for r in rows),
        'actual_purchase_fees': None, 'actual_eur_cost': None,
        'scenarios_are_hypotheses': True, 'scenario_tokens_per_call': {'input': 4000, 'completion_including_reasoning': 1500},
        'scenario_mix': {'luna': '.70', 'sol': '.28', 'astra': '.02'}, 'scenarios': scenarios,
        'limits': ['No human learning-effectiveness trial', 'No Astra inference tested', 'No complete five-subject end-to-end model comparison',
            'One upstream error with unknown cost; one historical pre-dispatch hold conservatively retained',
            'Images are represented in reported OCR usage, not an invented extra flat image fee',
            'No prompt-cache saving measured; actual fees/FX and sustained traffic are unverified']}
    target = Path(__file__).resolve().parents[1] / 'docs/OPENROUTER_EVALUATION_2026_10_19.json'
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print(str(target))


if __name__ == '__main__':
    main()
