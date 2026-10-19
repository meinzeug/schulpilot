"""Public HTTPS: fixed artificial source, draft/resume and passive parent reads.

No submitted answer, provider call, real family or private content in output.
Uses only the protected account created by prepare_design_review.py.
"""

import json
import os
import time
from pathlib import Path

import httpx

PRIVATE = Path(__file__).resolve().parents[1] / 'artifacts/.design-qa-account.json'
HEADERS = {'X-Schulpilot-Request': '1', 'X-Client-Platform': 'native'}


def checked(response, status=200):
    if response.status_code != status:
        raise RuntimeError('Own artificial check HTTP ' + str(response.status_code))
    return response.json()


def save(data):
    fd = os.open(PRIVATE, os.O_WRONLY | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as file:
        json.dump(data, file)


def main():
    data = json.loads(PRIVATE.read_text())
    credentials = data['credentials']
    with httpx.Client(base_url='https://schulpilot.dorfspy.de/api', headers=HEADERS, timeout=30) as parent, httpx.Client(
            base_url='https://schulpilot.dorfspy.de/api', headers=HEADERS, timeout=30) as child:
        for api, role in [(parent, 'parent'), (child, 'child')]:
            login = checked(api.post('/auth/login', json={'username': credentials[role + '_username'],
                'password': credentials[role + '_password']}))
            assert login['user']['role'] == role
            assert (all(f['synthetic'] for f in login['user']['families']) if role == 'parent' else login['user']['synthetic'])
            api.headers['Authorization'] = 'Bearer ' + login['token']
        try:
            if not data.get('adaptive_resume_job_id'):
                material = checked(parent.get('/materials/' + data['material_id']))
                assert material['synthetic'] and not material['fixture_id'] and material['confirmed']
                job = checked(parent.post('/children/' + data['child_id'] + '/units',
                    headers={'Idempotency-Key': 'adaptive-fixed-recovery-v1'}, json={'material_id': material['id']}), 202)
                data['adaptive_resume_job_id'] = job['id']
                save(data)
            for _ in range(60):
                job = checked(parent.get('/jobs/' + data['adaptive_resume_job_id']))
                if job['status'] == 'failed':
                    raise RuntimeError('Fixed artificial job failed; no automatic retry')
                if job['status'] == 'completed':
                    break
                time.sleep(.4)
            assert job['status'] == 'completed'
            unit_id = job['result']['unit_id']
            path = '/units/' + unit_id
            unit = checked(child.get(path))
            assert unit['synthetic'] and unit['provider'] == 'synthetic' and not any(q['attempts'] for q in unit['questions'])
            assert unit['questions'][0]['type'] == 'choice'
            expected_draft = unit['questions'][0]['options'][0]
            if not data.get('adaptive_resume_done'):
                unit = checked(child.post(path + '/start'))
                if unit['learning_session']['action']['kind'] == 'check_prior':
                    unit = checked(child.post(path + '/learning-session/action', json={'request_key': 'adaptive-prior-smoke-001',
                        'kind': 'check_prior', 'revision': unit['learning_session']['revision']}))
                body = {'request_key': 'adaptive-draft-smoke-001', 'revision': unit['learning_session']['draft_revision'],
                    'question_id': unit['questions'][0]['id'], 'answer': expected_draft, 'input_method': 'typed'}
                saved = checked(child.put(path + '/learning-session/draft', json=body))
                duplicate = checked(child.put(path + '/learning-session/draft', json=body))
                assert saved['revision'] == duplicate['revision']
                checked(child.post(path + '/pause'))
                data['adaptive_resume_done'] = True
                save(data)
            before = checked(child.get(path))
            # Older checkpoints used an unrenderable arbitrary choice draft.
            # Correct only this own unsubmitted synthetic draft, never an Attempt.
            if before['learning_session']['working_memory']['draft']['answer'] != expected_draft:
                checked(child.put(path + '/learning-session/draft', json={'request_key': 'adaptive-valid-choice-001',
                    'revision': before['learning_session']['draft_revision'], 'question_id': before['questions'][0]['id'],
                    'answer': expected_draft, 'input_method': 'typed'}))
                before = checked(child.get(path))
            assert before['status'] == 'paused' and before['learning_session']['working_memory']['draft']['answer'] == expected_draft
            events = checked(parent.get('/children/' + data['child_id'] + '/activity'))
            for _ in range(3):
                view = checked(parent.get(path))
                assert 'draft' not in view['learning_session']['working_memory']
                checked(parent.get('/children/' + data['child_id'] + '/overview?compact=true'))
            after = checked(child.get(path))
            assert after['learning_session']['revision'] == before['learning_session']['revision']
            assert after['active_seconds_approx'] == before['active_seconds_approx']
            assert not any(q['attempts'] for q in after['questions'])
            assert checked(parent.get('/children/' + data['child_id'] + '/activity')) == events
            print(json.dumps({'public_https': True, 'synthetic_only': True, 'draft_retained_after_pause': True,
                'duplicate_save_idempotent': True, 'parent_cannot_read_unsubmitted_draft': True,
                'passive_parent_reads_change_neither_time_nor_answers': True, 'external_ai_calls': 0}))
        finally:
            for api in (parent, child):
                api.post('/auth/logout')


if __name__ == '__main__':
    main()
