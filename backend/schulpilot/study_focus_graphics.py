"""Bind a study stage to existing, literal, source-checked list graphics.

The exercise texts and answers remain model output and are validated normally;
only the selected graphic and its exact original options are server-bound.
"""
import copy

from . import package_prepared_focus as focus
from . import package_prepared_graphics as prepared


class StudyFocusBinding:
    def __init__(self, binding):
        self.binding = binding

    @property
    def context(self):
        return self.binding.context

    @property
    def rules(self):
        return self.binding.rules

    def hydrate(self, data):
        if not isinstance(data, dict) or 'units' in data or 'group_id' in data:
            raise ValueError('Ungültige Struktur der vorbereiteten Grafikzuordnung.')
        result = self.binding.hydrate({'units': [data]})
        return result['units'][0]


def bind_schema(schema, payload):
    context = payload.get('visual_context') or {}
    subject = payload.get('required_subject')
    if (not payload.get('study_block') or subject not in focus.SUBJECTS
            or not context.get('required') or payload.get('selected_groups')):
        return None
    # Compile from precisely the current source snapshot. The wrapper only
    # adapts the existing package compiler's structure; it adds no source.
    probe = {**payload, 'package_partition': 1,
             'selected_groups': [{'subject': subject, 'id': None}]}
    candidates = focus.compile_candidates(probe)
    if not candidates:
        return None
    binding = focus.Binding(tuple(candidates))
    unit = {key: copy.deepcopy(value) for key, value in schema.items() if key != '$defs'}
    wrapper = {'$defs': schema['$defs'], 'properties': {'units': {'items': unit}}}
    prepared.bind_candidates(wrapper, binding, question_kinds=('scene',), question_binding=focus._question_schema)
    schema['properties'] = wrapper['properties']['units']['items']['properties']
    return StudyFocusBinding(binding)
