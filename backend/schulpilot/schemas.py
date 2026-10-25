from datetime import date
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, StringConstraints, model_validator

from .grouped_questions import FieldGroup
from .subject_content import Presentation, SourceBlock
from .visual_reference_schemas import ExplanationStep

Short = Annotated[str, Field(min_length=1, max_length=160)]
# Credential characters are exact; only identifiers and ordinary text are trimmed.
PasswordText = Annotated[str, StringConstraints(strip_whitespace=False)]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Register(Strict):
    email: EmailStr
    password: PasswordText = Field(min_length=12, max_length=128)
    display_name: str = Field(min_length=1, max_length=80)
    family_name: str = Field(min_length=1, max_length=120)
    adult_consent: Literal[True]


class Login(Strict):
    username: str = Field(min_length=1, max_length=254)
    password: PasswordText = Field(min_length=1, max_length=128)
    device: str = Field(default="Browser", max_length=100)

    @model_validator(mode="before")
    @classmethod
    def discard_legacy_totp(cls, value):
        # Existing APKs sent this obsolete field for every family login.
        # It never participates in authentication; the new clients omit it.
        if isinstance(value, dict) and "totp" in value:
            return {key: item for key, item in value.items() if key != "totp"}
        return value


class EmailRequest(Strict):
    email: EmailStr


class TokenRequest(Strict):
    token: str = Field(min_length=32, max_length=128)


class ResetRequest(TokenRequest):
    password: PasswordText = Field(min_length=12, max_length=128)


class ConfirmPassword(Strict):
    password: PasswordText = Field(min_length=1, max_length=128)


class ChildCreate(Strict):
    display_name: str = Field(min_length=1, max_length=80)
    username: str = Field(min_length=5, max_length=50, pattern=r"^[a-zA-Z0-9._-]+$")
    password: PasswordText = Field(min_length=12, max_length=128)
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
    password: PasswordText = Field(default="", max_length=128)
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
    push_consent: bool = False
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
    source_unit_id: str | None = None
    revision: int | None = Field(default=None, ge=1)
    mandatory: bool = True

    @model_validator(mode="after")
    def dates_consistent(self):
        if self.due and self.scheduled_for and self.scheduled_for > self.due:
            raise ValueError("Der Lernbeginn darf nicht nach dem Termin liegen.")
        return self


class AssignmentComplete(Strict):
    revision: int | None = Field(default=None, ge=1)


class MaterialVocabularyPreview(Strict):
    subject: str = Field(min_length=1, max_length=80)
    topic: Short
    content: Annotated[str, StringConstraints(strip_whitespace=False)] = Field(
        min_length=1, max_length=24000, pattern=r"\S"
    )


class MaterialWordSelection(Strict):
    key: str = Field(pattern=r"^[a-f0-9]{24}$")
    word: str = Field(min_length=1, max_length=200)
    meaning: str = Field(min_length=1, max_length=200)
    context: str = Field(default="", max_length=500)
    part_of_speech: str = Field(default="", max_length=40)
    confirmed: Literal[True]


class MaterialWords(Strict):
    target_locale: Literal["en-GB", "en-US", "fr-FR", "es-ES", "la"]
    language_confirmed: Literal[True]
    reverse: bool = False
    revision: int = Field(ge=1)
    # Missing on older clients: keep suggestions in review, never silently
    # promote OCR candidates into confirmed vocabulary.
    selections: list[MaterialWordSelection] | None = Field(default=None, max_length=400)


class MaterialTaskDecision(Strict):
    key: str = Field(pattern=r"^[a-f0-9]{24}$")
    classification: Literal["homework", "example", "unclear"]
    due: date | None = None


class MaterialConfirm(Strict):
    subject: str = Field(min_length=1, max_length=80)
    topic: Short
    content: Annotated[str, StringConstraints(strip_whitespace=False)] = Field(
        min_length=1, max_length=24000, pattern=r"\S"
    )
    homework: list[Annotated[str, Field(max_length=500)]] = Field(default_factory=list, max_length=20)
    uncertainties_resolved: Literal[True]
    revision: int | None = Field(default=None, ge=1)
    vocabulary: MaterialWords | None = None
    task_decisions: list[MaterialTaskDecision] = Field(default_factory=list, max_length=20)


