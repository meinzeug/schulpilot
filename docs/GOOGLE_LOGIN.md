# Google-Elternzugang

Optionales Google OpenID Connect über unsere eigene API. Firebase bleibt ausschließlich für Push zuständig. Kinder und Administratoren verwenden ihre bisherigen unabhängigen Zugänge; aus einer Google-Projektrolle werden keine SCHULPILOT-Rechte abgeleitet.

## Konfiguration

Im vorhandenen Projekt `schulpilot-f6bf3` existiert der Webclient **SCHULPILOT Elternzugang**, Ursprung `https://schulpilot.dorfspy.de`, ausschließlich Rücksprung `https://schulpilot.dorfspy.de/api/auth/google/callback`. Nur `openid email`, keine Gmail-/Drive-/Kalenderrechte und keine Firebase Authentication. Keine Offlineberechtigung; Google-Zugriffs-/Erneuerungstokens werden weder gespeichert noch an Flutter gegeben.

Private Konfiguration lokal `/home/dennis/.local/share/schulpilot-firebase/google-oauth-client.json` (0600, Verzeichnis 0700), Server `/etc/schulpilot/google-oauth-client.json` (root:schulpilot, 0640). `GOOGLE_OAUTH_CLIENT_FILE` bleibt eine lokale Servereinstellung. Alternativ kann der Admin `google_oauth_client_json` verschlüsselt speichern; dieser Wert hat Vorrang vor der Datei und wird niemals zurückgegeben. `google_login_enabled` aktiviert den eingerichteten Zugang. Ohne Einrichtung bleibt normale Anmeldung nutzbar und der Google-Knopf verborgen.

## Absicherung

- Kurze Flows von zehn Minuten; zufälliger State, Nonce, HttpOnly-/SameSite-Lax-Cookie für den einzelnen Browserrücksprung und serverseitiges PKCE. Google-Signatur, Ablauf, Aussteller, Audience, gegebenenfalls Authorized Party, bestätigte E-Mail und Nonce werden geprüft. Festgelegte HTTPS-Endpunkte und begrenzte Wartezeiten, kein beliebiger Rücksprung.
- Web erhält ausschließlich unsere widerrufbare HttpOnly-/SameSite-Strict-Sitzung. Nachträglicher Native-Header kann keinen Web-Flow in eine Bearerantwort verwandeln.
- Android verwendet den externen Browser. Zusätzlich zur zufälligen, im sicheren Gerätespeicher gehaltenen Client-PKCE-Proof ist ein einmaliges, nur im Callback-Fragment ausgeliefertes Rückgabeticket nötig. Bloßes Polling mit dem initialen App-Proof reicht ausdrücklich nicht, damit ein versandter Anmeldelink kein fremdes Google-Konto auf das initiierende Gerät holt.
- Android-App-Link mit der geprüften Direct-Signatur unter `/.well-known/assetlinks.json`; zusätzliche Rückgabe über `schulpilot://google/complete`. Der Rücksprung allein liefert keine Sitzung. Für den später durch Google signierten Play-Client den tatsächlichen Play-App-Signing-Fingerprint ergänzen; der Upload-Fingerprint ist kein Nachweis dafür.
- Bekannte Google-Kontokennung meldet nur das damit ausdrücklich verknüpfte Elternkonto an. Bestehende E-Mail-Adresse allein erzeugt keine Verknüpfung. Verknüpfen unter Einstellungen erfordert das bestehende Elternpasswort, die bestehende aktive Sitzung und dieselbe bestätigte E-Mail. Kinder und Admins erhalten Backend-403.
- Google-Elternregistrierung legt ausschließlich eine eigene Familie und den Elternrang an; Volljährigkeits-/Berechtigungsbestätigung und ein eigenes starkes Elternpasswort für Wiederherstellung, Löschung und geschützte Kontoeinstellungen bleiben erforderlich. Normale Tarifgrenzen gelten ebenfalls. Bei nicht von Google betriebenen Drittanbieter-Postfächern ist zusätzlich die eigene echte E-Mail-Bestätigung erforderlich; email_verified allein genügt dafür nicht.
- Abschluss und Start nur einmal per bedingtem Datenbankupdate; kein erneuter Codeaustausch nach einem Timeout. Logout löscht daran gebundene offene Verknüpfungen. Identitäten verschwinden per FK bei Kontolöschung; abgelaufene Flows im täglichen Bereinigungslauf.

## Google-Konsole, tatsächlich am 14.10.2026

Branding SCHULPILOT, vorhandene Betreiber-Googleadresse als Support/Entwicklerkontakt, neuer schwarzer Abschluss­hut sowie Website-/Datenschutz-/Bedingungslinks gespeichert. Zielgruppe extern, Veröffentlichungsstatus **In Produktion**. Prüfung des grundlegenden Datenzugriffs erfordert laut Konsole keine zusätzliche Freigabe. Die Branding-Prüfung meldete fehlenden Webseiten-Inhaberschaftsnachweis und zu wenig maschinenlesbaren Datenschutzinhalt. Deshalb eigener HTML-Datenschutz ohne JavaScript und HTML-Dateiverifikation für ausschließlich die SCHULPILOT-Subdomain. Kein zweites Projekt, keine doppelten OAuthclients, keine anderen DNS-Einträge geändert.

Ein akzeptierter OAuthclient oder ein produktiver Zielgruppenstatus ist kein behaupteter erfolgreicher Login oder eine genehmigte Branding-Prüfung. Tatsächliche Abnahme und offene Nachweise stehen in `STATUS.md` und `CHATGPT_HANDOFF.txt`.

Primärquellen, geprüft gegen google-auth 2.62.0 und die fixierte Flutter-Version:
- https://developers.google.com/identity/openid-connect/openid-connect
- https://googleapis.dev/python/google-auth/2.62.0/reference/google.oauth2.id_token.html
- https://developers.google.com/identity/branding-guidelines
- https://developers.google.com/terms/api-services-user-data-policy
- https://docs.flutter.dev/cookbook/navigation/set-up-app-links
