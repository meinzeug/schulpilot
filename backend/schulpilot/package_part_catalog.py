"""Bind a planned part's existing subject identity before model generation.

The server already selected this subject. The model still chooses real topic
matches; it cannot omit or replace the registry identity of a fixed part.
Legacy and unresolved-subject requests retain their existing checks.
"""

from .subject_registry import normalized


def bind_schema(schema, payload):
    if payload.get("package_partition") is None:
        return
    groups = payload.get("selected_groups") or []
    context = payload.get("catalog_context") or {}
    if len(groups) != 1:
        return
    subject = normalized(groups[0].get("subject", ""))
    subject_id = context.get("subject_aliases", {}).get(subject)
    allowed = {row["id"] for row in context.get("subjects", [])}
    if subject_id is None or subject_id not in allowed:
        return
    field = schema.get("$defs", {}).get("CatalogAssignment", {}).get("properties", {}).get("subject_ids")
    if field is None:
        return
    field.update(minItems=1, maxItems=1)
    field["items"] = {"type": "string", "enum": [subject_id]}
