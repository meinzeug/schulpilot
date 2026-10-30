"""Small server-owned selection guide for the final, already bounded schema.

This is request metadata, never a new output format or permission to make a
second model call. Detailed data/validation rules stay with the existing models.
"""

PURPOSES = {
    "decimal_sum": "Stellenwertgerechte Dezimaladdition ohne Übertrag, ausschließlich mit bestätigter Regel, geprüftem Originalbeispiel und serverseitig vorab berechneten Aufgabenparametern.",
    "lab": "Eigenes versioniertes Lehrmodell zur konstanten Kraft/Bewegung oder zu ausdrücklich kuratierten Satzumstellungen; Zusatzwissen, keine Schülerbewertung.",
    "fraction": "Bruchteile und belegte Bruchzahlen vergleichen.",
    "triangle": "Grundseite und senkrechte Höhe eines belegten Dreiecks erkennen.",
    "sentence": "Satzbausteine und ausdrücklich belegte Satzrollen unterscheiden.",
    "speech": "Aussagen in Textblasen vergleichen; keine Audioerzeugung.",
    "forms": "Belegte Formen oder Begriffspaare als beschriftete Zeilen/Tabelle vergleichen.",
    "timeline": "Belegte Daten, Zeiträume oder Jahrhundertgrenzen einordnen.",
    "picture_words": "Bis zu fünf vorhandene Bildwortsymbole verwenden; kein freier Bildgenerator.",
    "plant": "Blüte, Blatt, Stängel und Wurzel im vereinfachten Pflanzenaufbau zuordnen.",
    "heart_pump": "Einfaches Schema: Das Herz pumpt Blut durch den Körper, wenn die Quelle genau dies belegt.",
    "shadow_size": "Einfaches Modell: bei feststehender Lampe und Wand den Schatten eines Gegenstands vergleichen, wenn die Quelle den Zusammenhang ausdrücklich belegt.",
    "food_chain": "Ausdrücklich belegte Nahrung-zum-Fresser-Pfeile lesen.",
    "compass": "Belegte Himmelsrichtungen räumlich einordnen.",
    "position": "Die belegte Ballposition auf, unter oder neben dem Tisch erkennen.",
    "water_cycle": "Beschriftete Stationen des belegten Wasserkreislaufs überblicken.",
    "perspectives": "Belegte Sichtweisen vergleichen, keine eindeutige Haltung bewerten.",
    "reflection": "Belegte Reflexionswinkel am Lot vergleichen.",
    "circuit": "Einen belegten offenen oder geschlossenen Schaltplan lesen.",
    "particles": "Die belegte feste, flüssige oder gasförmige Teilchenanordnung vergleichen.",
    "filtration": "Beschriftete Teile einer belegten Filtration erkennen.",
    "bar_chart": "Belegte nichtnegative Zahlen je Kategorie vergleichen.",
    "statements": "Beschriftete belegte Aussagen gegenüberstellen.",
    "flowchart": "Start, Eingabe, Verarbeitung, Ausgabe und Ende eines belegten Ablaufs lesen.",
    "place_values": "Eine belegte Bitfolge mit ihren Stellenwerten verstehen.",
    "movement": "Beschriftete Bewegungsschritte betrachten; keine Bewegungsmessung.",
    "pattern": "Ein belegtes Muster aus Kreis, Dreieck und Quadrat vergleichen.",
    "colour_wheel": "Das belegte RYB- oder RGB-Farbsystem unterscheiden.",
    "layers": "Vordergrund, Mittelgrund und Hintergrund einordnen.",
    "mindmap": "Belegte Zweige eines Hauptthemas überblicken.",
    "flashcard": "Belegte Beschriftungen strukturieren; kein eigener Karten-Umdrehworkflow.",
    "notes": "Belegte Notenwerte in Viertelschlägen vergleichen.",
    "keyboard": "Die festen weißen Tasten C D E F G A H C zuordnen; kein Instrument.",
    "traditions": "Belegte Traditionen beschreiben, keine Überzeugung benoten.",
    "senses": "Beschriftete behandelte Sinne zuordnen.",
    "seasons": "Die vier beschrifteten Jahreszeiten in ihrer Reihenfolge überblicken.",
    "fairplay": "Beschriftete Handlungsmöglichkeiten reflektieren.",
    "gears": "Die belegte Drehrichtung gekoppelter Zahnräder verstehen.",
    "forces": "Belegtes Ziehen oder Schieben im festen Schema erkennen.",
    "money": "Belegte Eurobeträge je beschrifteter Position vergleichen.",
    "function_graph": "Ein ausdrücklich notiertes Polynom anhand seiner geprüften Koeffizienten lesen.",
    "function_curve": "Eine der acht exakt belegten Standardfunktionen statisch lesen.",
    "data_plot": "Exakte belegte Zahlenpaare als Messpunkte oder verbundene Punkte lesen.",
    "cell": "Feste beschriftete Teile eines vereinfachten Tier-/Pflanzenzellmodells erkennen.",
    "molecule": "Belegte Strukturformeln als Bindungsschema lesen, keine räumliche Molekülgeometrie.",
    "logic_table": "Die belegte UND-, ODER- oder NICHT-Operation anhand ihrer Wahrheitstafel verstehen.",
    "circuit_network": "Die ausdrücklich belegte Reihen-/Parallelschaltung von R1 und R2 lesen.",
    "technical_drawing": "Belegte Plattenmaße und mittige Bohrung in einer nicht maßstäblichen Skizze lesen.",
    "process_graph": "Ausdrücklich belegte gerichtete Schritte und Verzweigungen überblicken.",
    "process_cycle": "Eine ausdrücklich belegte geschlossene Knotenfolge überblicken.",
    "scene": "Für diese Frage eigene belegte Objekte, Zustände und Beziehungen schematisch zusammensetzen.",
    "text_probe": "Zwei bis vier vollständig im Original belegte Textreihenfolgen vergleichen; keine erfundenen Gegenbeispiele oder Grammatikurteile.",
}

