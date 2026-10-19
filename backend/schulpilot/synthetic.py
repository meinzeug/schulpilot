"""Deterministic, explicitly synthetic fixtures, never a fallback AI provider."""

import secrets
from fractions import Fraction

from fastapi import APIRouter, Depends, HTTPException, Request, Response

from .auth import create_session
from .config import runtime_settings
from .db import Child, Family, Material, Membership, User, get_db, now
from .schemas import UnitOutput
from .security import digest, password_hash, rate_limit

CONTENT = (
    "Ein Bruch besteht aus Zähler und Nenner. Der Nenner sagt, in wie viele gleich große Teile "
    "ein Ganzes geteilt wird. Der Zähler zählt die ausgewählten Teile. "
    "Brüche mit gleichem Nenner werden addiert, indem man die Zähler addiert. "
    "Zum Kürzen teilt man Zähler und Nenner durch dieselbe Zahl. Beispiel: 2/4 = 1/2. "
    "Es sind keine Hausaufgaben notiert."
)
router = APIRouter(tags=["Synthetischer Testraum"])


def sample_material(child_id):
    return Material(
        child_id=child_id,
        title="Synthetischer Hefteintrag · Brüche",
        status="review",
        subject="Mathematik",
        topic="Brüche",
        content=CONTENT,
        uncertainties=["Bitte den vorbereiteten Beispieltext prüfen. Diese Demo führt keine echte Fotoerkennung aus."],
        homework=[],
        synthetic=True,
        confirmed=False,
    )


def sample_unit(variant=0, difficulty="normal"):
    denominator = 4 if difficulty == "too_hard" else [4, 6, 8][variant % 3]
    a, b = (1, 1) if denominator == 4 else (1, 2)
    correct = f"{a + b}/{denominator}"
    reduced = str(Fraction(a + b, denominator))
    if "/" not in reduced:
        reduced += "/1"
    data = {
        "subject": "Mathematik",
        "topic": "Brüche",
        "explanation": "Ein Ganzes kann in gleich große Teile geteilt werden. Bei 1/4 ist das Ganze in vier Teile geteilt; einer davon ist gemeint. Der Nenner steht unten, der Zähler oben. Bei gleichem Nenner addierst du die Zähler. Beim Kürzen teilst du oben und unten durch dieselbe Zahl.",
        "questions": [
            {
                "id": "sum",
                "type": "choice",
                "prompt": f"Was ergibt {a}/{denominator} + {b}/{denominator}?",
                "options": [correct, f"{a + b}/{denominator * 2}", f"{a}/{denominator * 2}"],
                "answer": correct,
                "accepted": [],
                "hints": ["Der Nenner bleibt beim Addieren gleich.", f"Addiere nur die Zähler: {a} + {b}."],
                "explanation": f"{a} + {b} = {a + b}. Der Nenner bleibt {denominator}. Das Ergebnis ist {correct}.",
            },
            {
                "id": "reduce",
                "type": "gap",
                "prompt": "Kürze 2/4 vollständig: 2/4 = __ (als Bruch)",
                "options": [],
                "answer": "1/2",
                "accepted": ["1 / 2"],
                "hints": ["Teile Zähler und Nenner durch 2."],
                "explanation": "2 geteilt durch 2 ist 1. 4 geteilt durch 2 ist 2. Daraus wird 1/2.",
            },
            {
                "id": "parts",
                "type": "match",
                "prompt": "Ordne die Begriffe ihrer Bedeutung zu.",
                "options": ["Zähler|Anzahl ausgewählter Teile", "Nenner|Anzahl aller gleich großen Teile"],
                "answer": "Anzahl ausgewählter Teile;Anzahl aller gleich großen Teile",
                "accepted": [],
                "hints": ["Der Zähler zählt die Teile, die gemeint sind."],
                "explanation": "Der Nenner beschreibt die Einteilung des Ganzen, der Zähler die ausgewählten Teile.",
            },
            {
                "id": "name",
                "type": "short",
                "prompt": "Wie heißt die Zahl unter dem Bruchstrich? Ein Wort reicht.",
                "options": [],
                "answer": "Nenner",
                "accepted": ["der Nenner"],
                "hints": ["Der Begriff beginnt mit N."],
                "explanation": "Die Zahl unter dem Bruchstrich heißt Nenner.",
            },
        ],
    }
    # Keep generated legacy fixtures in the same shape as stored legacy units:
    # absent optional presentation blocks stay absent rather than becoming null.
    return UnitOutput.model_validate(data).model_dump(exclude_none=True)


@router.post("/demo", status_code=201)
def demo(request: Request, response: Response, db=Depends(get_db)):
    if not runtime_settings().synthetic_demo:
        raise HTTPException(404, "Testraum deaktiviert.")
    rate_limit(db, "demo:" + digest(request.client.host), 5, 3600)
    rate_limit(db, "demo-global", 100, 3600)
    suffix = secrets.token_hex(5)
    parent_password = secrets.token_urlsafe(18)
    child_password = secrets.token_urlsafe(18)
    parent = User(
        username="eltern-" + suffix,
        display_name="Demo-Elternteil",
        role="parent",
        verified=True,
        password_hash=password_hash(parent_password),
    )
    child_user = User(
        username="kind-" + suffix,
        display_name="Mika (Beispiel)",
        role="child",
        verified=True,
        password_hash=password_hash(child_password),
    )
    family = Family(name="Meine Testfamilie", synthetic=True, expires=int(now()) + 86400)
    db.add_all([parent, child_user, family])
    db.flush()
    child = Child(
        user_id=child_user.id,
        family_id=family.id,
        grade=6,
        subjects=["Mathematik", "Deutsch", "Englisch"],
        preferences={"weekdays": [0, 1, 2, 3, 4, 5, 6]},
    )
    db.add(child)
    db.flush()
    db.add(Membership(user_id=parent.id, family_id=family.id, permission="owner"))
    material = sample_material(child.id)
    db.add(material)
    db.commit()
    result = create_session(db, parent, response, request, "Synthetischer Testzugang")
    return {
        **result,
        "credentials": {
            "parent_username": parent.username,
            "parent_password": parent_password,
            "child_username": child_user.username,
            "child_password": child_password,
        },
        "child_id": child.id,
        "material_id": material.id,
        "notice": "Synthetischer Testraum, 24 Stunden gültig. Keine echte Bilderkennung, keine externe KI, keine echten Kinderdaten eingeben. Zugangsdaten werden nur jetzt angezeigt.",
    }
