"""Rotated artificial photos: bounding-box overlap cannot erase literal blocks."""
from types import SimpleNamespace

from schulpilot.material_review import _protected_readings


def block(text, role='student_work', region=None, annotations=None):
    return {'kind': 'paragraph', 'text': text, 'literal_role': role,
            'image_region': region or {'left': 100, 'top': 100, 'right': 800, 'bottom': 800},
            'annotations': annotations or []}


def test_overlapping_changed_and_exact_protected_blocks_all_survive_in_order():
    old = [block('Titel', 'unknown'), block('1) 2/3 Minute = 60 40 Sekunden'),
           block('2) 1 km = 1000 m'), block('3) 27 t = 27000 kg'),
           block('4) Drei von sieben: 3/7'), block('5) 7/4 = 1 3/4')]
    new = [block('Titel', 'unknown'), block('1) 2/3 Minute = 60 Sekunden\n40', 'unknown'),
           block('2) 1 km = 1000 m', 'unknown'), block('3) 27 t = 27000 kg', 'unknown'),
           block('4) Drei von sieben: 3/7', 'unknown'), block('5) 7/4 =\n1 3/4', 'unknown')]
    result = _protected_readings({'source_blocks': new, 'content': '', 'legibility': 'readable', 'uncertainties': []},
                                SimpleNamespace(snapshot={'source_blocks': old}))
    assert [b['text'] for b in result['source_blocks']] == [b['text'] for b in old]
    assert result['legibility'] == 'partial' and result['uncertainties']
    assert result['source_blocks'][1]['reading_uncertainties']
    assert not result['source_blocks'][3].get('reading_uncertainties')


def test_normal_ink_does_not_freeze_an_uncorrected_first_reading():
    old = block('Der Nemer bezeichnet die Teile.', 'unknown', annotations=[{'kind': 'ink', 'quote': 'Nemer', 'color': 'blue'}])
    corrected = block('Der Nenner bezeichnet die Teile.', 'unknown')
    result = _protected_readings({'source_blocks': [corrected], 'content': '', 'legibility': 'readable', 'uncertainties': []},
                                SimpleNamespace(snapshot={'source_blocks': [old]}))
    assert result['content'] == corrected['text']
