"""Versioned, explicit language targets; no changes to factual/math schemas."""

from typing import Literal

from pydantic import Field, model_validator

from .schemas import Strict

Locale = Literal["en-GB", "en-US", "fr-FR", "es-ES", "de-DE"]
TargetLocale = Literal["en-GB", "en-US", "fr-FR", "es-ES"]
TARGETS = {"en-GB": "Englisch · Großbritannien", "en-US": "Englisch · USA",
           "fr-FR": "Französisch · Frankreich", "es-ES": "Spanisch · Spanien"}
SKILLS = {"recognition", "recall", "spelling", "listening", "sentence", "grammar", "writing"}


class EvaluationPolicy(Strict):
    version: Literal[1] = 1
    case_sensitive: bool = True
    apostrophe_equivalent: bool = False
    terminal_punctuation_optional: bool = False
    closed_answers: bool = True
    criterion: Literal["meaning", "spelling", "grammar", "sentence", "listening"]


class LanguageTask(Strict):
    version: Literal[1] = 1
    ui_locale: Literal["de-DE"] = "de-DE"
    instruction_locale: Literal["de-DE"] = "de-DE"
    target_locale: TargetLocale
    answer_locale: Locale
    task_kind: Literal["meaning_choice", "recall", "spelling", "listening", "context_gap", "sentence_order", "grammar", "free_sentence"]
    skill: Literal["recognition", "recall", "spelling", "listening", "sentence", "grammar", "writing"]
    direction: Literal["target_to_de", "de_to_target", "target_to_target"]
    vocabulary_item_id: str = Field(pattern=r"^[a-f0-9]{32}$")
    vocabulary_revision: int = Field(ge=1)
    source_revisions: list[dict] = Field(default_factory=list)
    evaluation_policy: EvaluationPolicy
    stimulus: str = Field(default="", max_length=600)
    cue: str = Field(default="", max_length=600)
    cue_locale: Locale = "de-DE"
    context: str = Field(default="", max_length=500)
    word_bank: list[str] = Field(default_factory=list, max_length=25)
    generated_example: bool = False
    grammar_topic: Literal["", "simple_present", "simple_past", "progressive"] = ""

    @model_validator(mode="after")
    def coherent(self):
        if self.target_locale not in TARGETS:
            raise ValueError("Bitte eine ausdrücklich unterstützte Lernsprache wählen.")
        expected = "de-DE" if self.direction == "target_to_de" else self.target_locale
        if self.answer_locale != expected:
            raise ValueError("Antwortsprache und Abrufrichtung widersprechen sich.")
        kinds = {"meaning_choice": "recognition", "recall": "recall", "spelling": "spelling",
                 "listening": "listening", "sentence_order": "sentence", "grammar": "grammar", "free_sentence": "writing"}
        if self.task_kind in kinds and kinds[self.task_kind] != self.skill:
            raise ValueError("Aufgabenziel und Fähigkeit widersprechen sich.")
        if bool(self.stimulus) != (self.task_kind == "listening"):
            raise ValueError("Nur Hörübungen erhalten einen erforderlichen Hörstimulus.")
        if self.task_kind == "free_sentence" and self.evaluation_policy.closed_answers:
            raise ValueError("Freie Sätze benötigen eine offene Bewertung.")
        return self


class WordPair(Strict):
    word: str = Field(min_length=1, max_length=200)
    meaning: str = Field(default="", max_length=200)
    context: str = Field(default="", max_length=500)
    part_of_speech: str = Field(default="", max_length=40)
    variants: list[str] = Field(default_factory=list, max_length=8)
    meaning_variants: list[str] = Field(default_factory=list, max_length=8)
    uncertainty: str = Field(default="", max_length=500)


class VocabularyOutput(Strict):
    pairs: list[WordPair] = Field(min_length=1, max_length=80)


class ImportRequest(Strict):
    target_locale: TargetLocale
    title: str = Field(min_length=1, max_length=160)
    material_id: str | None = Field(default=None, max_length=32)
    text: str = Field(default="", max_length=24000)
    pairs: list[WordPair] = Field(default_factory=list, max_length=80)
    language_confirmed: Literal[True]

    @model_validator(mode="after")
    def source(self):
        if self.target_locale not in TARGETS or sum((bool(self.material_id), bool(self.text.strip()), bool(self.pairs))) != 1:
            raise ValueError("Eine Lernsprache und genau eine Quelle wählen: Heftseite, Text oder eigene Wortpaare.")
        return self


class ImportConfirm(Strict):
    pairs: list[WordPair] = Field(min_length=1, max_length=80)
    target_locale: TargetLocale
    language_confirmed: Literal[True]