class Question(Strict):
    explanation_steps: list[ExplanationStep] | None = Field(default=None, min_length=1, max_length=2)
    presentation: Presentation | None = None
    field_group: FieldGroup | None = None

    @model_validator(mode="before")
    @classmethod
    def decode_choice_labels(cls, value):
        from .checks import canonical_choice

        return canonical_choice(value)

    id: str = Field(min_length=1, max_length=60, pattern=r"^[A-Za-z0-9_-]+$")
    type: Literal["choice", "gap", "match", "short", "grouped"]
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
    accepted: list[Annotated[str, Field(max_length=200)]] = Field(
        max_length=10,
        description="Zusätzliche gleichwertige Schreibweisen der exakten Antwort. Bei choice und match leer. Keine Teilwerte, Zähler/Nenner oder Rechenschritte als Varianten einer Bruchlösung.",
    )
    hints: list[Annotated[str, Field(max_length=500)]] = Field(min_length=1, max_length=3)
    explanation: str = Field(min_length=1, max_length=1500)

    @model_validator(mode="after")
    def consistent(self):
        from .checks import expanded_fraction, fraction_parts, fraction_result
        from .grouped_questions import canonical, parse_answer, requires_math_contract

        if self.type == "grouped":
            if self.field_group is None or self.options or self.accepted:
                raise ValueError("Mehrfeldaufgabe benötigt eine Feldgruppe und leere äußere options/accepted.")
            if requires_math_contract(self.prompt, self.field_group):
                raise ValueError("Rechen- und Bruchdarstellungsaufgaben benötigen ein bestehendes geprüftes Einzelantwortformat.")
            values = parse_answer(self.field_group, self.answer)
            if values != {field.id: field.answer for field in self.field_group.fields}:
                raise ValueError("Gemeinsame Musterantwort und private Feldlösungen widersprechen sich.")
            self.answer = canonical(values)
        elif self.field_group is not None:
            raise ValueError("Feldgruppen gehören ausschließlich zu type grouped.")
        if self.type in ("choice", "gap", "short"):
            fraction_result(self.prompt, self.answer, self.accepted, question_type=self.type, options=self.options)
            expected_form = expanded_fraction(self.prompt)
            if expected_form:
                if fraction_parts(self.answer) != expected_form:
                    raise ValueError("Die Bruchdarstellung entspricht nicht dem verlangten Erweiterungsfaktor.")
                # The main answer is already correct. Remove only unsuitable
                # aliases, never replace an answer or generate another task.
                self.accepted = [v for v in self.accepted if fraction_parts(v) == expected_form]
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
    explanation_steps: list[ExplanationStep] | None = Field(default=None, min_length=1, max_length=3)
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
    source_blocks: list[SourceBlock] = Field(default_factory=list, max_length=80)

    legibility: Literal["readable", "partial", "unreadable"] = "readable"
    subject: str = Field(max_length=80)
    topic: str = Field(max_length=160)
    content: Annotated[str, StringConstraints(strip_whitespace=False)] = Field(max_length=24000)
    uncertainties: list[Annotated[str, Field(max_length=500)]] = Field(max_length=30)
    homework: list[Annotated[str, Field(max_length=500)]] = Field(max_length=20)

    @model_validator(mode="after")
    def readable_content(self):
        if self.source_blocks and "\n\n".join(b.text for b in self.source_blocks) != self.content:
            raise ValueError("Abschnittsrollen gehören nicht zur wörtlichen Abschrift.")
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


class LearningGoal(Strict):
    id: Literal["g1", "g2", "g3", "g4"]
    label: str = Field(min_length=3, max_length=180)
    source_excerpt: str = Field(min_length=3, max_length=400)


class PracticeQuestion(Question):
    learning_goal_id: Literal["g1", "g2", "g3", "g4"]


class PracticeUnitOutput(UnitOutput):
    questions: list[PracticeQuestion] = Field(min_length=2, max_length=2)


class QuestionFeedback(Strict):
    question_id: str = Field(min_length=1, max_length=60)
    outcome: Literal["correct", "incorrect", "uncertain"]
    feedback: str = Field(min_length=1, max_length=700)


class QuestionReview(QuestionFeedback):
    learning_goal_id: Literal["g1", "g2", "g3", "g4"]


