"""Closed, content-free validation diagnostics; never changes provider billing.

Known local validator messages are matched exactly in memory to public tags.
No message, input, context, model title or arbitrary error type is retained.
This is diagnostic metadata only, never a repair or an acceptance decision.
"""
from pydantic import ValidationError

_FIELDS = frozenset("""
units questions id type prompt options answer accepted hints explanation group_id subject topic content
uncertainties homework legibility explanation_steps competence_id disclosure presentation version evidence_kind
blocks kind title source_excerpt labels numbers connections marks unit variant scene text_probe lab
objects layout steps transition_ms caption placements object_id slot highlight edges start end label shape tone
index role segments text variants order parameters mass_kg acceleration_m_s2 example_id recipe_id recipe_version
reference source_refs field_group fields answer_ui value position
""".split())
_REASONS = {
    "Value error, Eine Literalannotation benötigt den unveränderten Wortlaut dieses Blocks.": "ocr_mark_quote",
    "Value error, Urheberschaft benötigt einen ausdrücklich sichtbaren Beleg; Farbe allein reicht nicht.": "ocr_author_evidence",
    "Value error, Eine Farbe oder ein Name belegt keine sichtbare Urheberrolle.": "ocr_author_role",

    "Value error, Lernszene benötigt Szenendaten und Textalternative, keine fachfremden Grafikparameter.": "scene_parameters",
    "Value error, Szenendaten gehören ausschließlich zu kind scene.": "scene_kind",
    "Value error, Bruchmodell braucht Zähler und positiven Nenner bis24.": "fraction_bounds",
    "Value error, Textproben benötigen eine geöffnete Hilfe/Lösung und ausschließlich Textprobenparameter.": "text_probe_parameters",
    "Value error, Textprobendaten gehören ausschließlich zu kind text_probe.": "text_probe_parameters",
    "Value error, Eigenes Lernlabor benötigt ausschließlich Rezeptparameter und eine Textalternative.": "lab_parameters",
    "Value error, Labordaten gehören ausschließlich zu kind lab.": "lab_parameters",
    "Value error, Parameter gehören nicht zum gewählten eigenen Laborrezept.": "lab_parameters",
}


