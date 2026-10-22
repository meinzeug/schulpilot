"""Synthetic parent collection workflows; reads never become learning work."""
import csv
import io
from datetime import timedelta

import pytest
from conftest import create_child, register
from schulpilot.db import DB, Activity, Assignment, Attempt, Child, Job, LearningUnit, SchoolGrade, Usage
from schulpilot.learning import local_day
from sqlalchemy import func, select


def snapshot():
    with DB() as db:
        return tuple(db.scalar(select(func.count()).select_from(model))
                     for model in (Activity, Assignment, Attempt, Job, LearningUnit, SchoolGrade, Usage))


def seed(household):
    _, child = household
    with DB.begin() as db:
        today = local_day(db.get(Child, child['id']))
        goals = [Assignment(child_id=child['id'], subject='Mathematik', topic='Gleiches Thema', kind='parent',
            mandatory=False, created=i + 100) for i in range(25)]
        goals.extend([
            Assignment(child_id=child['id'], subject='Biologie', topic='Gleiches Thema', kind='exam',
                due=(today + timedelta(days=1)).isoformat(), scheduled_for=(today + timedelta(days=1)).isoformat(), created=1),
            Assignment(child_id=child['id'], subject='Physik', topic='Gleiches Thema', kind='homework',
                done=True, due=(today - timedelta(days=1)).isoformat(), created=2),
            Assignment(child_id=child['id'], subject='Englisch', topic='Runde existiert', kind='parent',
                due=(today - timedelta(days=2)).isoformat(), created=3),
        ])
        db.add_all(goals)
        db.flush()
        db.add(LearningUnit(child_id=child['id'], assignment_id=goals[-1].id, goal_revision=1,
            subject='Englisch', topic='Runde existiert', explanation='Synthetisch', questions=[], status='paused', provider='synthetic', synthetic=True))
        rows = [SchoolGrade(child_id=child['id'], subject='Mathematik', topic='Datiert', kind='test',
            value=i + 1, scale='grade_1_6', weight=i + 1, assessed_on=(today - timedelta(days=i)).isoformat(), created=i)
                for i in range(3)]
        rows.extend([
            SchoolGrade(child_id=child['id'], subject='Englisch', topic=' =SUM(A1)', note='\t=1+1', kind='oral',
                value=12, scale='points_0_15', weight=1, school_year_start=2025, semester=2, created=1),
            SchoolGrade(child_id=child['id'], subject='Mathematik', topic='Halbjahr', kind='test',
                value=6, scale='grade_1_6', weight=1, school_year_start=2026, semester=1, created=2),
        ])
        db.add_all(rows)
        db.flush()
        return child['id'], today, [g.id for g in goals], [r.id for r in rows]


@pytest.mark.parametrize('completion,expected', [('open', 27), ('done', 1), ('all', 28)])
def test_pk001_completed_goals_are_a_real_separate_collection(api, household, completion, expected):
    child, _, _, _ = seed(household)
    before = snapshot()
    value = api.get(f'/api/children/{child}/learning-plan', params={'completion': completion}).json()
    assert value['pagination']['total'] == expected
    assert all(a['done'] == (completion == 'done') for a in value['topics']) if completion != 'all' else True
    assert value['filters']['completion'] == completion
    assert snapshot() == before


def test_pk002_deadline_sort_keeps_undated_last_and_stable_pages(api, household):
    child, _, goals, _ = seed(household)
    path = f'/api/children/{child}/learning-plan'
    first = api.get(path, params={'order': 'due', 'completion': 'all'}).json()
    assert [a['id'] for a in first['topics'][:3]] == [goals[-1], goals[-2], goals[-3]]
    second = api.get(path, params={'order': 'due', 'completion': 'all', 'page': 2}).json()
    assert len({a['id'] for a in first['topics'] + second['topics']}) == 28
    assert api.get(path, params={'order': 'arbitrary'}).status_code == 422