ANSWER_UI = {
    "choice": "Genau eine Radioauswahl, keine Mehrfachauswahl.",
    "gap": "Freie Eingabe für genau eine Lücke, keine Inline-Dropdowns.",
    "short": "Freie kurze Eingabe; keine erfundenen Antwortregler oder Dropdowns.",
    "grouped": "Zwei bis vier beschriftete Text-/Auswahlfelder gemeinsam ausfüllen und bewusst als EINEN Versuch prüfen. Private Lösungen/Belege bleiben unsichtbar; unbekannte freie Formulierungen bleiben offen.",
    "match": "Vorhandene Zuordnungsfläche per Langdruck/Drag oder Tippen/Tastatur; Drop ändert den Entwurf, erst bewusstes Prüfen bewertet.",
}

INTERACTIONS = {
    "decimal_sum": "Stellenwerttafel mit untereinander stehenden Kommas: bewusst spaltenweise von rechts addieren, zurückgehen oder zurücksetzen. Kein Autoplay, keine Antwortbewertung durch Erkunden.",
    "heart_pump": "Zwei ausdrücklich gewählte Leseschritte zeigen Herz und Weg zum Körper; keine Kreislaufsimulation.",
    "shadow_size": "Zwei ausdrücklich gewählte Gegenstandspositionen vergleichen die Schattengröße bei fester Lampe und Wand.",
    "lab": "Nur freigegebene eigene Rezepte: physics.force_motion mit begrenzter Masse/Beschleunigung und bewusstem2s-Lauf; german.sentence_shift mit Mira-Beispiel/vier erlaubtenUmstellungen. Tippen/Tastatur/Drag/Reset; keine freienFormeln/Gruppen oder Anbieteraufrufe.",
    "function_graph": "Automatisch Erkunden ab geöffneter Hilfe/Lösung: Punkt mit x=-4..4 in 0,1-Schritten und y-Anzeige; polynomial2 numbers=[a,b,c] bleiben unverändert. Keine Koeffizientenregler.",
    "data_plot": "Automatisch Erkunden ab geöffneter Hilfe/Lösung: nur zwischen den 2..8 exakten Originalpaaren auswählen. Keine neuen Messwerte, Interpolation oder Regression.",
    "logic_table": "Automatisch Erkunden ab geöffneter Hilfe/Lösung: A/B=0 oder1 schalten und Y/Tabellenzeile hervorheben; feste UND/ODER/NICHT-Operation. Kein Schaltungseditor.",
    "process_graph": "Optionaler lokaler Knoten-Schrittplayer: gleiche Positionen und alle belegten Kanten, wechselnde Hervorhebung. Keine zusätzliche Prozesssimulation oder erfundene Zeitfolge.",
    "process_cycle": "Optionaler lokaler Knoten-Schrittplayer: gleiche Positionen und alle belegten Kanten, wechselnde Hervorhebung. Keine physikalische Simulation.",
    "scene": "Lokaler Nutzerstart für Play/Pause/Schrittwahl; Animation nur mit mindestens zwei Schritten und transition_ms>0. Ohne Bewegungsfreigabe bleiben statische Schritte; niemals Autoplay. Zustandsvergleich wählt zwei gespeicherte Schritte und benennt nur vorhandene Beschriftungs-/Platz-/Hervorhebungs-/Kantenänderungen.",
    "text_probe": "Textprobe und Gruppe per Tipp/Tastatur auswählen und vergrößert lesen, vollständigen belegten Kontext weitersehen; Reset. Keine Umordnung, Bewertung oder automatische Grammatikbehauptung.",
}

