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
    tasks = payload.get('practice_tasks')
    coach_practice = (payload.get('review') is True and isinstance(tasks, list) and len(tasks) == 2
                      and all(isinstance(task, dict) and isinstance(task.get('id'), str)
                              and isinstance(task.get('learning_goal_id'), str)
                              and isinstance(task.get('source_excerpt'), str)
                              and len(task['source_excerpt'].strip()) >= 3 for task in tasks))
    if (not (payload.get('study_block') or coach_practice) or subject not in focus.SUBJECTS
            or not context.get('required') or payload.get('selected_groups')):
        return None
    # Compile from precisely the current source snapshot. The wrapper only
    # adapts the existing package compiler's structure; it adds no source.
    probe = {**payload, 'package_partition': 1,
             'selected_groups': [{'subject': subject, 'id': None}]}
    candidates = focus.compile_candidates(probe)
    if not candidates:
        return None
    if coach_practice and any(not any(
            ' '.join(task['source_excerpt'].casefold().split()) in
            ' '.join(row['block']['source_excerpt'].casefold().split())
            for row in candidates if row['disclosure'] != 'given') for task in tasks):
        # Do not silently drop a fixed goal when no offered picture covers it.
        return None
    binding = focus.Binding(tuple(candidates))
    unit = {key: copy.deepcopy(value) for key, value in schema.items() if key != '$defs'}
    wrapper = {'$defs': schema['$defs'], 'properties': {'units': {'items': unit}}}
    tasks_by_id = {task['id']: task for task in tasks} if coach_practice else {}
    def question_binding(branch, candidate):
        if coach_practice:
            ids = branch.get('properties', {}).get('id', {}).get('enum', [])
            task = tasks_by_id.get(ids[0]) if len(ids) == 1 else None
            quote = ' '.join(candidate['block']['source_excerpt'].casefold().split())
            excerpt = ' '.join(task['source_excerpt'].casefold().split()) if task else ''
            if not excerpt or excerpt not in quote:
                return None
        return focus._question_schema(branch, candidate)

    prepared.bind_candidates(wrapper, binding, question_kinds=('scene',), question_binding=question_binding)
    schema['properties'] = wrapper['properties']['units']['items']['properties']
    return StudyFocusBinding(binding)
