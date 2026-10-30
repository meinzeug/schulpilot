"""Prove disclosed sentence markings against complete literal role statements."""
import re
from itertools import groupby


def validate(block):
    roles = {}
    for mark in block.marks:
        if mark.index in roles and roles[mark.index] != mark.role:
            raise ValueError("Ein Satzbaustein besitzt widersprüchliche Rollenmarkierungen.")
        roles[mark.index] = mark.role
    # Do not accept a prefix of a longer named constituent, or a role mentioned
    # inside a negated narrative. Only explicit complete line/field statements.
    begin = r"(?:^|;|[.!?][ \t]+)[ \t]*"
    next_field = r"(?:Das[ \t]+)?(?:Subjekt|Prädikat)[ \t]*[:=]"
    end = r"(?=[ \t]*(?:[.!?](?:[ \t]*(?:\n|$)|[ \t]+(?=" + next_field + r"))|\n|$|;))"
    for role, term in (("subject", "Subjekt"), ("predicate", "Prädikat")):
        indices = sorted(index for index, value in roles.items() if value == role)
        for _, run in groupby(enumerate(indices), lambda item: item[1] - item[0]):
            selected = [index for _, index in run]
            phrase = r"\s+".join(re.escape(word) for index in selected for word in block.labels[index].split())
            forward = begin + r"(?:Das[ \t]+)?" + term + r"\s*[:=]\s*" + phrase + end
            reverse = begin + phrase + r"\s+(?:ist|=)\s+(?:das\s+)?" + term + end
            if not re.search(forward + "|" + reverse, block.source_excerpt, re.I | re.M):
                raise ValueError("Satzmarkierung hat keinen eindeutigen vollständigen Rollenbeleg.")
