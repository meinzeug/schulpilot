from datetime import date
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator

Short = Annotated[str, Field(min_length=1, max_length=160)]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Register(Strict):
    email: EmailStr
    password: str = Field(min_length=12, max_length=128)
    display_name: str = Field(min_length=1, max_length=80)
    family_name: str = Field(min_length=1, max_length=120)
    adult_consent: Literal[True]


class Login(Strict):
    username: str = Field(min_length=1, max_length=254)
    password: str = Field(min_length=1, max_length=128)
    device: str = Field(default="Browser", max_length=100)
    totp: str = Field(default="", max_length=8)


class EmailRequest(Strict):
    email: EmailStr


class TokenRequest(Strict):
    token: str = Field(min_length=32, max_length=128)


class ResetRequest(TokenRequest):
    password: str = Field(min_length=12, max_length=128)


class ConfirmPassword(Strict):
    password: str = Field(min_length=1, max_length=128)


class ChildCreate(Strict):
    display_name: str = Field(min_length=1, max_length=80)
    username: str = Field(min_length=5, max_length=50, pattern=r"^[a-zA-Z0-9._-]+$")
    password: str = Field(min_length=12, max_length=128)
    grade: int = Field(ge=1, le=13)
    subjects: list[str] = Field(default_factory=list, max_length=20)
    school_type: str = Field(default="", max_length=80)
    region: str = Field(default="", max_length=80)


class ChildUpdate(Strict):
    display_name: str = Field(min_length=1, max_length=80)
    grade: int = Field(ge=1, le=13)
    subjects: list[str] = Field(max_length=20)
    school_type: str = Field(default="", max_length=80)
    region: str = Field(default="", max_length=80)


class InviteCreate(Strict):
    email: EmailStr
    permission: Literal["view", "manage"]


class InviteAccept(TokenRequest):
    password: str = Field(default="", max_length=128)
    display_name: str = Field(default="", max_length=80)


class Preferences(Strict):
    weekdays: list[int] = Field(default_factory=lambda: [0, 1, 2, 3, 4], max_length=7)
    daily_minutes: int = Field(default=20, ge=5, le=120)
    weekly_minutes: int = Field(default=100, ge=5, le=600)
    session_minutes: int = Field(default=15, ge=5, le=45)
    break_minutes: int = Field(default=5, ge=1, le=30)
    focus_subjects: list[str] = Field(default_factory=list, max_length=20)
    subject_days: dict[Annotated[str, Field(min_length=1, max_length=80)], list[int]] = Field(
        default_factory=dict, max_length=20
    )
    repeat_topics: list[str] = Field(default_factory=list, max_length=20)
    pause_until: date | None = None
    quiet_start: int = Field(default=20, ge=0, le=23)
    quiet_end: int = Field(default=8, ge=0, le=23)
    reminders: bool = False
    notify_help: bool = True
    timezone: str = Field(default="Europe/Berlin", max_length=64)

    @model_validator(mode="after")
    def valid_days(self):
        from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

        if any(d < 0 or d > 6 for d in self.weekdays) or len(set(self.weekdays)) != len(self.weekdays):
            raise ValueError("Wochentage müssen eindeutig zwischen 0 und 6 liegen.")
        if any(
            len(days) > 7 or len(days) != len(set(days)) or any(d < 0 or d > 6 for d in days)
            for days in self.subject_days.values()
        ):
            raise ValueError("Fach-Lerntage müssen eindeutig zwischen 0 und 6 liegen.")
        try:
            ZoneInfo(self.timezone)
        except ZoneInfoNotFoundError:
            raise ValueError("Unbekannte Zeitzone.") from None
        return self


class AssignmentCreate(Strict):
    kind: Literal["parent", "exam"] = "parent"
    subject: str = Field(min_length=1, max_length=80)
    topic: Short
    note: str = Field(default="", max_length=2000)
    due: date | None = None
    scheduled_for: date | None = None
    material_id: str | None = None
    mandatory: bool = True

    @model_validator(mode="after")
    def dates_consistent(self):
        if self.due and self.scheduled_for and self.scheduled_for > self.due:
            raise ValueError("Der Lernbeginn darf nicht nach dem Termin liegen.")
        return self


class MaterialConfirm(Strict):
    subject: str = Field(min_length=1, max_length=80)
    topic: Short
    content: str = Field(min_length=1, max_length=24000)
    homework: list[Annotated[str, Field(max_length=500)]] = Field(default_factory=list, max_length=20)
    uncertainties_resolved: Literal[True]


