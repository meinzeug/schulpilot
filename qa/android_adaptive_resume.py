"""Observe a saved server choice through native Flutter pause/restart. No answer."""

import json
import re
import time

import android_smoke as native
import httpx
from android_design import login, require
from android_update import installed_code, launch, wait_until


def selected_choice(label):
    found = native.matching(label)
    if not found:
        # At 200% system text the options are below the question. Scroll only;
        # selecting a value here would invalidate the restoration observation.
        native.adb('shell', 'input', 'swipe', '900', '1700', '900', '1300', '500')
        return False
    return any(node.get('checked') == 'true' for node in found)


def main():
    checkpoint = json.loads((native.ARTIFACTS / '.design-qa-account.json').read_text())
    credentials = checkpoint['credentials']
    with httpx.Client(base_url=native.BASE, headers=native.HEADERS, timeout=30) as parent:
        response = parent.post('/auth/login', json={'username': credentials['parent_username'], 'password': credentials['parent_password']})
        require(response.status_code == 200, 'own_parent_login_failed')
        account = response.json()
        require(all(f['synthetic'] for f in account['user']['families']), 'own_artificial_family_required')
        parent.headers['Authorization'] = 'Bearer ' + account['token']
        try:
            job = parent.get('/jobs/' + checkpoint['adaptive_resume_job_id']).raise_for_status().json()
            unit_id = job['result']['unit_id']
            unit = parent.get('/units/' + unit_id).raise_for_status().json()
            require(unit['synthetic'] and unit['provider'] == 'synthetic', 'fixed_demo_only')
            require(not any(q['attempts'] for q in unit['questions']), 'unanswered_fixture_required')
            expected = re.sub(r'(\d+)\s*/\s*(\d+)', r'\1 durch \2', unit['questions'][0]['options'][0])
            version = json.loads((native.ARTIFACTS / 'android-release.json').read_text())['version_code']
            require(installed_code() == version, 'current_signed_build_required')
            native.adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
            time.sleep(2)
            launch()
            entry, _ = native.wait_any(('Willkommen zurück', 'Lernrunde verlassen', 'Heute'))
            if entry == 'Lernrunde verlassen':
                if native.matching('Pause'):
                    native.press('Pause', scroll=True)
                native.press('Lernrunde verlassen')
                if native.matching('Jetzt eine Pause machen?'):
                    native.press('Pause machen')
                native.wait('Heute')
                entry = 'Heute'
            if entry == 'Heute':
                native.press('Konto')
                native.wait(credentials['child_username'])
                native.press('Abmelden', scroll=True)
            native.wait('Willkommen zurück')
            login(credentials, 'child')
            for iteration in range(2):
                overview = parent.get('/children/' + checkpoint['child_id'] + '/overview?compact=true').raise_for_status().json()
                first = overview['plan']['today'][0]
                require(first['kind'] == 'unit' and first['id'] == unit_id, 'own_paused_unit_must_be_next')
                action, _ = native.wait_any(('Lernrunde verlassen', 'Weiterlernen', 'Freiwillig weiterlernen', 'Jetzt lernen'))
                if action != 'Lernrunde verlassen':
                    native.press(action, scroll=True)
                entry, _ = native.wait_any(('Lernen fortsetzen', 'Antwort prüfen'))
                if entry == 'Lernen fortsetzen':
                    native.press('Lernen fortsetzen', scroll=True)
                native.wait('Antwort prüfen')
                # Secure-storage restoration completes after the first frame.
                # Observe the stable selected control, not just its first paint.
                wait_until(lambda: selected_choice(expected), seconds=35)
                print(json.dumps({'checkpoint': 'saved_choice_visible', 'iteration': iteration,
                    'system_text_scale': 1 if iteration == 0 else 2}), flush=True)
                native.screenshot('adaptive-native-restored-choice-' + str(iteration) + '.png')
                native.press('Pause', scroll=True)
                native.wait('Lernen fortsetzen')
                print(json.dumps({'checkpoint': 'round_paused', 'iteration': iteration}), flush=True)
                if iteration == 0:
                    native.adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
                    time.sleep(2)  # Wait for Android's configuration relaunch.
                    native.adb('shell', 'am', 'force-stop', native.PACKAGE)
                    time.sleep(1)
                    launch()
                    native.wait_any(('Heute', 'Lernrunde verlassen'))
            after = parent.get('/units/' + unit_id).raise_for_status().json()
            require(not any(q['attempts'] for q in after['questions']), 'draft_must_not_be_an_answer')
            native.press('Lernrunde verlassen', scroll=True)
            if native.matching('Jetzt eine Pause machen?'):
                native.press('Pause machen')
            native.wait('Heute')
            native.adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
            time.sleep(2)
            native.press('Konto')
            native.press('Abmelden', scroll=True)
            native.wait('Willkommen zurück')
            report = {'installed_code': version, 'native_flutter': True, 'synthetic_only': True,
                'saved_choice_retained_through_pause_and_restart': True, 'system_font_scale_200': True,
                'submitted_answers': 0, 'external_ai_calls': 0}
            target = native.ARTIFACTS / 'adaptive-android-resume-result.json'
            target.write_text(json.dumps(report) + '\n')
            target.chmod(0o600)
            print(json.dumps(report))
        finally:
            native.adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
            parent.post('/auth/logout')


if __name__ == '__main__':
    main()