_PHASES = frozenset("""
json envelope transport prepared_graphics source choice schema part_bounds normalization controller catalog extract exam_bounds
subject practice counts factual coaching entry asset visual billing
""".split())
_VALUE_REASONS = {
    "Grafiktransport entspricht nicht dem gebundenen Anfrageformat.": "graphic_pair_transport",
    "Grafiktransport: ungültige Tabelle.": "graphic_table_catalog",
    "Grafiktransport: ungültiger Eintrag.": "graphic_table_row",
    "Grafiktransport: doppelte Kennung.": "graphic_table_duplicate",
    "Grafiktransport: unbekannter Verweis.": "graphic_table_reference",
    "Grafiktransport: mehrfach verwendeter Verweis.": "graphic_table_reused",
    "Grafiktransport: nicht verwendeter Eintrag.": "graphic_table_unused",
    "Satzmarkierung hat keinen eindeutigen Rollenbeleg.": "sentence_role_evidence",
    "Der Originalfokus benötigt eine unveränderte vollständige Original-Liste ohne erfundene Beziehungen.": "original_focus_shape",
    "Der Originalfokus benötigt den exakt bestätigten Quellenbeleg.": "original_focus_source",
    "Die Originalfokus-Frage benötigt dieselben Originaloptionen ohne Antwort im Prompt.": "original_focus_question",
    "Ungültige vorbereitete Grafikzuordnung.": "prepared_graphic_binding",
    "Ungültige Struktur der vorbereiteten Grafikzuordnung.": "prepared_graphic_structure",
    "Unbekannte vorbereitete Grafik-ID.": "prepared_graphic_id",
    "Vorbereitete Grafik gehört nicht zum Fach oder zur Paketgruppe.": "prepared_graphic_scope",
    "Vorbereitete Grafikmetadaten stimmen nicht mit der Auswahl überein.": "prepared_graphic_metadata",
    "Vorbereitete Grafik gehört nicht zur erlaubten Aufdeckstufe.": "prepared_graphic_disclosure",
    "Vorbereitete Grafik passt nicht zu den ausdrücklichen Frageparametern.": "prepared_graphic_question_anchor",
    "Ein Lernpaketteil benötigt genau ein Fach.": "part_structure",
    "Der Lernpaketteil überschreitet den begrenzten Umfang.": "part_bounds",
    "Die Aufgabe überschreitet den begrenzten Ausgabeumfang.": "part_bounds",
    "Eine Aufgabe enthält eine stark wiederholte Formulierung.": "part_repeated_words",
    "Eine Aufgabenstellung verweist auf eine Lösungsgrafik.": "part_solution_in_prompt",
    "Ein Erklärabschnitt benötigt genau einen vollständigen Grafikschritt.": "part_step_count",
    "Der Grafikschritt überschreitet den begrenzten Umfang.": "part_bounds",
    "Die Lernszene benötigt zwei überschaubare vollständige Phasen.": "part_scene_bounds",
    "Grafik passt nicht zur gewählten Referenz.": "visual_reference",
    "Laborparameter passen nicht zur gewählten Referenz.": "lab_parameters",
    "Die Lernszene braucht belegte Beziehungen und mindestens zwei Phasen.": "visual_scene_relations",
    "Unveränderte Wortkästen sind keine fachliche Phasenvisualisierung.": "visual_scene_phases",
    "Jeder neue Erklärabschnitt benötigt passende Grafikschritte.": "visual_steps_required",
    "Zu viele Erklärschritte.": "visual_step_count",
    "Doppelte Erklärungsschritt-ID.": "visual_step_id",
    "Der Erklärtext enthält eine falsche rationale Gleichung.": "visual_math",
    "Erklärschritt verwendet keine freigegebene Kompetenz-ID.": "visual_competence",
    "Einführungen dürfen keine versteckte Aufgabenlösung enthalten.": "visual_disclosure",
    "Frageerklärungen öffnen erst über Hinweis oder Lösung.": "visual_disclosure",
    "Erklärung verweist auf fremde oder veraltete Quellen.": "visual_sources",
    "Referenz gehört nicht zum freigegebenen Fach und Auftrag.": "visual_reference",
    "Die gewählte Referenzversion existiert nicht.": "visual_reference",
    "Erklärgrafiken ohne freigegebene Referenz und Quelle sind nicht zulässig.": "visual_sources",
    "Erklärtext und Spiegelgrafik verwenden verschiedene Winkel.": "visual_reflection_parameters",
    "Erklärtext und Dreieckgrafik verwenden verschiedene Grundseiten oder Höhen.": "visual_triangle_parameters",
    "Erklärtext und Bruchgrafik verwenden verschiedene Brüche.": "visual_fraction_parameters",
    "Grafik gehört nicht zum ausgewählten Fachprofil.": "subject_profile",
    "Grafik ohne wörtlichen Quellenbeleg.": "source_excerpt",
    "Grafikzahl fehlt im Beleg oder in der Aufgabe.": "number_evidence",
    "Grafikbeschriftung fehlt im wörtlichen Beleg.": "label_evidence",
    "Der Originalvergleich benötigt zwei bis vier unterschiedliche kurze Originalausdrücke ohne Zusatzparameter.": "original_comparison_shape",
    "Jeder Vergleichsausdruck muss vollständig und wortgetreu im Originalbeleg stehen.": "original_comparison_label",
    "Der Originalvergleich benötigt einen bestätigten Originalbeleg statt eines erzeugten Aufgabenbeispiels.": "original_comparison_source",
    "Die Frage muss mindestens einen vollständigen Originalausdruck ihres Vergleichs nennen.": "original_comparison_question",
    "Gegebene Grafik verrät die Antwort.": "subject_disclosure",
    "Gegebene Grafik darf kein richtiges Zuordnungspaar vorwegnehmen.": "subject_disclosure",
    "Fach oder Umfang des Lernstarts wurde verändert.": "entry_contract",
    "Der begrenzte Lernstart wurde nicht vollständig übernommen.": "entry_contract",
    "Eine geprüfte Voraussetzung wurde verändert.": "entry_probe_changed",
    "Die kurze Lernprobe benötigt ein einzelnes Antwortformat.": "entry_format",
    "Unknown catalog subject identity": "catalog_assignment",
    "Unknown catalog context reference": "catalog_assignment",
    "Catalog topic is outside its subject/candidate list": "catalog_assignment",
    "Unknown unmatched context reference": "catalog_assignment",
    "Output subject is not a selected existing subject": "catalog_assignment",
}


