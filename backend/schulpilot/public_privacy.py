"""Accessible privacy document, readable without Flutter or JavaScript."""

from html import escape

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from .config import runtime_settings

router = APIRouter()
PARAGRAPHS = (
    ("Verantwortlicher und Kontakt", None),
    (
        "Wofür SCHULPILOT Daten verarbeitet",
        "SCHULPILOT begleitet Familien beim Lernen. Wir speichern Elternzugänge, zugeordnete Kinderzugänge, "
        "notwendige Lernvorgaben und die innerhalb der App ausgeführten Aktivitäten. Kinder benötigen keine eigene E-Mail-Adresse. "
        "Eltern sehen ausschließlich in ihrer berechtigten Familie Materialien, Aufgaben, Antworten, Hinweise, Erklärungen, "
        "Hilfewünsche und die näherungsweise aktive Lernzeit. Eltern können freiwillig Schulnoten mit Fach, Datum und optionaler "
        "Notiz verwalten und deren Gewichtung im Lernplan ausschalten. Die gespeicherten Noten und Notennotizen werden "
        "nicht automatisch an die Lern-KI übermittelt; nur eine abgeleitete Unterstützungsstrategie wird ergänzt. "
        "Andere Apps, fremde Webseiten und das übrige Gerät werden nicht überwacht. "
        "Es gibt keine Werbung, keinen Verkauf von Kinderprofilen und keine gemeinsame Inhaltsbibliothek aus privaten Materialien.",
    ),
    (
        "Grundlagen und freiwillige Funktionen",
        "Die für den angeforderten Lernzugang erforderlichen Konto- und Familiendaten werden zur Bereitstellung der "
        "vereinbarten Leistung verarbeitet. Eltern richten die Kinderzugänge ein. Optionale Google-Anmeldung und "
        "Gerätebenachrichtigungen sind freiwillig; ohne sie bleiben die normalen Zugänge und der Lernraum nutzbar. "
        "Einwilligungen können für die Zukunft widerrufen werden. Sicherheits- und Missbrauchsschutz dient dem Schutz der "
        "Zugänge. Gesetzlich aufzubewahrende Zahlungsbelege werden getrennt vom Lernverlauf behandelt.",
    ),
    (
        "Anmeldung mit Google – ausschließlich für Eltern",
        "Erst wenn ein Elternteil bewusst die Google-Anmeldung startet, wird die Google-Anmeldeseite geöffnet. "
        "Über OpenID Connect prüfen wir eine von Google bestätigte E-Mail-Adresse und eine eindeutige Google-Kontokennung. "
        "Diese Daten dienen ausschließlich der Anmeldung und ausdrücklichen Verknüpfung mit dem eigenen Elternkonto. "
        "Wir fordern nur openid und email an, keinen Zugriff auf Gmail, Kontakte, Kalender oder Drive. Google-Passwörter, "
        "Zugriffs- und Erneuerungstokens werden nicht gespeichert. Gleiche E-Mail-Adressen führen nicht automatisch Konten zusammen. "
        "Bestehende Elternkonten bestätigen eine Verknüpfung mit ihrem bisherigen Passwort. Die Verknüpfung lässt sich unter "
        "Zugänge & Einstellungen trennen und wird bei Kontolöschung entfernt. Kinder verwenden ihre unabhängigen "
        "SCHULPILOT-Zugänge ohne Google. Unvollständige Anmeldevorgänge sind zehn Minuten gültig und werden spätestens "
        "beim nächsten täglichen Bereinigungslauf entfernt. Firebase Authentication wird nicht eingesetzt.",
    ),
    (
        "Materialien und KI-Lernbegleitung",
        "Fotos können vor dem Upload gedreht und zugeschnitten werden. Ausstehende zugeschnittene Fotos lassen sich auf "
        "dem eigenen Gerät für höchstens 24 Stunden fortsetzen (maximal acht Seiten und drei MB); Abmelden oder Entfernen "
        "löscht diese lokale Warteschlange. Der Server entfernt Bildmetadaten. Persönliche Angaben im Bild müssen vor dem "
        "Upload zugeschnitten werden. Private Bilder sind ausschließlich nach Anmeldung und Berechtigungsprüfung abrufbar. "
        "Für die freigegebene KI-Verarbeitung wird OpenRouter mit kostenlosen, technisch geprüften Modellen und festem "
        "Upstream verwendet; der konkret verwendete Anbieter wird am Lerninhalt angezeigt. Namen, Passwörter und Familienkennungen "
        "werden dafür nicht benötigt. Verarbeitet werden bestätigte Unterrichtsinhalte und bei der Lernbegleitung Aufgaben, "
        "Antworten, Fehlversuche und Hinweise. Die Anbieterwahl erfolgt serverseitig; es gibt keine heimlichen Providerwechsel. "
        "Die zusätzliche Zero-Data-Retention-Anforderung ist im beauftragten Free-Standard nicht aktiviert. Eine vollständige "
        "Löschung bei allen beteiligten Anbietern allein aufgrund einer API-Einstellung wird nicht behauptet. "
        "Der öffentliche Testraum verwendet ausschließlich künstliche Daten und wird nach 24 Stunden gelöscht.",
    ),
    (
        "Freiwillige Benachrichtigungen über Firebase Cloud Messaging",
        "Firebase wird ausschließlich für Push eingesetzt. Erst beim bewussten Einschalten auf einem angemeldeten Gerät "
        "wird Firebase initialisiert und die Geräteberechtigung angefragt. Bei Kinderzugängen ist zuvor eine zusätzliche "
        "Freigabe durch die Eltern nötig. Google erhält Installations- und Gerätetokens sowie technische Verbindungsdaten; "
        "Namen, Lerninhalte, Noten, Antworten und Familienkennungen werden nicht als Nachrichteninhalt gesendet. "
        "Benachrichtigungen lauten neutral und öffnen den geschützten Lernraum. Analytics, Werbung, Firestore, Firebase Storage "
        "und Crashlytics werden nicht verwendet. Die Verarbeitung durch Google ist nicht auf Deutschland oder die EU beschränkt. "
        "Ausschalten, Abmelden, Sitzungswiderruf und Rechteentzug sperren weiteren Versand im Backend. Ein bereits vom "
        "Gerätedienst angenommener Hinweis kann noch kurz nachlaufen (höchstens 60 Sekunden Gültigkeit). Ruhezeiten und "
        "Benachrichtigungswünsche werden beachtet. Ohne geeignete Google Play Services ist Android-Push nicht zugesichert. "
        "Gerätetokens liegen verschlüsselt in der Datenbank, werden bei Abmeldung oder Entzug entfernt und nach 60 Tagen "
        "ohne Aktualisierung bereinigt; Versandstatus nach 14 Tagen. Das Löschen eines Tokens ist keine Zusage sofortiger "
        "Löschung sämtlicher Firebase-Installationsdaten oder Google-Backups.",
    ),
    (
        "Speicherung, Sicherheit und Aufbewahrung",
        "Konto-, Lern- und Familiendaten liegen in der eigenen Datenbank auf dem SCHULPILOT-Server bei Hetzner. "
        "Private Materialien und Datenbank sind nicht öffentlich zugänglich. Sitzungen sind widerrufbar und Passwörter "
        "werden mit Argon2id gehasht. Materialien, Aufgaben, Antworten, Aktivitäten, Heftfragen, Schulnoteneinträge und Nachrichten werden höchstens "
        "365 Tage gespeichert; technische Aufträge 30 Tage; abgelaufene Zugangstokens und Sitzungen weitere sieben Tage; "
        "tägliche Backups 14 Tage. Backups werden vor einer Wiederherstellung mit zwischenzeitlichen Löschungen abgeglichen. "
        "Technische Betriebsprotokolle enthalten keine Fotos, vollständigen Kinderantworten oder Zugangsdaten.",
    ),
    (
        "Fragen zum Heft und freiwillige Sprachfunktionen",
        "Heftfragen, Antworten und Quellenbelege gehören zum privaten Lernverlauf und sind für berechtigte Eltern sichtbar. "
        "Die freigegebene Lern-KI erhält die Frage, bestätigte Hefttexte und bei einer Nachfrage wenige vorherige Antworten. "
        "Mikrofon und Vorlesen starten ausschließlich auf Wunsch. Spracheingabe verwendet den Sprachdienst des Geräts "
        "oder Browsers, der Sprache auch online verarbeiten kann. Ein Hinweis erscheint vor der Aufnahme. SCHULPILOT "
        "speichert keine Audiodateien und lädt selbst keine Audiodateien hoch. Der erkannte Text ist vor dem Senden "
        "bearbeitbar. Auch Vorlesestimmen können einen Gerätedienst verwenden; eine Offlineverarbeitung ist nicht "
        "auf jedem Gerät verfügbar. Tippen und Lesen bleiben ohne diese Funktionen möglich.",
    ),
    (
        "Bestellungen und Überweisungen",
        "Bei einer Bestellung werden Tarif, Gesamtpreis, Vertragsfassung und Zahlungszuordnung gespeichert. "
        "Eine Freischaltung erfolgt nach manueller Prüfung einer tatsächlich eingegangenen Überweisung. Die App liest "
        "keine Bankkonten aus. Zahlungsbelege bleiben acht Jahre nach Ende des Buchungsjahres erhalten; bei Kontolöschung "
        "wird die Kontozuordnung entfernt. Sie enthalten keine Kinderantworten oder Lernmaterialien.",
    ),
    (
        "Auskunft, Export, Berichtigung und Löschung",
        "Eltern können Kinderangaben berichtigen und unter Zugänge & Einstellungen einen Familienexport mit Materialien "
        "und Lernverlauf anfordern sowie Kinderkonten und das eigene Elternkonto löschen. Beim Löschen des "
        "Familieninhabers wird die gesamte Familie gelöscht; eingeladene Eltern verlieren den Zugriff. Eine Kontolöschung "
        "ist auch über die öffentliche Web-App ohne installierte Android-App möglich. Betroffene können sich über den "
        "oben angegebenen Kontakt an den Betreiber wenden, Einwilligungen widerrufen und sich bei einer zuständigen "
        "Datenschutzaufsichtsbehörde beschweren. Gesetzlich erforderliche Aufbewahrung bleibt bestehen.",
    ),
)


