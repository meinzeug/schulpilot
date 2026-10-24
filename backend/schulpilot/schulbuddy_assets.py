"""Owned public exploration context; never a source or an assessment."""
from fastapi import HTTPException

from .learning_asset_models import LearningAssetBuild, LearningAssetInstance
from .learning_assets import NOTICE, build_data
from .subject_content import public_presentation
from .visual_reference_models import VisualReference
from .visual_references import digest


def resolve_asset(db, p, instance_id):
    row = db.get(LearningAssetInstance, instance_id)
    if not row or row.user_id != p.user.id:
        raise HTTPException(404, "Diese Erkundung gehört nicht zu diesem Zugang.")
    return row


def bind_asset(db, instance, payload):
    build = db.get(LearningAssetBuild, instance.build_key)
    value = build_data(db, build)
    if value.get("status") != "ready" or value.get("factual_status") != "unassessed":
        raise HTTPException(409, "Diese öffentliche Erkundung ist nicht mehr aktuell oder noch nicht bereit.")
    reference = value["reference"]
    row = db.get(VisualReference, (reference["id"], reference["version"]))
    if (not row or row.recipe.get("scope") != "exploration_only"
            or row.recipe.get("factual_status") != "unassessed"
            or row.recipe.get("technical_status") != "validated"):
        raise HTTPException(409, "Die Erkundungsreferenz ist nicht mehr gültig.")
    asset = value["asset"]
    context = {key: asset[key] for key in ("subject", "title", "text", "explorations")}
    context.update(presentation=public_presentation(asset["presentation"]), reference=reference,
                   mode="unassessed_exploration", technical_status="validated",
                   factual_status="unassessed", notice=NOTICE)
    payload["current_learning_asset"] = context
    return asset["subject"] + " · " + asset["title"], [instance.id, instance.user_id, instance.child_id, instance.build_key, digest(context)]
