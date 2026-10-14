# SCHULPILOT – dauerhafte Arbeitsregeln

- Erst Git-Status, bestehende Anweisungen und Serverbestand prüfen. Fremde Änderungen erhalten. Kein neues Git-Repository, kein Force-Push.
- Flutter/Dart für Web und Android; modulares Python/FastAPI-Backend; PostgreSQL im Betrieb, SQLite für isolierte Tests. Keine zusätzlichen Microservices ohne belegten Bedarf.
- Autorisierung immer im Backend: Familienmitgliedschaften aus der Sitzung, niemals aus Client-IDs ableiten. Administratoren erhalten keinen privaten Inhaltszugriff.
- Kinder haben eigene widerrufbare Sitzungen. Argon2id-Passwörter, keine Standardpasswörter, Admin ausschließlich per lokalem CLI mit TOTP.
- Kinderinhalte, Fotos, Passwörter, Tokens und Provider-Schlüssel niemals protokollieren oder committen. Private Uploads ausschließlich authentifiziert ausliefern.
- Externe Verarbeitung echter Kinderdaten bleibt gesperrt, bis dokumentierte Anbieter-/Datenschutzfreigaben vorliegen. Synthetische Demo ausdrücklich kennzeichnen; niemals KI-Erfolg vortäuschen.
- Live-KI-Tests verwenden nur serverseitige feste Testbilder/-texte. Demo-Familienmarkierung allein erlaubt keine externen freien Eingaben. Free-Endpunkte vor jedem Testaufruf prüfen; Preisgrenze 0 und feste Modell-/Upstreambindung erzwingen.
- Google-Anbindung bedeutet Google Play und Push, keinen Google-Login. Firebase ausschließlich nach ausdrücklichem Geräte-Opt-in initialisieren; keine Analytics, Familienthemen oder Lerninhalte in Push. Sitzung und Familienrechte vor Versand erneut prüfen.
- Die signierte Test-APK ist auf der Startseite und nach Web-Login herunterladbar. Öffentliche Manifestwerte aus der tatsächlichen APK berechnen. Upload-Schlüssel und Firebase-Dienstkonto bleiben außerhalb von Git.
- Anbieteraufrufe: feste serverseitige Adapter, validierte Schemas, atomare Kontingentreservierung, keine automatischen Providerwechsel oder unbegrenzte Wiederholungen.
- Codex-Lernprovider niemals mit Entwicklungszugängen starten. Ausschließlich isolierter Worker ohne Host-/Deployment-/GitHub-/SSH-Zugriff. Experimentell und standardmäßig deaktiviert.
- Vor Deployment betroffene Konfigurationen sichern; vorhandenes Caddy ergänzen; andere Dienste nicht ändern. Daten/Secrets außerhalb der Releases. Rückweg dokumentieren.
- Versionsstände und Quellen in docs/SOURCES.md pflegen. Keine erfundenen Modelle, Preise, Messwerte oder Testergebnisse.
- Jede Arbeitseinheit mit passenden Tests/Builds, Diff-/Geheimnisprüfung, aussagekräftigem Commit und Push zum vorhandenen Remote abschließen. Fehler und Blocker offen benennen.
