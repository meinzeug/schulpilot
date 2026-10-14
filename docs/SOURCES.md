# Offizielle Quellen, geprüft am 14.10.2026

Implementierte Schnittstellen wurden gegen diese offiziellen Dokumentationen geprüft. Versionsauflösung zusätzlich über Paketregister und die tatsächlich installierten Werkzeuge. Modellnamen, Fähigkeiten und Preisobergrenzen wurden für den ausdrücklich beauftragten OpenRouter-Free-Standard im offiziellen Endpunktkatalog überprüft; keine Annahme eines dauerhaft kostenlosen oder verfügbaren Endpunkts.

| Bereich | Primärquelle / Prüfung |
| --- | --- |
| Flutter | https://docs.flutter.dev/install/manual und https://docs.flutter.dev/install/archive ; offizieller `stable`-Git-Checkout: Flutter 3.47.7 / Revision `abaf9c523780a608bd46686fd5e53740a07077f8`, Dart 3.13.5. Das JSON-SDK-Archiv lieferte beim Abruf 404; deshalb offizieller Git-Checkout statt erfundenem Download. |
| Flutter-Web | https://docs.flutter.dev/platform-integration/web/initialization ; tatsächliches `flutter build web --help`: eigene Bootstrapdatei, `--no-web-resources-cdn`, `--csp`. |
| GoRouter | https://pub.dev/documentation/go_router/latest/go_router/GoRouter/optionURLReflectsImperativeAPIs.html ; Version 18.0.2 und lokaler Paketquelltext: Webnavigation per `go`, native Detailnavigation per `push`. |
| Flutter-Pakete | Offizielles pub.dev-Register; direkte Pins in `app/pubspec.yaml`, alle transitiven Stände in `pubspec.lock`. Export: https://pub.dev/packages/file_saver . |
| FastAPI | https://fastapi.tiangolo.com/deployment/concepts/ und https://fastapi.tiangolo.com/deployment/server-workers/ ; hier ein API-Prozess hinter vorhandenem Caddy, separater persistenter Jobworker. |
| Python-Pakete | pypi.org JSON-Metadaten: FastAPI 0.143.0, SQLAlchemy 2.1.4, Uvicorn 0.54.0, Psycopg 3.3.6, Pydantic 2.14.1, Pillow 12.3.0, Alembic 1.20.0; vollständige Pins in den Lockdateien. |
| OpenAI strukturierte Ausgaben | https://developers.openai.com/api/docs/guides/structured-outputs ; Responses `text.format`, zusätzliche serverseitige Validierung. |
| OpenAI Bilder | https://developers.openai.com/api/docs/guides/images-vision ; `input_image` als private Data-URL über unser Backend. |
| Minderjährige | https://developers.openai.com/api/docs/guides/safety-checks/under-18-api-guidance ; zusätzliche Schutzmaßnahmen und ZDR-Anforderungen bei bestimmten personenbezogenen Kinderdaten. |
| OpenAI Datenkontrollen | https://developers.openai.com/api/docs/guides/your-data ; `store:false` ist keine pauschale ZDR-/Datenschutzfreigabe. |
| Codex | https://developers.openai.com/codex/noninteractive/ und https://developers.openai.com/codex/config-reference/ ; außerdem tatsächlich installierte CLI 0.162.1: `exec --help`, `features list`. Kein Live-Lernaufruf unter Entwicklungszugängen. |
| OpenRouter | https://openrouter.ai/docs/guides/features/structured-outputs , https://openrouter.ai/docs/guides/privacy/data-collection , https://openrouter.ai/docs/guides/get-started/sovereign-ai ; explizite Upstreambindung, ZDR und Data-Collection-Deny ersetzen keine Vertrags-/Kontoprüfung. |
| Hetzner | https://docs.hetzner.cloud/reference/cloud und https://docs.hetzner.com/networking/dns/migration-to-hetzner-console/features-and-differences/ ; zuständige Cloud-API und bestehende Zone wurden tatsächlich authentifiziert geprüft. |
| Caddy | https://caddyserver.com/docs/caddyfile/directives/tls ; vorhandenes Caddy 2.6.2, ACME-Issuer `dir`, lokale Validierung, öffentlich geprüfter Let’s-Encrypt-Aussteller. |

Flutter-/Python-Abhängigkeiten müssen bei Aktualisierungen erneut auf Sicherheit, API-Kompatibilität und Lizenzpflichten geprüft werden. `docs/python-dependencies.json` enthält aus den installierten Distributionsmetadaten ermittelte Lizenzangaben einschließlich Entwicklungswerkzeugen; fehlende Angaben bleiben unbekannt. Flutter-Lizenzhinweise sind in der App erreichbar. Es wurde keine pauschale juristische Freigabe aller kommerziellen Betriebsbedingungen behauptet.


Zusätzliche offizielle Quellen, geprüft am 14.10.2026:

- Mehrseitiger Tagesassistent: https://pub.dev/packages/image_picker (fixiert 1.2.4, Kamera/Galerie und dokumentiertes `retrieveLostData` bei Android-Neustart) sowie https://openrouter.ai/docs/guides/features/structured-outputs (JSON-Schema-Ausgaben; zusätzlicher serverseitiger Paket-/Quellenabgleich). Keine neue Client-Abhängigkeit erforderlich.

- OpenRouter aktueller Modellkatalog: https://openrouter.ai/api/v1/models ; konkrete Endpunkte über `/api/v1/models/{author}/{slug}/endpoints`, für die oben dokumentierten kostenlosen Modelle tatsächlich abgerufen.
- Kosten- und Providerbindung: https://openrouter.ai/docs/guides/routing/provider-selection (max_price, only, allow_fallbacks, data_collection, zdr).
- FlutterFire: https://firebase.google.com/docs/cloud-messaging/flutter/client und https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages ; tatsächlich aufgelöste Pakete `firebase_core 4.15.0`, `firebase_messaging 16.7.0`, `firebase_core_web 3.12.0`, JS SDK `12.19.0`. Dieses fixierte Messaging-Paket stellt `getToken/onTokenRefresh` bereit; neuere FID-Methoden der Dokumentation wurden nicht erfunden oder vorausgesetzt.
- FCM HTTP v1 / Dienstkonto: https://firebase.google.com/docs/cloud-messaging/send/v1-api ; Payload-Schema einschließlich `PRIVATE`: https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages .
- Token-Lebenszyklus: https://firebase.google.com/docs/cloud-messaging/manage-tokens .
- Android-Signierung und AAB: https://docs.flutter.dev/deployment/android .
- Google Play Familien: https://support.google.com/googleplay/android-developer/answer/9893335 ; Kontolöschung: https://support.google.com/googleplay/android-developer/answer/13327111 .

Bei echten Google-Projektzugängen sind die dann geltenden SDK-/Families-/Data-Safety-Vorgaben erneut zu prüfen. Ein gebautes AAB ersetzt keine Play-Prüfung.


Ausbau vom 14.10.2026:

- Mehrfachauswahl: https://pub.dev/packages/image_picker ; `pickMultiImage`, Version 1.2.4. Drehen: https://pub.dev/documentation/image/latest/image/copyRotate.html ; bestehende Version 4.12.0 beibehalten.
- OpenRouter Datenkontrollen: https://openrouter.ai/docs/guides/privacy/data-collection und https://openrouter.ai/docs/guides/features/zdr ; geschützte synthetische Routingprüfung gegen die tatsächlich gewählten Endpunkte. Die erteilte Betreiberfreigabe ist kein Beleg für eine technisch verfügbare Route.
- Firebase: https://firebase.google.com/docs/cloud-messaging/flutter/get-started ; reale Zustellung erst mit Projektkonfiguration und Gerätetest.
- GitHub Actions: offizielle Repositories/Release-API von https://github.com/actions/checkout/tree/v7.0.1 und https://github.com/actions/setup-python/tree/v7.0.0 ; Release-Tags und vollständige Commit-IDs über Git verifiziert. Beide verwenden Node 24 und benötigen aktuelle Runner. CI nutzt Ubuntu 24.04, Python 3.12.3 und den bereits fixierten offiziellen Flutter-Commit; keine Deploy-/Signierschlüssel in CI.
- Vorbereiteter späterer Zahlungsbetrieb: https://docs.stripe.com/api/checkout/sessions/create und https://support.google.com/googleplay/android-developer/answer/9858738 ; noch kein Checkout aktiviert, keine erfundenen Tarifpreise und kein fremdes Zahlungs-/Google-Konto verwendet.
- E-Mail-Direktlinks (14.10.2026): https://api.flutter.dev/flutter/flutter_web_plugins/PathUrlStrategy/PathUrlStrategy.html und https://pub.dev/documentation/go_router/18.0.2/go_router/GoRouterState/uri.html ; `includeHash=true` erhält das Fragment beim Kaltstart. Die Formularseite erhält die vollständige Router-URI, statt den nachträglich veränderten Browserzustand auszulesen. Bestehende Flutter-/Router-Versionen bleiben fixiert.

- OpenRouter-Free-Standard (14.10.2026): https://openrouter.ai/docs/guides/routing/provider-selection und https://openrouter.ai/docs/guides/features/structured-outputs ; feste Endpunktbindung, Preisgrenze 0, Datensammlung gesperrt, keine Fallbacks. https://openrouter.ai/docs/guides/best-practices/reasoning-tokens ; dokumentierte `reasoning.enabled`/`exclude`-Parameter tatsächlich getestet. Der kompakte Free-Standard verwendet `enabled:false`, nachdem längere Reasoning-Ausgaben Ausgabelimits erreichten. https://openrouter.ai/dots-studio/dots-3-note-preview:free ; angekündigtes Ende 31.12.2026 erfordert spätere ausdrückliche Modellmigration. Entscheidung und weitere Datenschutzquellen: [AI_STANDARD.md](AI_STANDARD.md).