RULES = """\nDARSTELLUNGSWAHL: content_context ist der serverseitige Katalog für DIESEN Auftrag, kein neues Ausgabefeld.
Wähle je Frage anhand Lernziel und Quellen eine passende Darstellungsart aus genau dem zugehörigen Fachprofil; Text allein ist erlaubt.
Nutze die Zweckangaben für eine individuelle Darstellung statt derselben Dekoration bei jeder Aufgabe. Andere Fächer eines Pakets erweitern dieses Fachprofil nicht.
Plane benötigte Hinweis-/Lösungsgrafiken bei dieser Aufgabenerstellung in derselben presentation mit; Hinweise öffnen später gespeicherte Stufen ohne weiteren KI-Auftrag.
local_interactions beschreibt automatische App-Bedienung gültiger Blöcke, keine zusätzlichen JSON-Felder: keine controls/interactive/autoplay-Schlüssel erfinden.
Alle nicht ausdrücklich genannten Interaktionen bleiben statische Fachgrafiken mit Textalternative; keine freien Assets, 3D- oder Simulationsversprechen.
question_types und max_blocks stammen aus dem endgültigen Ausgabeschema. Feste math_tasks/practice_tasks und alle Quellen-/Offenlegungsregeln bleiben vorrangig; nicht für eine Darstellung verändern.
"""


def _nodes(value, definitions, seen=frozenset()):
    if isinstance(value, dict):
        yield value
        ref = value.get("$ref", "")
        if ref.startswith("#/$defs/"):
            name = ref.rsplit("/", 1)[-1]
            if name in definitions and name not in seen:
                yield from _nodes(definitions[name], definitions, seen | {name})
        for key, child in value.items():
            if key != "$defs":
                yield from _nodes(child, definitions, seen)
    elif isinstance(value, list):
        for child in value:
            yield from _nodes(child, definitions, seen)


def question_types(schema, node=None):
    types = set()
    for item in _nodes(schema if node is None else node, schema.get("$defs", {})):
        props = item.get("properties", {})
        if {"prompt", "answer", "options", "accepted", "type"} <= props.keys():
            types.update(props["type"].get("enum", []))
    return sorted(types)