def test_pk003_exact_old_goal_not_ambiguous_topic_or_wrong_completion(api, household):
    child, _, goals, _ = seed(household)
    path = f'/api/children/{child}/learning-plan'
    value = api.get(path, params={'assignment_id': goals[-2], 'completion': 'all'}).json()
    assert [a['id'] for a in value['topics']] == [goals[-2]]
    assert value['topics'][0]['done'] is True
    assert api.get(path, params={'assignment_id': 'missing'}).status_code == 404


@pytest.mark.parametrize('params,total', [({'rounds': 'open'}, 1), ({'rounds': 'none'}, 26),
    ({'rounds': 'finished'}, 0), ({'kind': 'exam'}, 1), ({'start': 'later'}, 1), ({'start': 'available'}, 26)])
def test_pk004_006_stored_round_kind_and_start_are_actual_filters(api, household, params, total):
    child, _, _, _ = seed(household)
    before = snapshot()
    value = api.get(f'/api/children/{child}/learning-plan', params=params)
    assert value.status_code == 200, value.text
    assert value.json()['pagination']['total'] == total
    assert snapshot() == before


def test_pk007_totals_are_whole_child_not_current_filtered_page(api, household):
    child, _, _, _ = seed(household)
    path = f'/api/children/{child}/learning-plan'
    expected = {'all': 28, 'open': 27, 'done': 1, 'overdue': 1}
    assert api.get(path).json()['assignment_totals'] == expected
    assert api.get(path, params={'q': 'no match'}).json()['assignment_totals'] == expected


def test_pk012_date_range_inclusive_and_unknown_dates_not_invented(api, household):
    child, today, _, grades = seed(household)
    path = f'/api/children/{child}/grades'
    before = snapshot()
    value = api.get(path, params={'start': (today-timedelta(days=1)).isoformat(), 'end': today.isoformat()}).json()
    assert {a['id'] for a in value['items']} == set(grades[:2])
    assert all(a['assessed_on'] is not None for a in value['items'])
    assert api.get(path, params={'start': today.isoformat(), 'end': (today-timedelta(days=1)).isoformat()}).status_code == 422
    assert api.get(path, params={'start': '2026-02-30'}).status_code == 422
    assert snapshot() == before


def test_pk013_semester_filter_uses_stored_school_evidence(api, household):
    child, _, _, grades = seed(household)
    response = api.get(f'/api/children/{child}/grades', params={'school_year': 2025, 'semester': 2})
    assert response.status_code == 200, response.text
    value = response.json()
    assert [a['id'] for a in value['items']] == [grades[-2]]
    assert value['items'][0]['assessed_on'] is None
    assert value['school_years'] == [2026, 2025]


@pytest.mark.parametrize('order,positions', [('oldest', [2, 1, 0]), ('newest', [0, 1, 2])])
def test_pk014_date_order_keeps_unknown_dates_after_dated_observations(api, household, order, positions):
    child, _, _, grades = seed(household)
    value = api.get(f'/api/children/{child}/grades', params={'order': order}).json()
    assert [a['id'] for a in value['items'][:3]] == [grades[i] for i in positions]
    assert all(a['assessed_on'] is None for a in value['items'][3:])


def test_pk015_filtered_csv_is_private_literal_and_does_not_create_work(api, household):
    child, _, _, _ = seed(household)
    before = snapshot()
    response = api.get(f'/api/children/{child}/grades-export.csv', params={'subject': 'Englisch'})
    assert response.status_code == 200
    assert 'no-store' in response.headers['cache-control']
    rows = list(csv.reader(io.StringIO(response.content.decode('utf-8-sig')), delimiter=';'))
    assert len(rows) == 2 and rows[1][0] == 'Englisch'
    assert rows[1][1] == "' =SUM(A1)" and rows[1][-1] == "'\t=1+1"
    assert rows[1][6] == '' and rows[1][7:9] == ['2025', '2']
    assert snapshot() == before
    assert api.get('/api/children/missing/grades-export.csv').status_code == 404


