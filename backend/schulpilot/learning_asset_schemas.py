"""Closed public selectors; there is no field for private source text or answers."""
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from .subject_content import Presentation

Identifier = Annotated[str, Field(min_length=1, max_length=120, pattern=r"^[A-Za-z0-9_.:-]+$")]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class LearningAssetSpec(Strict):
    subject: str = Field(min_length=1, max_length=80)
    recipe_id: Identifier
    recipe_version: int = Field(ge=1, le=1000, strict=True)
    foundation_ids: list[Identifier] = Field(default_factory=list, max_length=4)
    catalog_topic_id: Identifier | None = None
    locale: Literal["de-DE"] = "de-DE"
    level_band: Literal["primary", "lower_secondary", "upper_secondary"]

    @model_validator(mode="after")
    def public_basis(self):
        if len(set(self.foundation_ids)) != len(self.foundation_ids):
            raise ValueError("Doppelte Grundlagen-ID.")
        if not self.foundation_ids and self.catalog_topic_id is None:
            raise ValueError("Eine öffentliche Grundlage oder Katalog-ID ist erforderlich.")
        return self


class AssetExploration(Strict):
    prompt: str = Field(min_length=3, max_length=240)
    # Deliberately no answer, accepted, outcome or learning_goal_id.


class LearningAssetOutput(Strict):
    subject: str = Field(min_length=1, max_length=80)
    title: str = Field(min_length=1, max_length=120)
    text: str = Field(min_length=3, max_length=1200)
    presentation: Presentation
    explorations: list[AssetExploration] = Field(min_length=1, max_length=3)
