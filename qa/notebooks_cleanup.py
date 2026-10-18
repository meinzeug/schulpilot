"""Export and erase exactly the successfully exercised artificial album family."""

import hashlib
import io
import json
import re
import zipfile
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / "artifacts/.school-day-qa-account.json"
BASE = 'https://schulpilot.dorfspy.de/api'


def require(value):
    if not value:
        raise RuntimeError("Owned notebook export/erasure failed; checkpoint retained")


def main():
    account = json.loads(PRIVATE.read_text())
    require(account.get("normal_account") and account.get("verified") and
            account.get("notebook_qa", {}).get("phase") in ('native_passed', 'web_passed_native_pending') and
            re.search(r"\+schulpilot-normal-qa-[a-f0-9]{12}@", account["credentials"]["parent_username"]))
    expected = hashlib.sha256(account['child_id'].encode()).hexdigest()
    for name in ('web', 'native'):
        evidence = json.loads((ROOT/f'artifacts/notebooks-{name}-result.json').read_text())
        require(evidence.get('success') and evidence.get('dataset_key') == expected)
    headers = {'X-Schulpilot-Request': '1', 'X-Client-Platform': 'native'}
    with httpx.Client(base_url=BASE, headers=headers, timeout=60) as parent, httpx.Client(base_url=BASE, headers=headers, timeout=30) as child:
        for role, client in (('parent', parent), ('child', child)):
            signed = client.post('/auth/login', json={'username': account['credentials'][role + '_username'],
                                                       'password': account['credentials'][role + '_password']}).raise_for_status().json()
            require(signed['user']['id'] == account['user']['id'] if role == 'parent' else signed['user']['child_id'] == account['child_id'])
            client.headers['Authorization'] = 'Bearer ' + signed['token']
        family_id = account['user']['families'][0]['id']
        exported = parent.get(f'/families/{family_id}/export').raise_for_status()
        with zipfile.ZipFile(io.BytesIO(exported.content)) as archive:
            data = json.loads(archive.read('family.json'))
        own = data['children'][0]
        require(own['child']['id'] == account['child_id'] and len(own['materials']) == 26)
        require(not own['attempts'] and not own['school_grades'] and len(data['usage']) == 2)
        for row in own['materials']:
            require(parent.get('/materials/' + row['id'] + '/image').status_code == 200)
        old_photo = own['materials'][0]['id']
        require(parent.request('DELETE', '/account', json={'password': account['credentials']['parent_password']}).status_code == 200)
        require(parent.get('/children/' + account['child_id'] + '/subjects').status_code == 401)
        require(child.get('/materials/' + old_photo + '/image').status_code == 401)
        PRIVATE.unlink()
        result = {'success': True, 'exported_materials': 26, 'actual_ocr_usage_rows': 2, 'invented_attempts': 0,
                  'all_owned_private_photos_readable_before_delete': True, 'own_family_deleted': True,
                  'old_sessions_rejected': True, 'private_credentials_removed': True}
        (ROOT/'artifacts/notebooks-erasure-result.json').write_text(json.dumps(result)+'\n')
        print(json.dumps(result))


if __name__ == '__main__':
    main()
