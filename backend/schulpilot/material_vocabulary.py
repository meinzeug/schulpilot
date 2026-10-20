"""Literal word pairs from a checked page, never dictionary/AI supplementation."""

import hashlib
import re
import unicodedata

from fastapi import HTTPException
from sqlalchemy import select

from .db import Family, VocabularyImport, VocabularyMembership, uid

LANGUAGES = {"latein": "la", "latin": "la", "englisch": "en", "english": "en", "französisch": "fr", "francais": "fr",
             "français": "fr", "french": "fr", "spanisch": "es", "español": "es", "spanish": "es"}
GERMAN = {"deutsch", "german", "bedeutung", "übersetzung", "translation", "meaning"}
WORD_HEADERS = {*LANGUAGES, "word", "wort", "phrase", "vokabel"}
CONTEXT_HEADERS = {"context", "kontext", "beispiel", "example", "satz", "sentence"}
POS_HEADERS = {"word class", "word type", "part of speech", "wortart", "pos"}
GRAMMAR_HEADING = re.compile(
    r"(?:#{1,6}\s*)?(?:grammar(?: rules)?|grammatik|grammaire|gramática|"
    r"simple present|simple past|present progressive|past progressive|present continuous|past continuous)[:.]?", re.I)

# Section roles, not just a handful of exact headings. A table can explicitly
# return to bilingual vocabulary after a grammar/example/diagram section.
NON_TRANSLATION = re.compile(
    r"^(?:#{1,6}\s*)?(?:grammar\b|grammatik\b|grammaire\b|gramática\b|"
    r"simple (?:past|present)\b|present (?:perfect|progressive|continuous)\b|past (?:perfect|progressive|continuous)\b|"
    r"(?:irregular|regular) verbs?\b|base form\b|past tense\b|grundform\b|infinitiv\b|verbformen?\b|(?:das )?verb\b|konjugation\b|flexion\b|"
    r"zeit(?:strahl|achse)\b|timeline\b|beispiele?\b|examples?\b|regel\b|form\s*:)", re.I)
METADATA = re.compile(
    r"\b(?:app[ -]?test|künstliche? testseite|keine echte hausaufgabe|testblatt|wasserzeichen|"
    r"copyright|alle rechte vorbehalten)\b|^\s*(?:seite|page)\s+\d+\s*$|^\s*\d{1,2}[./]\d{1,2}[./]\d{2,4}\s*$", re.I)
WORD_SECTION = re.compile(r"\b(?:vokabel\w*|vocabulary|word ?list|wortschatz|wörter|übersetzungen|translations)\b", re.I)


def pair_key(line, word, meaning):
    return hashlib.sha256(f"{line}\0{word}\0{meaning}".encode()).hexdigest()[:24]


def plain(value):
    return unicodedata.normalize("NFC", (value or "").strip().strip("*_ ")).casefold()


