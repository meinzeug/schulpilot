"""Reviewed data imports preserve the official scope instead of guessing years."""

from datetime import date
from typing import Annotated, Literal
from urllib.parse import urlsplit

from pydantic import Field, model_validator

from .schemas import Strict

Identifier = Annotated[str, Field(pattern=r"^[a-z0-9][a-z0-9_.-]{1,119}$")]
Grade = Annotated[int, Field(ge=1, le=13, strict=True)]


class DocumentInput(Strict):
    id: Identifier
    state_code: str = Field(pattern=r"^DE-[A-Z]{2}$")
    title: str = Field(min_length=1, max_length=240)
    official_url: str = Field(min_length=12, max_length=1500)
    edition: str | None = Field(default=None, max_length=100)
    effective_from: date | None = None
    school_form_label: str = Field(min_length=1, max_length=80)
    school_form_id: Identifier
    school_form_scope: Literal["specific", "cross_form"] = "specific"
    applies_to_school_forms: list[Identifier] = Field(default_factory=list, max_length=40)
    applicability_note: str = Field(default="", max_length=1000)
    document_kind: Literal["curriculum", "official_guidance", "official_index", "historical_curriculum"] = "curriculum"
    source_notes: str = Field(default="", max_length=1000)
    source_status: Literal["current_verified", "version_not_verified"]
    retrieved: date

    @model_validator(mode="after")
    def official_url_only(self):
        url = urlsplit(self.official_url)
        if url.scheme != "https" or not url.hostname or url.username or url.password or url.port not in (None, 443):
            raise ValueError("Lehrplanbelege brauchen einen amtlichen HTTPS-Link ohne Zugangsdaten.")
        return self


class TopicInput(Strict):
    id: str = Field(pattern=r"^[a-z0-9][a-z0-9_.-]{1,139}$")
    document_id: Identifier
    subject_key: str = Field(min_length=1, max_length=100)
    title: str = Field(min_length=1, max_length=200)
    grade_kind: Literal["exact", "band", "phase", "unclassified"]
    grades: list[Grade] | None = Field(default=None, max_length=13)
    phase_label: str | None = Field(default=None, min_length=1, max_length=120)
    section: str = Field(min_length=1, max_length=300)
    page: int | None = Field(default=None, ge=1, le=10000, strict=True)
    quote: str = Field(min_length=1, max_length=200)
    canonical_topic_key: str | None = Field(default=None, pattern=r"^[a-z0-9][a-z0-9_.-]{1,119}$")
    mapping_status: Literal["curated_source_heading"] = "curated_source_heading"
    common_fact_keywords: list[Annotated[str, Field(min_length=1, max_length=80)]] = Field(default_factory=list, max_length=16)

    @model_validator(mode="after")
    def genuine_scope(self):
        grades = self.grades or []
        if len(grades) != len(set(grades)) or grades != sorted(grades):
            raise ValueError("Klassenangaben müssen eindeutig und geordnet sein.")
        if self.grade_kind == "exact" and (len(grades) != 1 or self.phase_label):
            raise ValueError("Eine exakte Klasse braucht genau einen amtlich belegten Jahrgang.")
        if self.grade_kind == "band" and (len(grades) < 2 or grades != list(range(min(grades), max(grades) + 1)) or self.phase_label):
            raise ValueError("Ein Klassenband bleibt ein zusammenhängendes Band, keine erfundene Einzelklasse.")
        if self.grade_kind == "phase" and not self.phase_label:
            raise ValueError("Eine Phase braucht ihre Originalbezeichnung.")
        if self.grade_kind == "unclassified" and (grades or self.phase_label):
            raise ValueError("Ohne amtliche Zuordnung keine Klassen- oder Phasenangabe.")
        return self


class CoverageInput(Strict):
    complete: Literal[False] = False
    note: str = Field(default="", max_length=1000)


class CoverageGap(Strict):
    state_code: str = Field(pattern=r"^DE-[A-Z]{2}$")
    gap: str = Field(min_length=1, max_length=1000)


class CatalogueInput(Strict):
    version: Literal[1]
    retrieved: date | None = None
    coverage: CoverageInput | None = None
    documents: list[DocumentInput] = Field(max_length=200)
    topics: list[TopicInput] = Field(max_length=5000)
    coverage_gaps: list[CoverageGap] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def unique_ids(self):
        if len({row.id for row in self.documents}) != len(self.documents) or len({row.id for row in self.topics}) != len(self.topics):
            raise ValueError("Dokument- und Themenkennungen müssen eindeutig sein.")
        return self


class ProfileInput(Strict):
    revision: int = Field(ge=0, strict=True)
    profile_revision: str = Field(pattern=r"^[a-f0-9]{64}$")
    state_code: str = Field(pattern=r"^DE-[A-Z]{2}$")
    school_form_id: Identifier | None = None
    grade: Grade