_SCENE_REASONS = {
    "Lernszenen enthalten nur Beschriftungen, keine Links, Markup oder ausführbaren Code.": "scene_text",
    "Szenenpfeile verbinden verschiedene Objekte.": "scene_edges",
    "Szenenobjekte und Plätze dürfen pro Schritt nicht doppelt vorkommen.": "scene_placements",
    "Doppelte Hervorhebung in der Lernszene.": "scene_highlights",
    "Doppelte Pfeile in der Lernszene.": "scene_edges",
    "Szenenversion muss die ganze Zahl1 sein.": "scene_version",
    "Szenenobjekte benötigen eindeutige IDs.": "scene_object_ids",
    "Jeder Szenenschritt platziert alle Objekte genau einmal.": "scene_placements",
    "Szenenschritt verweist auf ein unbekanntes Objekt.": "scene_object_reference",
    "Szenenbeschriftung fehlt im wörtlichen Beleg.": "scene_label_evidence",
    "Szenenschritt ohne wörtlichen Quellenbeleg.": "scene_source_excerpt",
    "Die Szenenbeschreibung muss im Schrittbeleg stehen.": "scene_caption_evidence",
    "Szenenpfeile brauchen bestätigten Quellenstoff.": "scene_source_evidence",
    "Szenenpfeil hat keine belegte Richtung zwischen seinen Beschriftungen.": "scene_arrow_evidence",
    "Pfeilbeschriftung fehlt im Schrittbeleg.": "scene_edge_label_evidence",
    "Eine gegebene Lernszene darf kein richtiges Zuordnungspaar räumlich vorwegnehmen.": "scene_answer_disclosure",
    "Gegebene Lernszene verrät die Antwort in einem ihrer Schritte.": "scene_answer_disclosure",
}
_VALUE_REASONS.update(_SCENE_REASONS)
_REASONS.update({"Value error, " + message: reason for message, reason in _SCENE_REASONS.items()})


def _location(value):
    if not isinstance(value, (tuple, list)):
        return "field"
    parts = [str(item) if type(item) is int and 0 <= item <= 99999 else item
             if isinstance(item, str) and item in _FIELDS else "field" for item in value[:16]]
    while len(".".join(parts)) > 200:
        parts.pop()
    return ".".join(parts) or "field"


def annotate(result, error, *, phase=None):
    """Add <=3 closed diagnostics without changing a financial receipt.

    Non-Pydantic errors require an explicit closed validation phase. Only exact
    built-in ValueError arguments are compared to fixed local literals in RAM;
    no exception rendering, unknown keys, context or traceback is retained.
    """
    pydantic = isinstance(error, ValidationError)
    if result is None or not (pydantic or (
            phase is not None and isinstance(error, (ValueError, KeyError, IndexError, TypeError)))):
        return result
    telemetry = result.telemetry
    if telemetry is not None and not isinstance(telemetry, dict):
        return result
    if pydantic:
        entries = error.errors(include_input=False, include_context=False, include_url=False)
        diagnostics = [{"location": _location(item.get("loc")),
                        "reason": _REASONS.get(item.get("msg"), "schema_validation")} for item in entries[:3]]
    else:
        reason = "schema_validation"
        if type(error) is ValueError and len(error.args) == 1 and type(error.args[0]) is str:
            reason = _VALUE_REASONS.get(error.args[0], reason)
        elif isinstance(error, KeyError):
            reason = "missing_field"
        elif isinstance(error, IndexError):
            reason = "invalid_index"
        elif isinstance(error, TypeError):
            reason = "invalid_type"
        diagnostics = [{"location": "field", "reason": reason}]
    validation = {"version": 1, "errors": diagnostics}
    if phase is not None:
        validation["phase"] = phase if type(phase) is str and phase in _PHASES else "schema"
    result.telemetry = {**(telemetry or {}), "validation": validation}
    return result