class Question(Strict):
    id: str = Field(min_length=1, max_length=60, pattern=r"^[A-Za-z0-9_-]+$")
    type: Literal["choice", "gap", "match", "short"]
    prompt: str = Field(min_length=1, max_length=1000)
    options: list[Annotated[str, Field(max_length=200)]] = Field(
        max_length=8,
        description="choice: vollständige unterschiedliche Antworten. match: links|rechts-Paare; ALLE linken und ALLE rechten Werte jeweils verschieden, eindeutig eins zu eins. Sonst leere Liste.",
    )
    answer: str = Field(
        min_length=1,
        max_length=600,
        description="choice: exakt eine vorhandene Option. gap/short: eine eindeutig prüfbare Antwort. match: rechte Werte der Paare in Originalreihenfolge mit Semikolon verbunden, ohne zusätzliche Trenn-Leerzeichen.",
    )
    accepted: list[Annotated[str, Field(max_length=200)]] = Field(max_length=10)
    hints: list[Annotated[str, Field(max_length=500)]] = Field(min_length=1, max_length=3)
    explanation: str = Field(min_length=1, max_length=1500)

    @model_validator(mode="after")
    def consistent(self):
        from .checks import fraction_result

        if self.type in ("choice", "gap", "short"):
            fraction_result(self.prompt, self.answer, self.accepted)
        if self.type == "choice" and (len(self.options) < 2 or self.answer not in self.options):
            raise ValueError("Auswahlaufgabe ohne gültige Antwort.")
        if len(set(self.options)) != len(self.options):
            raise ValueError("Doppelte Auswahlmöglichkeiten.")
        if self.type == "match":
            # Each item has exactly one 'left|right' pair. Answer is the ordered
            # right-hand list joined by ';', clients shuffle independently.
            if len(self.options) < 2 or any(x.count("|") != 1 for x in self.options):
                raise ValueError("Ungültige Zuordnung.")
            right = [x.split("|")[1] for x in self.options]
            left = [x.split("|")[0] for x in self.options]
            if len(set(left)) != len(left) or len(set(right)) != len(right) or self.answer != ";".join(right):
                raise ValueError("Zuordnung ist nicht eindeutig.")
        return self


class UnitOutput(Strict):
    subject: str = Field(min_length=1, max_length=80)
    topic: Short
    explanation: str = Field(min_length=1, max_length=5000)
    questions: list[Question] = Field(min_length=1, max_length=8)

    @model_validator(mode="after")
    def unique_questions(self):
        if len({q.id for q in self.questions}) != len(self.questions):
            raise ValueError("Doppelte Aufgaben-ID.")
        return self


class ExtractionOutput(Strict):
    legibility: Literal["readable", "partial", "unreadable"] = "readable"
    subject: str = Field(max_length=80)
    topic: str = Field(max_length=160)
    content: str = Field(max_length=24000)
    uncertainties: list[Annotated[str, Field(max_length=500)]] = Field(max_length=30)
    homework: list[Annotated[str, Field(max_length=500)]] = Field(max_length=20)

    @model_validator(mode="after")
    def readable_content(self):
        if self.legibility == "unreadable":
            if not self.uncertainties or self.homework or self.content.strip():
                raise ValueError(
                    "Unleserliche Seiten brauchen einen Unsicherheitshinweis und dürfen keinen erfundenen Stoff oder Hausaufgaben enthalten."
                )
        elif not all(value.strip() for value in (self.subject, self.topic, self.content)):
            raise ValueError("Lesbarer oder teilweise lesbarer Stoff benötigt Fach, Thema und Inhalt.")
        if self.legibility == "partial" and not self.uncertainties:
            raise ValueError("Teilweise lesbarer Stoff benötigt einen Unsicherheitshinweis.")
        return self


class PackageUnitOutput(UnitOutput):
    group_id: Annotated[str, Field(pattern=r"^g[1-9][0-9]?$", max_length=3)]
    questions: list[Question] = Field(min_length=2, max_length=5)


class PackageOutput(Strict):
    units: list[PackageUnitOutput] = Field(min_length=1, max_length=3)


class UnitCreate(Strict):
    material_id: str | None = None
    assignment_id: str | None = None
    review_of: str | None = None


class AnswerRequest(Strict):
    answer: str = Field(max_length=1000)


class FeedbackRequest(Strict):
    kind: Literal["too_easy", "too_hard", "unclear"]


class MessageRequest(Strict):
    kind: Literal["help", "interest", "plan_change", "reply"]
    body: str = Field(min_length=1, max_length=1000)


class ProviderUpdate(Strict):
    provider: Literal["disabled", "openai", "openrouter", "codex"]
    model: str = Field(max_length=160)
    extraction_model: str = Field(default="", max_length=160)
    extraction_capability_evidence: str = Field(default="", max_length=500)
    api_key: str | None = Field(default=None, max_length=1024)
    emergency_stop: bool
    image_capable: bool
    structured_capable: bool
    capability_evidence: str = Field(default="", max_length=500)
    privacy_approved: bool = False
    privacy_evidence: str = Field(default="", max_length=500)
    reserve_micros: int = Field(ge=1000, le=10_000_000)
    input_per_million_micros: int | None = Field(default=None, ge=0, le=1_000_000_000)
    output_per_million_micros: int | None = Field(default=None, ge=0, le=1_000_000_000)
    pricing_evidence: str = Field(default="", max_length=500)
    max_output_tokens: int = Field(default=4000, ge=1000, le=8000)
    global_limit_micros: int = Field(default=10_000_000, ge=0, le=1_000_000_000)