@router.get("/legal/privacy", response_class=HTMLResponse)
def privacy():
    site = runtime_settings()
    contact = "\n".join(x for x in (site.operator_name, site.operator_address, site.operator_support_email) if x)
    if not (site.operator_name and site.operator_address and site.operator_support_email):
        contact = (
            contact
            + "\nBetreiber- und Kontaktangaben sind noch unvollständig und müssen vor dem öffentlichen Verkauf ergänzt werden."
        ).strip()
    sections = "".join(
        f"<section><h2>{escape(title)}</h2><p>{escape(text if text is not None else contact)}</p></section>"
        for title, text in PARAGRAPHS
    )
    return HTMLResponse(
        """<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SCHULPILOT – Datenschutz</title><style>body{margin:0;background:#f5f7fc;color:#17243c;font:17px/1.7 system-ui,sans-serif}main{max-width:820px;margin:auto;padding:32px 22px}a{color:#5732bd}header{display:flex;align-items:center;gap:16px}header img{width:64px;height:64px}h1{font-size:32px}h2{font-size:22px;margin-top:32px}p{white-space:pre-line}nav{display:flex;gap:20px;flex-wrap:wrap}section{border-bottom:1px solid #dce1ec;padding-bottom:12px}</style>
<main><header><img src="/icons/icon-192.png" alt=""><strong>SCHULPILOT</strong></header><h1>Datenschutz</h1>
<p>Stand: 14. Oktober 2026. Für die Web-App und die Android-App.</p><nav><a href="/">Startseite</a><a href="/settings">Einstellungen</a><a href="/account-deletion">Konto löschen</a></nav>"""
        + sections
        + """
<p>Weitere Informationen der eingesetzten Dienste: <a href="https://policies.google.com/privacy">Google-Datenschutz</a>,
<a href="https://firebase.google.com/support/privacy">Firebase-Datenschutz</a>, <a href="https://openrouter.ai/privacy">OpenRouter-Datenschutz</a>.</p></main></html>"""
    )