class ItemUpdate(WordPair):
    revision: int = Field(ge=1)
    confirmed: Literal[True]


class RoundRequest(Strict):
    target_locale: TargetLocale
    collection_id: str | None = Field(default=None, max_length=32)
    direction: Literal["target_to_de", "de_to_target"] = "de_to_target"
    skill: Literal["recognition", "recall", "spelling", "listening"] = "spelling"
    count: int = Field(default=3, ge=2, le=5)
    voluntary: bool = False


class StimulusRequest(Strict):
    kind: Literal["listen", "solution", "word_bank", "speech_input"]


ProjectMode = Literal["context_gap", "sentence_order", "grammar", "dialog", "exam", "writing_feedback", "model_text",
                      "writing_help", "simplify", "presentation", "speech", "study_notes", "worksheet",
                      "topic_practice", "debate", "translation", "summary", "email"]


class ProjectRequest(Strict):
    target_locale: TargetLocale
    mode: ProjectMode
    item_ids: list[str] = Field(min_length=1, max_length=10)
    material_id: str | None = Field(default=None, max_length=32)
    goal: str = Field(min_length=3, max_length=500)
    draft: str = Field(default="", max_length=4000)
    grammar_topic: Literal["", "simple_present", "simple_past", "progressive"] = ""
    grammar_confirmed: bool = False
    previous_id: str | None = Field(default=None, max_length=32)
    language_confirmed: Literal[True]


class LanguageGeneratedQuestion(Strict):
    id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,60}$")
    type: Literal["choice", "short", "gap"]
    task_kind: Literal["context_gap", "sentence_order", "grammar", "free_sentence"]
    vocabulary_item_id: str = Field(pattern=r"^[a-f0-9]{32}$")
    prompt: str = Field(min_length=1, max_length=700)
    cue: str = Field(default="", max_length=600)
    cue_locale: Locale = "de-DE"
    source_excerpt: str = Field(min_length=1, max_length=600)
    options: list[str] = Field(default_factory=list, max_length=6)
    answer: str = Field(min_length=1, max_length=500)
    accepted: list[str] = Field(default_factory=list, max_length=8)
    hints: list[str] = Field(min_length=1, max_length=3)
    explanation: str = Field(min_length=1, max_length=1500)

    @model_validator(mode="after")
    def answers(self):
        if self.type == "choice" and (len(set(self.options)) < 2 or self.answer not in self.options or len(self.options) != len(set(self.options))):
            raise ValueError("Auswahlaufgaben benötigen eindeutige Optionen und genau einen vorhandenen Lösungstext.")
        if self.type != "choice" and self.options:
            raise ValueError("Freie Eingaben haben keine Auswahloptionen.")
        if self.type == "choice" and self.accepted:
            raise ValueError("Auswahlfragen erlauben keine zusätzlichen richtigen Optionen.")
        if self.task_kind == "sentence_order" and self.type != "short":
            raise ValueError("Satzbausteine benötigen eine kurze Texteingabe.")
        if self.type == "gap" and len(self.answer) > 200:
            raise ValueError("Eine Lückenantwort muss in das Eingabefeld passen.")
        return self


class LanguageProjectOutput(Strict):
    title: str = Field(min_length=1, max_length=160)
    explanation: str = Field(min_length=1, max_length=4000)
    response: str = Field(min_length=1, max_length=6000)
    response_locale: Locale
    source_excerpt: str = Field(min_length=1, max_length=600)
    criteria: list["WritingCriterion"] = Field(default_factory=list, max_length=5)
    questions: list[LanguageGeneratedQuestion] = Field(min_length=2, max_length=5)

    @model_validator(mode="after")
    def unique(self):
        if len({q.id for q in self.questions}) != len(self.questions):
            raise ValueError("Aufgaben-IDs müssen eindeutig sein.")
        if len({(q.prompt.strip(), q.cue.strip()) for q in self.questions}) != len(self.questions):
            raise ValueError("Eine Runde darf nicht dieselbe Frage mehrfach enthalten.")
        return self


class WritingCriterion(Strict):
    criterion: Literal["content", "clarity", "structure", "word_choice", "grammar"]
    draft_quote: str = Field(default="", max_length=400)
    observation: str = Field(min_length=1, max_length=500)
    suggestion: str = Field(min_length=1, max_length=500)


LanguageProjectOutput.model_rebuild()


def public_metadata(raw):
    result = LanguageTask.model_validate(raw).model_dump()
    # Exact answers, accepted variants and private matching rules stay server-side.
    result.pop("evaluation_policy")
    return result