def preview(subject, topic, content, source_blocks=None):
    topic, content = topic or "", content or ""
    language = LANGUAGES.get(plain(subject))
    if not language and not re.search(r"\b(vokabel\w*|vocabulary|word ?list)\b", topic, re.I):
        return None
    # Preserve literal OCR roles only while their text still exactly matches.
    excluded_roles = {"inflection", "rule", "example", "diagram", "metadata"}
    excluded_text = {line.strip() for block in source_blocks or [] if block.get("purpose") in excluded_roles
                     for line in block.get("text", "").splitlines()}
    pairs, columns, unpaired, header_seen = [], None, 0, False
    word_section = not bool(NON_TRANSLATION.search(topic))
    rejected = []
    for line_number, original in enumerate(content.splitlines(), 1):
        line = re.sub(r"^\s*(?:[-*•]\s+|\d+[.)]\s+)", "", original).strip().strip("|")
        if not line or re.fullmatch(r"[\s|:—–-]+", line):
            continue
        heading = " ".join(plain(line).split())
        if original.strip() in excluded_text or METADATA.search(line):
            unpaired += 1
            rejected.append({"line": line_number, "kind": "metadata", "reason": "Seitenhinweis, kein Wortpaar."})
            continue
        if NON_TRANSLATION.search(heading):
            word_section, columns = False, None
            unpaired += 1
            rejected.append({"line": line_number, "kind": "grammar_or_example", "reason": "Grammatik oder Beispiel, keine Übersetzung."})
            continue
        section, separator, label = heading.partition(":")
        named_section = (
            separator and label.strip() and len(label) <= 80
            and not re.search(r"[=|\t]", line)
            and WORD_SECTION.fullmatch(section.strip("# :."))
        )
        if named_section or WORD_SECTION.fullmatch(heading.strip("# :.")):
            word_section, columns = True, None
            continue
        cells = re.split(r"\||\t+| {2,}|=|(?<=\s)[—–-](?=\s)|:(?=\s)", line)
        cells = [cell.strip().strip("*_ ") for cell in cells]
        headers = [plain(cell) for cell in cells]
        word_columns = [i for i, h in enumerate(headers) if h in WORD_HEADERS]
        meaning_columns = [i for i, h in enumerate(headers) if h in GERMAN]
        if len(word_columns) == len(meaning_columns) == 1:
            word_index, meaning_index = word_columns[0], meaning_columns[0]
            context_index = next((i for i, h in enumerate(headers) if h in CONTEXT_HEADERS), None)
            pos_index = next((i for i, h in enumerate(headers) if h in POS_HEADERS), None)
            recognized = {word_index, meaning_index, context_index, pos_index} - {None}
            # Never mistake an unlabelled third column (e.g. phonetics) for a meaning.
            columns = (word_index, meaning_index, context_index, pos_index) if len(recognized) == len(cells) else None
            header_seen = columns is not None
            word_section = True
            language = language or LANGUAGES.get(headers[word_index])
            continue
        if not word_section:
            unpaired += 1
            continue
        # Arrows encode form changes, time or other relations. They are not
        # translation evidence in an unlabelled diagram.
        if re.search(r"→|←|->|<-", line) and columns is None:
            unpaired += 1
            rejected.append({"line": line_number, "kind": "relation", "reason": "Pfeilbeziehung, keine bestätigte Übersetzung."})
            continue
        if len(cells) not in (2, 3, 4) or columns is None and len(cells) != 2:
            if plain(line) not in {plain(subject), plain(topic), *LANGUAGES, "vokabeln", "vocabulary"}:
                unpaired += 1
            continue
        word_index, meaning_index, context_index, pos_index = columns or (0, 1, None, None)
        if max(i for i in (word_index, meaning_index, context_index, pos_index) if i is not None) >= len(cells):
            unpaired += 1
            continue
        word, meaning = cells[word_index], cells[meaning_index]
        if not word or not any(c.isalpha() for c in word):
            unpaired += 1
            continue
        if any(len(value) > 200 or len(value.split()) > 10 for value in (word, meaning)):
            unpaired += 1
            continue
        if meaning and not any(c.isalpha() for c in meaning):
            unpaired += 1
            continue
        context = cells[context_index] if context_index is not None else ""
        part_of_speech = cells[pos_index] if pos_index is not None else ""
        if len(context) > 500 or len(part_of_speech) > 40:
            unpaired += 1
            continue
        uncertainty = ""
        if not meaning:
            uncertainty = "Die Übersetzung fehlt."
        elif any(mark in word + meaning for mark in ("?", "�", "[…]")):
            uncertainty = "Bitte die unleserliche Stelle korrigieren."
        elif plain(word) in {"bank", "bat", "light", "right", "match"} and not context:
            uncertainty = "Bitte eine konkrete Bedeutung oder einen Kontext ergänzen."
        pair = {"word": word, "meaning": meaning, "context": context, "part_of_speech": part_of_speech,
                "variants": [], "meaning_variants": [], "uncertainty": uncertainty}
        if not any(all(p[k] == pair[k] for k in pair) for p in pairs):
            pairs.append(pair | {"key": pair_key(line_number, word, meaning), "source_line": line_number,
                                 "source_text": original.strip(), "kind": "translation_candidate"})
    meanings = {}
    for pair in pairs:
        meanings.setdefault(pair["word"], set()).add(pair["meaning"])
    for pair in pairs:
        if len(meanings[pair["word"]]) > 1 and not pair["context"]:
            pair["uncertainty"] = "Mehrere Bedeutungen: Bitte den passenden Kontext ergänzen."
    # A single ambiguous assignment in prose is not automatically a word list.
    if not pairs or len(pairs) == 1 and not header_seen and not re.search(r"vokabel|vocabulary|word ?list", topic + "\n" + content, re.I):
        return None
    return {"version": 2, "language": language, "pairs": pairs, "unpaired_lines": unpaired,
            "requires_pair_confirmation": True, "excluded_lines": rejected}


def source_status(db, material):
    from .vocabulary import import_data

    rows = list(db.scalars(select(VocabularyImport).where(
        VocabularyImport.child_id == material.child_id,
        VocabularyImport.request_key.startswith("material-" + material.id + "-v" + str(material.revision) + "-"),
    ).order_by(VocabularyImport.created, VocabularyImport.id)))
    proposal = preview(material.subject, material.topic, material.content, material.source_blocks)
    confirmed_ids = {row.collection_id for row in rows if row.status == "confirmed" and row.collection_id}
    word_ids = set(db.scalars(select(VocabularyMembership.item_id).where(
        VocabularyMembership.collection_id.in_(confirmed_ids)))) if confirmed_ids else set()
    return {"confirmed_words": len(word_ids),
            "review_words": sum(len(row.pairs) for row in rows if row.status == "review"),
            "unpaired_lines": proposal["unpaired_lines"] if proposal else 0,
            "imports": [import_data(db, row) for row in rows]}


