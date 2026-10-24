"""The same finite presentation contract, bound to a stable explanatory step."""
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from .subject_content import Presentation


class VisualStrict(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True, allow_inf_nan=False)


class VisualReferenceChoice(VisualStrict):
    id: str = Field(min_length=3, max_length=100, pattern=r"^[a-z][a-z0-9_.-]+$")
    version: int = Field(ge=1, le=1000, strict=True)


class ExplanationStep(VisualStrict):
    id: str = Field(min_length=1, max_length=32, pattern=r"^[A-Za-z0-9_-]+$")
    text: str = Field(min_length=1, max_length=1200)
    competence_id: str | None = Field(default=None, min_length=3, max_length=120, pattern=r"^[a-z][a-z0-9_.-]+$")
    disclosure: Literal["given", "hint1", "hint2", "hint3", "solution"]
    presentation: Presentation
    reference: VisualReferenceChoice
    source_refs: list[Annotated[str, Field(pattern=r"^[pr][1-9][0-9]?$", max_length=3)]] = Field(min_length=1, max_length=6)

    @model_validator(mode="after")
    def consistent(self):
        if len(set(self.source_refs)) != len(self.source_refs):
            raise ValueError("Doppelte Quellenreferenz im Erklärschritt.")
        if any(block.disclosure != self.disclosure for block in self.presentation.blocks):
            raise ValueError("Text und Grafik benötigen dieselbe Aufdeckstufe.")
        return self


class VisualQuestionSteps(VisualStrict):
    id: str = Field(min_length=1, max_length=60)
    explanation_steps: list[ExplanationStep] = Field(min_length=1, max_length=1)


class VisualExplanationOutput(VisualStrict):
    subject: str = Field(min_length=1, max_length=80)
    topic: str = Field(min_length=1, max_length=160)
    explanation_steps: list[ExplanationStep] = Field(min_length=1, max_length=1)
    questions: list[VisualQuestionSteps] = Field(min_length=1, max_length=8)
