"""Conservatively expand literal scene quotations within one confirmed source.

No labels, model statements, links, relationships, or source identities are
created or changed. A later full visual validation remains mandatory.
"""

import re

from .learning_scenes import _mentions


def _expanded(source, quote, needed):
    if not isinstance(source, str) or not isinstance(quote, str) or not (3 <= len(quote) <= 500):
        return None
    # Do not stitch pages, normalize source text, or accept generated prompts as
    # a source. Every returned character is a contiguous original source slice.
    for index, anchor in enumerate(re.finditer(re.escape(quote), source)):
        if index >= 32:
            break
        start, end = anchor.span()
        for label in needed:
            pattern = re.compile(r"(?<!\w)" + re.escape(label) + r"(?!\w)", re.I)
            matches = pattern.finditer(source, max(0, start - 500), min(len(source), end + 500))
            nearest = min(matches, key=lambda m: max(end, m.end()) - min(start, m.start()), default=None)
            if nearest is None:
                break
            start, end = min(start, nearest.start()), max(end, nearest.end())
            if end - start > 500:
                break
        else:
            result = source[start:end]
            if quote in result and all(_mentions(result, label) for label in needed):
                return result
    return None


def expand_scene_quotes(data, context):
    """Alter only scene source excerpts when the same cited source proves them."""
    if not isinstance(context, dict) or not context.get('required'):
        return
    refs = {row.get('ref'): row for row in context.get('sources', []) if isinstance(row, dict)}
    for unit in data.get('units') or [data]:
        subject, group = unit.get('subject'), unit.get('group_id')
        pairs = [(unit, None), *((question, question) for question in unit.get('questions', []))]
        for owner, question in pairs:
            prompt = question.get('prompt', '') if question else ''
            for step in owner.get('explanation_steps') or []:
                sources = [refs[ref].get('content') for ref in step.get('source_refs', [])
                    if ref in refs and refs[ref].get('subject') == subject and refs[ref].get('group_id') == group]
                for block in (step.get('presentation') or {}).get('blocks', []):
                    if block.get('kind') != 'scene' or not isinstance(block.get('scene'), dict):
                        continue
                    scene = block['scene']
                    quote = block.get('source_excerpt', '')
                    quoted = '\n'.join([quote, *[s.get('source_excerpt', '') for s in scene.get('steps', [])], prompt])
                    labels = [block.get('title', ''), *block.get('labels', []),
                        *[o.get('label', '') for o in scene.get('objects', [])]]
                    needed = [label for label in labels if isinstance(label, str) and label and not _mentions(quoted, label)]
                    # Generic graphic labels additionally must appear in the
                    # block quote or actual question, not just scene steps.
                    needed += [label for label in block.get('labels', [])
                        if isinstance(label, str) and label and not _mentions(quote + ' ' + prompt, label)]
                    if not needed:
                        continue
                    for source in sources:
                        extended = _expanded(source, quote, needed)
                        if extended is not None:
                            block['source_excerpt'] = extended
                            break