class CoachingReviewOutput(Strict):
    explanation: str = Field(min_length=1, max_length=1800)
    question_reviews: list[QuestionReview] = Field(min_length=1, max_length=8)
    next_unit: PracticeUnitOutput | None


class AssignedCoachingReviewOutput(CoachingReviewOutput):
    """Existing question-to-goal assignments belong to the server, not the model."""

    question_reviews: list[QuestionFeedback] = Field(min_length=1, max_length=8)


class CoachingOutput(CoachingReviewOutput):
    learning_goals: list[LearningGoal] = Field(min_length=1, max_length=6)


class NotebookPracticeSource(Strict):
    id: str = Field(pattern=r"^[a-f0-9]{32}$")
    revision: int = Field(strict=True, ge=1)


class UnitCreate(Strict):
    material_id: str | None = None
    assignment_id: str | None = None
    review_of: str | None = None
    notebook_sources: list[NotebookPracticeSource] | None = Field(default=None, min_length=1, max_length=12)
    question_count: int | None = Field(default=None, strict=True, ge=2, le=5)

    @model_validator(mode="after")
    def notebook_selection(self):
        if self.notebook_sources is not None:
            if not self.material_id or self.assignment_id or self.review_of:
                raise ValueError("Die Heftauswahl gehört nur zu einer neuen Runde aus der geöffneten Seite.")
            if self.question_count is None:
                self.question_count = 2
        elif self.question_count is not None:
            raise ValueError("Bitte für den gewünschten Aufgabenumfang ausdrücklich Heftseiten auswählen.")
        return self


class AnswerRequest(Strict):
    request_id: str | None = Field(default=None, min_length=16, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")
    input_method: Literal["typed", "speech"] = "typed"
    answer: str = Field(min_length=1, max_length=1000)
    guided_feedback: bool = False


class FeedbackAcknowledgement(Strict):
    attempt_id: str = Field(pattern=r"^[a-f0-9]{32}$")


class HeartbeatRequest(Strict):
    baseline: bool = False


class FeedbackRequest(Strict):
    kind: Literal["too_easy", "too_hard", "unclear", "answer_seems_right", "solution_seems_wrong", "display_unclear"]
    question_id: str | None = Field(default=None, max_length=60)


class ExplanationRequest(Strict):
    question_id: str = Field(min_length=1, max_length=60)


class MessageRequest(Strict):
    request_key: str | None = Field(default=None, min_length=16, max_length=80, pattern=r"^[A-Za-z0-9_-]+$")
    kind: Literal["help", "interest", "plan_change", "reply"]
    body: str = Field(min_length=1, max_length=1000)
    unit_id: str | None = Field(default=None, pattern=r"^[a-f0-9]{32}$")
    material_id: str | None = Field(default=None, pattern=r"^[a-f0-9]{32}$")
    day_id: str | None = Field(default=None, pattern=r"^[a-f0-9]{32}$")


class ProviderUpdate(Strict):
    expected_revision: int | None = Field(default=None, ge=1)
    provider: Literal["disabled", "openai", "openrouter", "codex"]
    model: str = Field(max_length=160)
    reasoning_effort: str = Field(default="medium", max_length=32, pattern=r"^[a-z][a-z0-9_-]{0,31}$")
    extraction_model: str = Field(default="", max_length=160)
    extraction_capability_evidence: str = Field(default="", max_length=500)
    api_key: str | None = Field(default=None, max_length=1024)
    emergency_stop: bool
    image_capable: bool
    structured_capable: bool
    capability_evidence: str = Field(default="", max_length=500)
    privacy_approved: bool = False
    privacy_evidence: str = Field(default="", max_length=500)
    openrouter_free_only: bool = True
    openrouter_require_zdr: bool = False
    reserve_micros: int = Field(ge=1000, le=10_000_000)
    input_per_million_micros: int | None = Field(default=None, ge=0, le=1_000_000_000)
    output_per_million_micros: int | None = Field(default=None, ge=0, le=1_000_000_000)
    pricing_evidence: str = Field(default="", max_length=500)
    max_output_tokens: int = Field(default=4000, ge=1000, le=8000)
    global_limit_micros: int = Field(default=10_000_000, ge=0, le=1_000_000_000)