- Lokaler Fotoimport im Browser (14.10.2026): https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/connect-src ; `fetch` und `XMLHttpRequest` unterliegen `connect-src`. Im fixierten Flutter-Paket `cross_file 0.3.5+5` liest `XFile.readAsBytes` lokale Blob-URLs per XHR. Der öffentliche Chromium-Test reproduzierte die CSP-Sperre; die projektspezifische Caddy-Richtlinie erlaubt deshalb ausdrücklich `blob:`.

- Betreutes Lernen (14.10.2026): https://openrouter.ai/docs/guides/features/structured-outputs ; Ausgabevarianten für bekannte beziehungsweise neu vorzuschlagende Ziele, zusätzliche Backendprüfung. Der konkrete Endpunktkatalog wurde erneut auf Bild-/Text-/Schemafähigkeiten und Preis 0 geprüft. Die mehrtägigen Lernkriterien sind ausdrücklich Produktregeln und keine behauptete externe Wirksamkeitszertifizierung.

- Android-Updates, geprüft am 14.10.2026: https://developer.android.com/reference/androidx/core/content/FileProvider ; https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls() ; https://developer.android.com/guide/playcore/in-app-updates/kotlin-java (app-update 2.1.0) ; https://support.google.com/googleplay/android-developer/answer/12085295?hl=en (Play-Flavour ohne direkte APK-Installation).

- Flutter-Gestaltung und Anpassung, erneut geprüft am 14.10.2026: [Themes](https://docs.flutter.dev/cookbook/design/themes), [Material 3](https://api.flutter.dev/flutter/material/ThemeData/useMaterial3.html), [Adaptive und responsive Oberflächen](https://docs.flutter.dev/ui/adaptive-responsive), [Aufbau nach verfügbarem Platz](https://docs.flutter.dev/ui/adaptive-responsive/general). Gemeinsame `ThemeData`/`ColorScheme`, Material-Komponenten und Layoutentscheidungen nach Fenstergröße statt allein nach Gerätenamen. Material 3 ist im fixierten Framework bereits enthalten; keine neue Abhängigkeit oder Versionsanhebung nötig. Der lokale Android-Einstieg `MainActivity : FlutterActivity` bestätigt eine Flutter-App, keine WebView-Hülle.

- Android-Installer, erneut geprüft am 14.10.2026: [FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider) und [Installationsquellen](https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls()). Der direkte Updater übergibt eine nur vorübergehend lesbare `content:`-URI an Androids Installationsoberfläche; Android verwaltet Quellenfreigabe und Bestätigung. [ACTION_INSTALL_PACKAGE](https://developer.android.com/reference/android/content/Intent#ACTION_INSTALL_PACKAGE) ist seit API 29 veraltet; der vorhandene direkte Adapter verwendet `ACTION_VIEW` mit APK-MIME-Typ. Keine stille Installation behaupten. Direkter und Play-Flavour bleiben getrennt.

- OpenRouter-Fehlerantworten, geprüft am 14.10.2026: [Errors and debugging](https://openrouter.ai/docs/api_reference/errors-and-debugging). Auch nicht gestreamte HTTP-200-Antworten können ein Fehlerobjekt ohne choices enthalten. Wurzel-/Choice-Fehler und leere Antworten werden gesondert erkannt; nur feste Fehlerkategorien anzeigen, keine Upstreamnachrichten oder Metadaten übernehmen. Kein impliziter Wiederholungsversuch.

## Produktionsprüfung 14.10.2026

- Google Play: aktuelle Ziel-API-Anforderung (Smartphone-Neueinreichung/Updates seit 31.08.2026 API 36): https://support.google.com/googleplay/android-developer/answer/11926878
- Google Play: geschlossener Test nur bei den betroffenen neuen persönlichen Konten, zwölf Personen/14 Tage vor Produktionsantrag: https://support.google.com/googleplay/android-developer/answer/14151465
- Android: 16-KB-Seitengrößen, ZIP- und ELF-Prüfungen ersetzen keine Geräteprüfung: https://developer.android.com/guide/practices/page-sizes
- Alembic ScriptDirectory.get_heads(consider_depends_on=True): effektive Migrations-Heads, API in der fixierten Alembic-Version geprüft: https://alembic.sqlalchemy.org/en/latest/api/script.html
- Flutter: tatsächlich heruntergeladene fixierte Revision abaf9c523780a608bd46686fd5e53740a07077f8; SemanticsNode.flagsCollection und CI-Kennung anhand dieses SDK-Quellcodes geprüft. Das CI-Signal vermeidet die unbenötigte Azure-Metadatenerkennung: https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/packages/flutter_tools/lib/src/base/bot_detector.dart
