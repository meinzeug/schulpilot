"""Bounded explicit exam schedules and immutable source selections."""

from datetime import date
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import Field, model_validator

from .schemas import Strict


class ExamSource(Strict):
    id: str = Field(pattern=r"^[a-f0-9]{32}$")
    revision: int = Field(ge=1)


class ExamTopic(Strict):
    id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,48}$")
    label: str = Field(min_length=1, max_length=160)
    question_count: int = Field(default=5, ge=1, le=50, strict=True)
    material_refs: list[ExamSource] = Field(min_length=1, max_length=16)

    @model_validator(mode="after")
    def distinct_sources(self):
        if len({ref.id for ref in self.material_refs}) != len(self.material_refs):
            raise ValueError("Eine Themenseite darf nur einmal ausgewählt werden.")
        return self


class ExamSchedule(Strict):
    dates: list[date] = Field(default_factory=list, max_length=30)

    @model_validator(mode="after")
    def distinct_dates(self):
        if len(set(self.dates)) != len(self.dates):
            raise ValueError("Jeder Lerntag darf nur einmal vorkommen.")
        self.dates.sort()
        return self


class ExamCreate(Strict):
    title: str = Field(min_length=1, max_length=160)
    purpose: Literal["preparation", "review"] = "preparation"
    kind: Literal["classwork", "test"] = "classwork"
    subject: str = Field(min_length=1, max_length=80)
    exam_date: date | None = None
    timezone: str = Field(default="Europe/Berlin", min_length=1, max_length=80)
    minutes: int = Field(default=15, ge=5, le=60)
    topics: list[ExamTopic] = Field(default_factory=list, max_length=8)
    schedule: ExamSchedule = Field(default_factory=ExamSchedule)
    reminders: bool = False
    reminder_time: str = Field(default="16:00", pattern=r"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$")

    @model_validator(mode="after")
    def valid_plan(self):
        try:
            ZoneInfo(self.timezone)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("Bitte eine gültige Zeitzone wählen.") from None
        if len({topic.id for topic in self.topics}) != len(self.topics):
            raise ValueError("Themenkennungen müssen eindeutig sein.")
        if self.purpose == "preparation" and (not self.topics or not self.schedule.dates):
            raise ValueError("Bitte mindestens ein Thema und einen Lerntag auswählen.")
        if bool(self.topics) != bool(self.schedule.dates):
            raise ValueError("Ein Lernplan braucht Themen und Lerntage zusammen.")
        if self.exam_date and any(day > self.exam_date for day in self.schedule.dates):
            raise ValueError("Lerntage dürfen nicht nach dem Prüfungstermin liegen.")
        return self


class ExamUpdate(ExamCreate):
    revision: int = Field(ge=1)


class ExamArchive(Strict):
    revision: int = Field(ge=1)
