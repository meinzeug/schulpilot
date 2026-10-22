"""Parent grade filters remain read-only and search beyond the current page."""
import pytest
from schulpilot.db import DB, Activity, Assignment, Attempt, Child, Job, LearningUnit, SchoolGrade, Usage
from schulpilot.learning import local_day
from sqlalchemy import func, select


def snapshot():
    with DB() as db:
        return tuple(db.scalar(select(func.count()).select_from(model)) for model in (
            Activity, Assignment, Attempt, Job, LearningUnit, SchoolGrade, Usage))


def seed(household):
    _, child = household
    with DB.begin() as db:
        today = local_day(db.get(Child, child['id']))
        for index in range(24):
            db.add(SchoolGrade(child_id=child['id'], subject='Mathematik', topic=f'Brüche {index}',
                kind='test', scale='grade_1_6', value=3, weight=1, assessed_on=today.isoformat(), created=100+index))
        for index in range(24):
            db.add(SchoolGrade(child_id=child['id'], subject='Mathematik', topic=f'Undatiert {index}',
                kind='test', scale='grade_1_6', value=3, weight=1, school_year_start=today.year, semester=2, created=100+index))
        wanted = SchoolGrade(child_id=child['id'], subject='Englisch', topic='100%_Wörter', note='Künstliche Wortarten',
            kind='oral', scale='points_0_15', value=12, weight=1, school_year_start=today.year, semester=1, created=1)
        db.add(wanted)
        db.flush()
        return child['id'], wanted.id


@pytest.mark.parametrize('filters', [
    {'q': '100%_Wörter'}, {'q': ' WORTARTEN '}, {'kind': 'oral'},
    {'scale': 'points_0_15'}, {'date_precision': 'semester', 'subject': 'Englisch'},
    {'q': 'Wörter', 'kind': 'oral', 'scale': 'points_0_15', 'date_precision': 'semester'},
])
def test_pp059_062_real_filters_reach_older_grade_and_preserve_full_planning(api, household, filters):
    child, wanted = seed(household)
    endpoint = f'/api/children/{child}/grades'
    original = api.get(endpoint).json()
    assert wanted not in {row['id'] for row in original['items']}
    before = snapshot()
    for _ in range(2):
        response = api.get(endpoint, params=filters)
        assert response.status_code == 200, response.text
        value = response.json()
        assert [row['id'] for row in value['items']] == [wanted]
        assert value['pagination'] == {'page': 1, 'pages': 1, 'total': 1, 'page_size': 20}
        assert value['focus'] == original['focus']
        assert value['planning_enabled'] == original['planning_enabled']
    assert snapshot() == before


def test_pp059_062_bounded_literal_filters_do_not_leak_or_mutate(api, household):
    child, _ = seed(household)
    endpoint = f'/api/children/{child}/grades'
    before = snapshot()
    assert api.get(endpoint, params={'q': '%_'}).json()['pagination']['total'] == 1
    assert api.get(endpoint, params={'q': 'no-such-value'}).json()['items'] == []
    assert api.get(endpoint, params={'q': 'x' * 161}).status_code == 422
    for field in ('kind', 'scale', 'date_precision'):
        assert api.get(endpoint, params={field: 'invented'}).status_code == 422
    assert api.get('/api/children/missing/grades', params={'q': 'Wörter'}).status_code == 404
    assert snapshot() == before


def test_pp062_day_filter_never_invents_dates_for_semester_only_results(api, household):
    child, _ = seed(household)
    endpoint = f'/api/children/{child}/grades'
    value = api.get(endpoint, params={'date_precision': 'day', 'page_size': 50}).json()
    assert len(value['items']) == 24
    assert all(row['assessed_on'] is not None for row in value['items'])
    semester = api.get(endpoint, params={'date_precision': 'semester', 'subject': 'Englisch'}).json()['items'][0]
    assert semester['assessed_on'] is None and semester['date_precision'] == 'semester'