def context(subjects, profiles, *, schema=None, compact_matching=False, symbol_words=()):
    selected = list(dict.fromkeys(subject for subject in subjects if isinstance(subject, str) and subject))
    allowed = {kind for subject in selected for kind in profiles.get(subject, ())}
    definitions = (schema or {}).get("$defs", {})
    reachable = list(_nodes(schema or {}, definitions))
    # A request may bind immutable reference-specific copies of these objects.
    # Only actually reachable fields describe the request, never unused defs.
    graphics = [item["properties"] for item in reachable if
                {"kind", "labels", "numbers", "scene", "text_probe", "lab"} <= item.get("properties", {}).keys()]
    presentations = [item["properties"] for item in reachable if
                     {"version", "evidence_kind", "blocks"} <= item.get("properties", {}).keys()]
    if schema is not None:
        allowed &= {kind for graphic in graphics for kind in graphic["kind"].get("enum", [])}
    types = question_types(schema) if schema is not None else []
    by_subject = {subject: set() for subject in selected}
    if schema is not None:
        for item in _nodes(schema, definitions):
            props = item.get("properties", {})
            if not {"subject", "questions"} <= props.keys():
                continue
            names = props["subject"].get("enum", selected)
            for subject in selected:
                if subject in names:
                    by_subject[subject].update(question_types(schema, props["questions"]))
    value = {
        "version": 1,
        "graphic_kinds": sorted(allowed),
        "scene_version": 1,
        "scene_limits": {name: definitions.get("SceneV1", {}).get("properties", {}).get(field, {}).get(bound, default)
            for name, field, bound, default in (("objects", "objects", "maxItems", 12),
                ("steps", "steps", "maxItems", 8), ("transition_ms", "transition_ms", "maximum", 800))},
        "subject_profiles": [
            {"subject": subject, "graphic_kinds": sorted(set(profiles.get(subject, ())) & allowed),
             "question_types": sorted(by_subject[subject])}
            for subject in selected
        ],
        "question_types": types,
        "answer_ui": {kind: ANSWER_UI[kind] for kind in types if kind in ANSWER_UI},
        "max_blocks": max((item["blocks"].get("maxItems", 0) for item in presentations), default=0),
        "use_for": {kind: PURPOSES[kind] for kind in sorted(allowed)},
        "local_interactions": {kind: INTERACTIONS[kind] for kind in sorted(allowed) if kind in INTERACTIONS},
    }
    if "lab" in allowed:
        from .learning_labs import RECIPES
        from .subject_content import canonical_profile

        enabled = {recipe for item in reachable if {"recipe_id", "recipe_version", "parameters"} <= item.get("properties", {}).keys()
                   for recipe in item["properties"]["recipe_id"].get("enum", [])}
        value["lab_recipes"] = {subject: [key for key, recipe in RECIPES.items() if key in enabled and canonical_profile(subject) in recipe["subjects"]]
            for subject in selected}
    if "grouped" in types:
        value["field_group"] = {"version": 1, "fields_min": 2, "fields_max": 4,
                                "source": "Jede label=answer/label:answer/label→answer-Zuordnung wörtlich in einem Originalbeleg derselben Gruppe.",
                                "answer": "Ein JSON-String mit version1 und fields-Objekt; exakt die stabilen Feld-IDs, keine Semikolontrennung."}
    if "text_probe" in allowed:
        value["text_probe"] = {"version": 1, "segments_min": 2, "segments_max": 8, "variants_min": 2, "variants_max": 4,
                               "source": "Jede vollständige Textreihenfolge in einem wörtlichen Originalbeleg; ausschließlich Hilfe/Lösung."}
    if "picture_words" in allowed:
        value["picture_word_labels"] = sorted(symbol_words)
    if compact_matching and "match" in types:
        value["matching"] = {"pairs_min": 2, "pairs_max": 4,
                             "purpose": "Belegte eindeutige Paare sinnvoll zuordnen; vorhandene Antwort-UI mit Drag-/Tipp-/Tastaturalternative, erst bewusstes Prüfen bewertet.",
                             "source": "Jedes vollständige Paar wörtlich in einem Originalmaterial derselben Gruppe; keine gegebene erklärende Grafik."}
    return value
