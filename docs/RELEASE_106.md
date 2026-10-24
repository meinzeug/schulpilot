# Release 1.32.0+106 – Klassenarbeiten und Quellenverarbeitung

Produktstand: `8659115f8648d6134937ccd5f63948581abad28f`.
Live: `20261024T131935Z-8659115`, Schema `0034`.

## Verhalten

Klassenarbeiten/LK können mit optionalem Termin, bewusst gewählten Lerntagen,
Themen und individuell eingegebener Aufgabenanzahl geplant werden. Geschriebene
Arbeiten besitzen einen eigenen privaten Foto-, Erkennungs- und Berichtigungsweg.
Originalantwort, Lehrermarkierung, KI-Hilfe und neue eigene Berichtigung bleiben
getrennt. Lesen oder Analysieren einer Arbeit erzeugt keinen Leistungsnachweis.

Schulbuddy erhält den ausgewählten Lern-/Material-/Arbeitskontext. Ein stabiler
Texteingabeschlüssel verhindert den durch Neuaufbau ausgelösten Fokusverlust
beim Öffnen der Android-Tastatur. Die Wartemeldung fordert nicht mehr zum
Schließen der Seite auf. Die Modellkonfiguration blieb dafür unverändert.

Der Tagesassistent prüft vor einem ausdrücklichen Wiederholungsversuch die
Reservierung des tatsächlich gewählten nächsten Auftrags. Gespeicherte
Erkennungstexte bleiben unabhängig vom Kostenbudget überprüfbar. Ein gescheiterter
OCR-Auftrag mit begrenzter Ausgabelänge wählt beim nächsten bewussten Versuch
die bereits freigegebene stärkere Route. Kein automatischer Providerretry.

Fertig-/Fehlermeldungen sind an Schultag, Vorbereitungsdurchlauf und Zustand
gebunden. In-App-Status funktioniert ohne Firebase. Push erfordert weiterhin
Elternfreigabe und die ausdrückliche Registrierung eines Geräts. Ein Datenbank-
oder FCM-Annahmebeleg ist keine beobachtete Zustellung.

## Nachweise

- Vollständige CI am Produkt-SHA: Run `40088116971`, erfolgreich. Backend
  2495 bestanden/35 übersprungen; Flutter 3442 bestanden/19 übersprungen;
  Analyse ohne Befund; Webrelease erfolgreich.
- Zusätzlicher frischer PostgreSQL-Fokus: 204 bestanden, keine übersprungen;
  Produkt-/Testquellen vor und nach dem Lauf hashgebunden unverändert.
- IME-Regression: Entfernen ausschließlich des Composerschlüssels lässt den
  gezielten Test scheitern; nach bytegenauer Wiederherstellung bestanden.
- Regulärer sauberer Web-/Direct-APK-/Play-AAB-Build, bestehender Signierer,
  APK-16KiB-Ausrichtung, Manifest-/Bundle-Prüfung und Geheimnisscan ohne Befund.
- Buildbeleg `ff05ad5f2d2cbdcc2f50a3c362915650`, Quellbaum
  `e54b317b4dd924cd687594f174d6c82b990f325d706085a790be6e40512f432a`.
- APK SHA256 `4091676014a6a335964aa7ce6890d087063506a9da834f449eff3c339e64a2c5`;
  AAB `5589162715611e2bef0e128dbbacd6f88a9ac7f5674d406d9354cfb775c8541c`;
  Web-JS `c3f2fc77141eca0e48a101d18bd9cda6e179649dbe0cc335a02ba9dbd07d2d7d`.
- Öffentliche APK und Webdateien entsprechen den geprüften Artefakten.
- 17 Konfigurationen unmittelbar vor Deployment gesichert und danach
  byteidentisch; bestehender Google-Inhabernachweis erhalten; API, Worker,
  Codex und beide Reparaturdienste aktiv; verschlüsseltes DB-Backup erfolgreich.
- Reparaturarchiv am Produkt-SHA geprüft, 667 Dateien, Modus 0640, SHA256
  `04f4e8de02a6ad83effd064e50ed2dc5d3676483808f13d182612854735102d1`.

Private Diagnosebelege, Logs und Artefakte liegen außerhalb der Gitquellen.
Es wurden keine Kinderantworten oder künstlichen Lernzeiten in Produktion erzeugt.

## Grenzen und weiterer Auftrag

Die Liveprüfung zeigt zusätzlich eine tatsächlich ausgeschöpfte alte
Familienkostenschranke durch unbekannte Kosten im Codex-Kontobetrieb. Diese
werden nicht als kostenlos behandelt. Release 107 ergänzt die ausdrücklich
beauftragten vorrangigen Kostenlimits je Kind und den OpenRouter-Belegabgleich.
Der Nutzer hat dafür unbegrenzte Tages-/Monatsgrenzen im konkret benannten
Kinderkonto freigegeben; diese sind in Release 106 noch nicht konfiguriert.

Ein physisches Android-Gerät war nicht verbunden. Die native Tastatur und eine
sichtbare Firebase-Zustellung sind daher keine hier behaupteten Laufzeitabnahmen.
Im betroffenen Kinderkonto existiert aktuell keine Push-Geräteregistrierung.

Nach Beginn neuer Schreibvorgänge mit den Examtabellen keinen alten 105-Stand
gegen Schema 0034 starten. Fehler vorwärts beheben; eine Wiederherstellung nur
isoliert und mit authentifiziertem Löschjournal nach vorhandener Betriebsanleitung.
