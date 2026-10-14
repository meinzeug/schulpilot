# Offizielle Quellen, geprüft am 14.10.2026

Implementierte Schnittstellen wurden gegen diese offiziellen Dokumentationen geprüft. Versionsauflösung zusätzlich über Paketregister und die tatsächlich installierten Werkzeuge. Es wurden keine Modellnamen oder Anbieterpreise vorausgewählt.

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