def test_pk018_stale_delete_preserves_changed_grade(api, household):
    child, _, _, grades = seed(household)
    path = f'/api/children/{child}/grades/{grades[0]}'
    with DB.begin() as db:
        row = db.get(SchoolGrade, grades[0])
        row.value = 5
        row.revision = 2
    assert api.delete(path, params={'revision': 1}).status_code == 409
    with DB() as db:
        assert db.get(SchoolGrade, grades[0]).value == 5
    assert api.delete(path, params={'revision': 2}).status_code == 200


def test_pk019_changed_grade_does_not_silently_create_goal(api, household):
    child, _, _, grades = seed(household)
    before = snapshot()
    response = api.post(f'/api/children/{child}/grades/{grades[0]}/goal', json={'revision': 9})
    assert response.status_code == 409
    assert snapshot() == before


def test_pk033_selection_summary_never_mixes_scales_or_claims_prognosis(api, household):
    child, _, _, _ = seed(household)
    value = api.get(f'/api/children/{child}/grades', params={'date_precision': 'day'}).json()
    assert value['selected_summary'] == [{'subject': 'Mathematik', 'scale': 'grade_1_6', 'count': 3,
        'weight_total': 6, 'average': 2.33}]
    assert api.get(f'/api/children/{child}/grades', params={'q': 'missing'}).json()['selected_summary'] == []


def test_parent_collections_cannot_select_another_familys_goal_or_export(api, household, mailbox):
    first_child, _, goals, _ = seed(household)
    user = register(api, mailbox, 'other-synthetic@example.org')
    other = create_child(api, user, 'other-synthetic-child')
    assert api.get(f'/api/children/{other["id"]}/learning-plan', params={'assignment_id': goals[0]}).status_code == 404
    assert api.get(f'/api/children/{first_child}/grades-export.csv').status_code == 404


def homework_seed(household):
    from schulpilot.db import Material, TutorTurn

    user, child = household
    with DB.begin() as db:
        ids = []
        for index, (done, more, old) in enumerate([([], False, False), (['a'], False, False),
                (['a', 'b'], False, False), (['a', 'b'], True, False), (['a'], False, True)]):
            m = Material(child_id=child['id'], purpose='homework', subject='Mathematik', topic='Synthetisch',
                title=f'Foto {index}', confirmed=True, created=100 + index)
            db.add(m)
            db.flush()
            turn = TutorTurn(child_id=child['id'], user_id=user['id'], material_id=m.id, question='',
                status='ready', source_revisions=[{'id': m.id, 'revision': 1}],
                homework_context={'action': 'analyze', 'sequence': 1},
                reply={'tasks': [{'id': 'a', 'title': 'Aufgabe A'}, {'id': 'b', 'title': 'Aufgabe B'}], 'more_tasks': more})
            db.add(turn)
            db.flush()
            m.homework_state = {'source_revision': 1, 'analysis_id': 'removed-analysis' if old else turn.id, 'done': done}
            ids.append(m.id)
        unknown = Material(child_id=child['id'], purpose='homework', subject='Englisch', title='Noch ungeprüft', created=110)
        db.add(unknown)
        db.flush()
        ids.append(unknown.id)
        return child['id'], ids


@pytest.mark.parametrize('progress,positions', [('none', [0, 4, 5]), ('partial', [1, 3]), ('complete', [2]), ('unanalyzed', [5])])
def test_pk025_026_homework_progress_uses_the_actual_current_task_ids(api, household, progress, positions):
    child, ids = homework_seed(household)
    before = snapshot()
    response = api.get(f'/api/children/{child}/homework-review', params={'progress': progress})
    assert response.status_code == 200, response.text
    value = response.json()
    assert {p['id'] for p in value['photos']} == {ids[i] for i in positions}
    assert value['total'] == len(positions)
    if progress == 'complete':
        assert all(p['marked_done'] == p['task_count'] and not p['more_tasks'] for p in value['photos'])
    assert snapshot() == before