def transfer(db, principal, child, material, data):
    from . import language_tasks as s
    from . import vocabulary

    if db.get(Family, child.family_id).synthetic or material.synthetic:
        raise HTTPException(403, "Der Testraum verwendet feste Beispielinhalte.")
    if not material.confirmed or material.status != "confirmed" or data.revision != material.revision:
        raise HTTPException(409, "Bitte die aktuelle Heftseite zuerst prüfen und bestätigen.")
    proposal = preview(material.subject, material.topic, material.content, material.source_blocks)
    if not proposal:
        raise HTTPException(422, "Keine eindeutigen Wortpaare erkannt. Bitte die Wörter aus dieser Seite gesondert prüfen.")
    if proposal["language"] and data.target_locale.split("-")[0] != proposal["language"]:
        raise HTTPException(422, "Die gewählte Lernsprache passt nicht zum Fach dieser Seite.")
    fields = set(s.WordPair.model_fields)
    pairs = [s.WordPair.model_validate({k: v for k, v in pair.items() if k in fields}) for pair in proposal["pairs"]]
    if data.reverse:
        pairs = [pair.model_copy(update={"word": pair.meaning, "meaning": pair.word}) for pair in pairs]
        if any(not pair.word.strip() for pair in pairs):
            raise HTTPException(422, "Bitte fehlende Wörter zuerst klären.")
        for pair in pairs:
            if plain(pair.word) in {"bank", "bat", "light", "right", "match"} and not pair.context:
                pair.uncertainty = "Bitte die konkrete Bedeutung klären."
    if data.selections is not None:
        allowed = {pair["key"]: index for index, pair in enumerate(proposal["pairs"])}
        if len({row.key for row in data.selections}) != len(data.selections):
            raise HTTPException(422, "Bitte jedes Wortpaar nur einmal auswählen.")
        checked = []
        for row in sorted(data.selections, key=lambda row: row.key):
            if row.key not in allowed:
                raise HTTPException(409, "Die Wortvorschläge haben sich geändert. Bitte erneut prüfen.")
            pair = s.WordPair(word=row.word.strip(), meaning=row.meaning.strip(), context=row.context.strip(),
                              part_of_speech=row.part_of_speech.strip())
            if not pair.word or not pair.meaning:
                raise HTTPException(422, "Bitte Wort und Übersetzung ergänzen.")
            if plain(pair.word) in {"bank", "bat", "light", "right", "match"} and not pair.context:
                raise HTTPException(422, "Dieses Wort hat mehrere Bedeutungen. Bitte den passenden Kontext ergänzen.")
            checked.append(pair)
        pairs = checked
    else:
        # Compatibility is safe: an older client can save/read the source, but
        # its bundled page confirmation is not individual word confirmation.
        existing = db.scalar(select(VocabularyImport.id).where(
            VocabularyImport.child_id == child.id,
            VocabularyImport.request_key.startswith("material-" + material.id + "-v" + str(material.revision) + "-")))
        if existing:
            return source_status(db, material)
        for pair in pairs:
            pair.uncertainty = pair.uncertainty or "Bitte dieses Wortpaar einzeln prüfen."
    if len(pairs) > 400:
        raise HTTPException(422, "Bitte diese große Wortliste in mehrere Seiten aufteilen; es wurden keine Wörter abgeschnitten.")
    groups = ([pair for pair in pairs if not pair.uncertainty], [pair for pair in pairs if pair.uncertainty])
    for pending, group in enumerate(groups):
        for offset in range(0, len(group), 80):
            batch = group[offset:offset + 80]
            selection_digest = vocabulary.fingerprint([pair.model_dump() for pair in pairs])[:10]
            key = f"material-{material.id}-v{material.revision}-{data.target_locale}-{int(data.reverse)}-{selection_digest}-{pending}-{offset // 80}"
            value = vocabulary.fingerprint([data.model_dump(exclude={"selections"}), [pair.model_dump() for pair in batch]])
            row = db.scalar(select(VocabularyImport).where(
                VocabularyImport.child_id == child.id, VocabularyImport.request_key == key))
            if row:
                if row.request_digest != value:
                    raise HTTPException(409, "Die Wortliste hat sich geändert. Bitte die Seite erneut prüfen.")
                continue
            row = VocabularyImport(id=uid(), child_id=child.id, user_id=principal.user.id,
                session_id=principal.session.id, request_key=key, request_digest=value, target_locale=data.target_locale,
                title=(material.topic or material.title or "Meine Schulwörter")[:160], text="",
                source_revisions=[{"id": material.id, "revision": material.revision}],
                pairs=[pair.model_dump() for pair in batch], status="review")
            db.add(row)
            db.flush()
            if not pending:
                vocabulary.confirm_import_record(db, principal, child, row, s.ImportConfirm(
                    pairs=batch, target_locale=data.target_locale, language_confirmed=True))
    return source_status(db, material)
