# Kinder-Rollentest am 19.10.2026

Tatsächlich bediente öffentliche Flutter-Web-App unter
<https://schulpilot.dorfspy.de>, Version 1.10.0+47,
Quellstand `30d032315afe49d7c5367888c2d2c155db981389`.
Chrome/Playwright mit echten Zeiger- und Tastatureingaben, eigene neue
synthetische Familie und getrennte normale Kinder-/Elternsitzungen.
Keine echten Familienmaterialien oder Antworten wurden verändert.

Der Test simuliert das Handeln eines Kindes; er ist kein Nutzertest mit einem
Kind und belegt keine pädagogische Wirksamkeit. Der Ablauf wurde nach
Unterbrechungen in derselben vorbereiteten Runde fortgesetzt. QA-Anpassungen
an Flutter-Semantik, Statusnamen und festen Aktionsleisten sind keine
festgestellten Produktfehler.

## Tatsächlich durchgespielter Ablauf

1. Eigenständiger Kinderlogin über das sichtbare Anmeldeformular. Das
   Web-Sitzungscookie ist Secure, HttpOnly und SameSite=Strict.
2. Vorbereiteten, ausdrücklich synthetischen Bruch-Hefteintrag gelesen und
   über „Stimmt, weiter“ bestätigt, ohne Prüfcheckbox. Über „Jetzt lernen“
   genau eine feste Demorunde erzeugt. Keine externe KI oder Ersatzaufgaben.
3. Runde gestartet und „Erst selbst probieren“ gewählt. Beim Addieren
   gleichnamiger Brüche bewusst die falsche Auswahl getroffen. Der gespeicherte
   Versuch wurde als falsch zurückgemeldet. Nach Browser-Reload blieb genau
   diese Rückmeldung sichtbar; keine zweite Antwort wurde erzeugt.
4. Über „Hilfe“ einen konkreten Hinweis abgerufen, anschließend richtig
   beantwortet. Dieser Erfolg bleibt als unterstützt/erneut gespeichert.
5. Bei der Bruchlücke Zähler und Nenner getrennt eingegeben, pausiert,
   neu geladen und auch nach erneuter Anmeldung denselben ungesendeten
   Entwurf wiedergefunden. Für DOM-Wertprüfungen wurde das jeweilige
   Flutter-Eingabefeld zuerst fokussiert; die sichtbaren Werte wurden
   zusätzlich per Screenshot geprüft.
6. Bruchlücke, Begriffszuordnung und kurze Fachantwort über ihre wirklichen
   Widgets beantwortet. Jede Antwort hatte eigene Rückmeldung und bewusstes
   Weitergehen. Vier Aufgaben, fünf Antwortversuche blieben erhalten.
7. Rückblick erreicht: drei selbstständige Aufgaben und eine
   unterstützte/erneut gelöste Aufgabe. Das Tagesziel war mit 27 gespeicherten
   Aktivitätssekunden von damals 20 Minuten noch offen. Die abgeschlossene
   Runde bot trotzdem einen sichtbaren Abschluss/Pausenweg.
8. Nach Elternabgleich rein lesend weitere Bereiche geöffnet: Heute bei
   320/390/1440 Pixeln, Hilfeauswahl, Glocke/In-App-Postfach, Hefte,
   Fachalbum, Wörter und Konto. Bei „Meine Fächer“ blieb genau der
   Mathematikhefter mit einer Seite; leere Fächer waren ausgeblendet.
   Der vollständige Fachstamm war ohne diesen Filter erreichbar.

Der letzte Leseumlauf erzeugte keine Lernschreibanfragen und keine weiteren
Antworten. Es gab keine Browser-Laufzeitfehler oder authentifizierten
HTTP-Fehler. Der erwartete anonyme `GET /api/auth/me` mit 401 vor dem Login
ist getrennt erfasst und kein Anwendungsfehler.

## Gemeinsamer Rollenabgleich

Der Elternagent prüfte über seine eigene normale Sitzung, während der
Kinderbrowser geschlossen war:

- gespeicherte Antwortversuche und ihre Unterstützung sichtbar;
- ungesendeter Antwortentwurf weder im Eltern-Einheitsaufruf noch in der
  Eltern-Lernsitzungsprojektion sichtbar;
- Elternlesen erzeugt keine Kinderlernzeit oder neue Antworten;
- Abschlusszahlen entsprechen den maßgeblichen gespeicherten Versuchen.