def test_pk025_old_analysis_marks_do_not_contradict_the_visible_card(api, household):
    child, ids = homework_seed(household)
    path = f'/api/children/{child}/homework-review'
    worked = api.get(path, params={'state': 'worked'}).json()
    assert {p['id'] for p in worked['photos']} == set(ids[1:4])
    opened = api.get(path, params={'state': 'open'}).json()
    assert ids[4] in {p['id'] for p in opened['photos']}
    assert all(p['marked_done'] == 0 for p in opened['photos'])


def test_pk024_oldest_homework_cursor_is_stable_with_same_timestamps(api, household):
    from schulpilot.db import Material

    _, child = household
    with DB.begin() as db:
        for i in range(44):
            db.add(Material(child_id=child['id'], purpose='homework', subject='Mathematik', title=f'Foto{i}', created=100))
    path = f'/api/children/{child["id"]}/homework-review'
    ids, cursor = [], None
    for _ in range(3):
        response = api.get(path, params={'order': 'oldest', **({'cursor': cursor} if cursor else {})})
        assert response.status_code == 200, response.text
        value = response.json()
        ids.extend(p['id'] for p in value['photos'])
        cursor = value['next_cursor']
    assert len(ids) == len(set(ids)) == 44 and cursor is None
    assert ids == sorted(ids)


def test_pk023_photo_date_range_uses_child_timezone_and_inclusive_local_days(api, household):
    from datetime import datetime
    from zoneinfo import ZoneInfo

    from schulpilot.db import Material

    _, child = household
    with DB.begin() as db:
        saved = db.get(Child, child['id'])
        saved.preferences = {**saved.preferences, 'timezone': 'Europe/Berlin'}
        for hour in (0, 1, 23):
            # DST transition day: the full local day must be retained.
            db.add(Material(child_id=child['id'], purpose='homework', subject='Mathematik', title=f'Zeit{hour}',
                created=int(datetime(2026, 10, 25, hour, tzinfo=ZoneInfo('Europe/Berlin')).timestamp())))
        db.add(Material(child_id=child['id'], purpose='homework', subject='Englisch', title='Anderer Tag',
            created=int(datetime(2026, 10, 26, 0, tzinfo=ZoneInfo('Europe/Berlin')).timestamp())))
    path = f'/api/children/{child["id"]}/homework-review'
    value = api.get(path, params={'start': '2026-10-25', 'end': '2026-10-25'})
    assert value.status_code == 200, value.text
    assert value.json()['total'] == 3
    assert api.get(path, params={'start': '2026-10-26', 'end': '2026-10-25'}).status_code == 422


def profile_body(child, **updates):
    return {'display_name': child['display_name'], 'grade': child['grade'], 'subjects': child['subjects'],
            'school_type': child['school_type'], 'region': child['region'], **updates}


def test_pk034_child_profile_compare_and_swap_keeps_another_parents_change(api, household):
    user, child = household
    original = api.get(f'/api/families/{user["families"][0]["id"]}').json()['children'][0]
    revision = original['profile_revision']
    path = f'/api/children/{child["id"]}'
    first = api.put(path, json=profile_body(original, display_name='Geändert'), headers={'If-Match': revision})
    assert first.status_code == 200, first.text
    changed = first.json()
    assert changed['profile_revision'] != revision
    stale = api.put(path, json=profile_body(original, region='Anderer alter Entwurf'), headers={'If-Match': revision})
    assert stale.status_code == 409
    current = api.get(f'/api/families/{user["families"][0]["id"]}').json()['children'][0]
    assert current['display_name'] == 'Geändert' and current['region'] == original['region']
    assert api.put(path, json=profile_body(current, region='Bewusst aktuell'), headers={'If-Match': changed['profile_revision']}).status_code == 200


def test_pk034_legacy_profile_update_keeps_existing_contract(api, household):
    _, child = household
    response = api.put(f'/api/children/{child["id"]}', json=profile_body(child, region='Geändert ohne If-Match'))
    assert response.status_code == 200
    assert response.json()['region'] == 'Geändert ohne If-Match'
    assert len(response.json()['profile_revision']) == 64


def test_pk034_profile_revision_does_not_change_for_unrelated_preferences(api, household):
    user, child = household
    path = f'/api/families/{user["families"][0]["id"]}'
    initial = api.get(path).json()['children'][0]['profile_revision']
    with DB.begin() as db:
        row = db.get(Child, child['id'])
        row.preferences = {**row.preferences, 'daily_minutes': 35}
    assert api.get(path).json()['children'][0]['profile_revision'] == initial


def test_pk034_parallel_profile_writes_claim_one_version(api, household):
    from concurrent.futures import ThreadPoolExecutor

    user, child = household
    original = api.get(f'/api/families/{user["families"][0]["id"]}').json()['children'][0]
    def write(name):
        return api.put(f'/api/children/{child["id"]}', json=profile_body(original, display_name=name),
            headers={'If-Match': original['profile_revision']}).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = list(pool.map(write, ['Synthetischer Entwurf A', 'Synthetischer Entwurf B']))
    assert sorted(outcomes) == [200, 409]


def test_pk037_child_export_is_exactly_one_child_and_cleans_temporary_zip(api, household):
    import json
    import zipfile

    from schulpilot.config import settings

    user, child = household
    other = create_child(api, user, 'synthetic-sibling')
    response = api.get(f'/api/children/{child["id"]}/export')
    assert response.status_code == 200, response.text
    assert 'no-store' in response.headers['cache-control']
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        assert archive.namelist() == ['child.json']
        value = json.loads(archive.read('child.json'))
    assert value['child']['id'] == child['id']
    assert other['id'] not in json.dumps(value)
    assert not {'account', 'orders', 'usage'} & value.keys()
    assert not list((settings.data_dir / 'exports').glob('child-*.zip'))


def test_pk037_child_export_remains_parent_only_and_family_scoped(api, household, mailbox):
    from conftest import HEADERS
    from fastapi.testclient import TestClient
    from schulpilot.main import app

    _, child = household
    path = f'/api/children/{child["id"]}/export'
    with TestClient(app, headers=HEADERS) as client:
        login = client.post('/api/auth/login', json={'username': child['username'], 'password': 'secure-child-pass-123'})
        assert login.status_code == 200
        client.headers['Authorization'] = 'Bearer ' + login.json()['token']
        assert client.get(path).status_code == 403
    register(api, mailbox, 'unrelated-export-parent@example.org')
    assert api.get(path).status_code == 404


def test_pk038_deadlines_are_actual_open_targets_not_ai_time_proposals(api, household):
    child, today, goals, _ = seed(household)
    before = snapshot()
    response = api.get(f'/api/children/{child}/learning-deadlines', params={'start': (today-timedelta(days=3)).isoformat(), 'end': (today+timedelta(days=3)).isoformat()})
    assert response.status_code == 200, response.text
    value = response.json()
    assert [row['id'] for row in value['items']] == [goals[-1], goals[-3]]
    assert value['total'] == 2 and not value['truncated']
    assert snapshot() == before
    voluntary = api.get(f'/api/children/{child}/learning-deadlines', params={'obligation':'voluntary'}).json()
    assert voluntary['total'] == 0