Sein abschließender Usage-Abgleich meldete null externe KI-Aufrufe,
leere Verbrauchsbelege und null reservierte Kosten. Danach änderte er nur
Vorgaben/Noten der eigenen künstlichen Familie. Die erneute Kinderansicht
zeigte das geänderte 25-Minuten-Tagesziel und weiterhin denselben
Lernstand; keine Antworten wurden umgeschrieben.

## Befunde

| Kennung | Beobachtung | Ergebnis |
| --- | --- | --- |
| CHILD-01 | Fehler, Hinweis und erneuter richtiger Versuch | Gespeichert und als unterstützt nachvollziehbar |
| CHILD-02 | Reload während ungelesener Antwort-Rückmeldung | Dieselbe Rückmeldung, keine Doppelantwort |
| CHILD-03 | Bruchentwurf nach Pause/Reload/Neuanmeldung | Sichtbar und über fokussierte Felder bestätigt |
| CHILD-04 | Alle vier Demowidgets bis Rückblick | 4 Aufgaben/5 Versuche; 3 selbstständig, 1 unterstützt/erneut |
| CHILD-05 | Mindestzeit und Rundenabschluss | Ziel offen; Runde abgeschlossen, Pause möglich |
| CHILD-06 | Elternlesen und Entwurfsprivatheit | Gemeinsamer isolierter Abgleich bestanden |
| CHILD-07 | Heftefilter und reguläres Wörtermenü | Nur nichtleerer Hefter; Album/Wörter erreichbar |
| CHILD-08 | Kleine/größere Browseransicht, Hilfe, Glocke | 320/390/1440 px; sichtgeprüfte Screenshots, kein Dokument-Querüberlauf |
| CHILD-09 | „1 gespeicherte Seiten“ auf Heute | In Build47 bestätigt, `dashboard.dart` pauschal im Plural; an Root zur Korrektur gemeldet, hier kein Nachtest eines späteren Builds behauptet |

## Grenzen

- Eine feste Demoquelle und eine Mathematikrunde wurden beantwortet.
  Es gab keine vollständige fachübergreifende Abdeckung.
- Keine neue Kameraaufnahme, kein Dateiupload, Zuschnitt oder echte OCR in
  diesem Rollenlauf. Die vorbereitete Demo wird ausdrücklich als solche gezeigt.
- Keine externe Modellanfrage; daraus folgt keine Qualitätsabnahme des
  OpenRouter-/Codex-Betriebs oder einer neuen KI-Paketgenerierung.
- Der Demohefter enthält keine neu fotografierte echte Bildseite. Öffnen
  des Albums belegt hier die Navigation, keine vollständige Foto-/Blätterabnahme.
- Kein physisches Androidgerät, kein tatsächlich beobachtetes Mikrofon,
  Tonausgabe oder Screenreader. Tastatureingabe wurde verwendet; eine
  vollständige Tastatur-/Screenreader-Konformitätsprüfung wurde nicht gemacht.
- Keine 200-%-Textskalierung in diesem Browser-Rollenlauf. Entsprechende
  Flutter-Widgetprüfungen der Hauptarbeit sind ein getrennter Nachweis.
- Keine Firebase-Zustellung oder externe Sofatutor-Medienrückkehr beobachtet.

## Reproduzierbarkeit und Übergabe

Treiber: `qa/role_child_simulation.mjs`.
Geschützte eigene Familie vorab über `qa/role_parent_prepare.py` anlegen;
`node qa/role_child_simulation.mjs` durchläuft/fortsetzt dieselbe Runde,
`node qa/role_child_simulation.mjs --read-only` prüft danach die genannten
Bereiche ohne Lernschreibzugriffe. Ein unsicher abgeschickter
Generierungsauftrag wird nicht automatisch erneut gesendet.

Bereinigtes Ergebnis: `artifacts/role-child-result.json` mit 23 erfolgreichen
Prüfungen. Geschützte synthetische Screenshots/Textbelege liegen unter
`artifacts/role-child-*`; Zugangsdaten werden weder dort ausgegeben noch
in diesen Bericht aufgenommen. Lokaler Zustand und Zugangsdaten verbleiben
in geschützten, ignorierten Dateien. Die zentrale Testfamilienbereinigung
koordiniert Root; dieser Bericht behauptet keine eigenständig ausgeführte
Bereinigung oder nachträgliche Build48-Abnahme.