def test_pk039_calendar_is_all_day_private_escaped_and_statically_bounded(api, household):
    child, today, goals, _ = seed(household)
    with DB.begin() as db:
        row = db.get(Assignment, goals[-3])
        row.topic = 'Ä' * 100 + ', Aufgabe; 1\nBEGIN:VEVENT'
    before = snapshot()
    endpoint = f'/api/children/{child}/learning-deadlines.ics'
    response = api.get(endpoint)
    assert response.status_code == 200
    assert 'no-store' in response.headers['cache-control']
    text = response.content.decode('utf-8')
    assert text.split('\r\n').count('BEGIN:VEVENT') == 1
    unfolded = text.replace('\r\n ', '')
    assert 'DTSTART;VALUE=DATE:'+(today+timedelta(days=1)).strftime('%Y%m%d') in unfolded
    assert 'DTEND;VALUE=DATE:'+(today+timedelta(days=2)).strftime('%Y%m%d') in unfolded
    assert '\\, Aufgabe\\; 1\\nBEGIN:VEVENT' in unfolded
    assert all(len(line.encode('utf-8')) <= 75 for line in text.split('\r\n'))
    assert 'Statische private Kopie' in unfolded
    assert 'URL:' not in text and 'ATTACH:' not in text
    assert snapshot() == before
    assert api.get(endpoint, params={'start':'2026-10-22','end':'2028-10-22'}).status_code == 422
    assert api.get(endpoint, params={'start':'2026-10-22','end':'2026-10-21'}).status_code == 422


def test_pk036_overview_selection_filters_only_confirmed_mandatory_goals(api, household):
    child, _, goals, _ = seed(household)
    with DB.begin() as db:
        row = db.get(Assignment, goals[-3])
        row.source_status = 'needs_review'
    response = api.get(f'/api/children/{child}/learning-plan', params={'completion':'open','source':'confirmed','obligation':'mandatory'})
    assert response.status_code == 200
    assert [row['id'] for row in response.json()['topics']] == [goals[-1]]


def test_pk055_grade_sources_use_retained_confirmed_pdf_slot_without_inventing_manual_origin(api, household):
    from schulpilot.db import GradeSourceSlot

    child, _, _, grades = seed(household)
    with DB.begin() as db:
        db.add(GradeSourceSlot(child_id=child, grade_id=grades[0], slot_key='a'*64,
            school_year_start=2026, last_value='1', ignored=False))
        db.get(SchoolGrade, grades[0]).value = 5
    before = snapshot()
    path = f'/api/children/{child}/grades'
    value = api.get(path, params={'source': 'pdf'}).json()
    assert [row['id'] for row in value['items']] == [grades[0]]
    assert value['items'][0]['provenance'] == {'kind':'pdf','school_year_start':2026,'last_pdf_value':'1'}
    assert value['items'][0]['value'] == 5
    others = api.get(path, params={'source':'manual'}).json()
    assert len(others['items']) == 4 and all(row['provenance'] == {'kind':'without_pdf'} for row in others['items'])
    assert snapshot() == before


def test_pk056_linked_grade_filter_and_csv_share_the_actual_saved_goal_selection(api, household):
    child, _, goals, grades = seed(household)
    with DB.begin() as db:
        db.get(SchoolGrade, grades[0]).assignment_id = goals[0]
    before = snapshot()
    root = f'/api/children/{child}'
    value = api.get(root+'/grades',params={'goal':'linked'}).json()
    assert [row['id'] for row in value['items']] == [grades[0]]
    assert value['items'][0]['assignment_id'] == goals[0]
    assert api.get(root+'/grades',params={'goal':'none'}).json()['pagination']['total'] == 4
    rows = list(csv.reader(io.StringIO(api.get(root+'/grades-export.csv',params={'goal':'linked'}).content.decode('utf-8-sig')),delimiter=';'))
    assert len(rows) == 2 and rows[1][1] == 'Datiert'
    assert snapshot() == before


def test_pk057_child_text_export_excludes_only_photos_and_keeps_real_material_evidence(api, household):
    import json
    import zipfile

    from schulpilot.config import settings
    from schulpilot.db import Material

    _, child = household
    with DB.begin() as db:
        material = Material(child_id=child['id'],path='synthetic-photo.jpg',title='Synthetisches Testfoto',subject='Mathematik',content='Künstlicher Quelltext')
        db.add(material)
    (settings.data_dir/'uploads').mkdir(exist_ok=True)
    (settings.data_dir/'uploads'/'synthetic-photo.jpg').write_bytes(b'SYNTHETIC-NOT-A-REAL-PHOTO')
    path = f'/api/children/{child["id"]}/export'
    default = api.get(path)
    limited = api.get(path,params={'include_photos':'false'})
    assert default.status_code == limited.status_code == 200
    with zipfile.ZipFile(io.BytesIO(default.content)) as archive:
        assert 'materials/synthetic-photo.jpg' in archive.namelist()
    with zipfile.ZipFile(io.BytesIO(limited.content)) as archive:
        assert archive.namelist() == ['child.json']
        content = json.loads(archive.read('child.json'))
        assert content['materials'][0]['content'] == 'Künstlicher Quelltext'
    assert not list((settings.data_dir/'exports').glob('child-*.zip'))


def test_pk059_homework_timestamp_matches_child_day_even_when_browser_time_would_be_previous_day(api, household):
    from datetime import datetime
    from zoneinfo import ZoneInfo

    from schulpilot.db import Material

    _, child = household
    with DB.begin() as db:
        row = db.get(Child,child['id'])
        row.preferences = {**row.preferences,'timezone':'Europe/Berlin'}
        db.add(Material(child_id=child['id'],title='Synthetischer Abend',purpose='homework',created=int(datetime(2026,10,25,0,15,tzinfo=ZoneInfo('Europe/Berlin')).timestamp())))
    value = api.get(f'/api/children/{child["id"]}/homework-review',params={'start':'2026-10-25','end':'2026-10-25'}).json()
    assert value['timezone'] == 'Europe/Berlin'
    assert value['photos'][0]['created_local'] == '2026-10-25T00:15:00+02:00'


def test_pk060_homework_search_reads_only_current_recognized_task_titles_and_literal_characters(api, household):
    from schulpilot.db import TutorTurn

    child, ids = homework_seed(household)
    with DB.begin() as db:
        turn = db.scalar(select(TutorTurn).where(TutorTurn.material_id==ids[0]))
        turn.reply = {'tasks':[{'id':'a','title':'Pythagoras 100% sicher'}],'more_tasks':False}
        other = db.scalar(select(TutorTurn).where(TutorTurn.material_id==ids[1]))
        other.source_revisions = [{'id':ids[1],'revision':0}]
        other.reply = {'tasks':[{'id':'a','title':'Veralteter Pythagoras'}]}
    before = snapshot()
    endpoint=f'/api/children/{child}/homework-review'
    value=api.get(endpoint,params={'q':'PYTHAGORAS'}).json()
    assert [row['id'] for row in value['photos']] == [ids[0]]
    assert api.get(endpoint,params={'q':'%'}).json()['total'] == 1
    assert api.get(endpoint,params={'q':'_'}).json()['total'] == 0
    assert snapshot() == before


def test_pk034_profile_waiting_for_child_user_lock_does_not_write_after_parent_logout(api, household):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Event

    from schulpilot.db import Session, User, engine
    from sqlalchemy import event, update

    if engine.dialect.name != 'postgresql':
        pytest.skip('PostgreSQL lock/session case')
    user, child = household
    reached = Event()
    def waiting(_connection, _cursor, statement, _parameters, _context, _many):
        if statement.startswith('UPDATE users SET display_name=users.display_name'):
            reached.set()
    with ThreadPoolExecutor(max_workers=1) as pool:
        with DB.begin() as blocker:
            child_user_id = blocker.get(Child,child['id']).user_id
            blocker.scalar(select(User).where(User.id==child_user_id).with_for_update())
            event.listen(engine,'before_cursor_execute',waiting)
            try:
                future = pool.submit(api.put,f'/api/children/{child["id"]}',json=profile_body(child,display_name='Veralteter Elternzugriff'))
                assert reached.wait(5)
                with DB.begin() as db:
                    db.execute(update(Session).where(Session.user_id==user['id']).values(revoked=True))
            finally:
                event.remove(engine,'before_cursor_execute',waiting)
        assert future.result(timeout=10).status_code == 401
    with DB() as db:
        assert db.get(User,child_user_id).display_name == child['display_name']
