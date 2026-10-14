import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'download_panel.dart';
import 'ui.dart';

class LandingScreen extends StatelessWidget {
  final AppState state;
  const LandingScreen(this.state, {super.key});
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 850;
    return Scaffold(
      body: SelectionArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 48 : 22,
                  vertical: 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: brand(),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.go(
                            state.user == null ? '/login' : '/app',
                          ),
                          child: Text(
                            state.user == null ? 'Anmelden' : 'Mein Lernraum',
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: wide ? 90 : 50),
                    Wrap(
                      spacing: 60,
                      runSpacing: 36,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: wide ? 520 : double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Tag('MEHR LEICHTIGKEIT IM FAMILIENALLTAG'),
                              const SizedBox(height: 24),
                              Text(
                                'Ein guter Lernweg.\nFür dein Kind.\nFür euch als Familie.',
                                style: TextStyle(
                                  fontSize: wide ? 53 : 36,
                                  fontWeight: FontWeight.w800,
                                  height: 1.12,
                                  color: ink,
                                  letterSpacing: -1.2,
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Vom aktuellen Schulstoff zur nächsten kleinen Lerneinheit. Mit verständlichen Erklärungen, passenden Übungen und einem klaren Überblick für Eltern.',
                                style: TextStyle(
                                  fontSize: 17,
                                  height: 1.7,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  ActionButton(
                                    label: 'Synthetisch ausprobieren',
                                    icon: Icons.arrow_forward_rounded,
                                    onPressed: () async {
                                      await state.accept(
                                        await state.api.post('/demo'),
                                      );
                                      if (context.mounted) context.go('/app');
                                    },
                                  ),
                                  OutlinedButton(
                                    onPressed: () => context.go('/register'),
                                    child: const Text('Elternkonto erstellen'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Entwicklungsstand · Demo ohne echte Kinderdaten',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: wide ? 440 : double.infinity,
                          child: Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5EEDF),
                              borderRadius: BorderRadius.circular(34),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.wb_sunny_outlined, color: teal),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'SO KANN DEIN LERNTAG AUSSEHEN',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'Kleine Schritte.\nEin gutes Gefühl.',
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    color: ink,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 25),
                                for (final item in [
                                  (
                                    Icons.document_scanner_outlined,
                                    'Dein Stoff',
                                    'Material prüfen & bestätigen',
                                  ),
                                  (
                                    Icons.auto_stories_outlined,
                                    'Dein nächster Schritt',
                                    'Eine überschaubare Einheit',
                                  ),
                                  (
                                    Icons.family_restroom_rounded,
                                    'Gemeinsam dranbleiben',
                                    'Eltern sehen, wobei Hilfe gut tut',
                                  ),
                                ])
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Panel(
                                      padding: const EdgeInsets.all(18),
                                      child: Row(
                                        children: [
                                          Icon(item.$1, color: teal),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.$2,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                Text(
                                                  item.$3,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const Text(
                                  'Beispielhafte Darstellung · keine gemessenen Lernergebnisse',
                                  style: TextStyle(fontSize: 10, color: muted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 55),
                    const Notice(
                      'Im Testraum werden künstliche Materialien verwendet. Das feste Beispiel funktioniert ohne KI; der gesonderte KI-Test nutzt einen ausdrücklich kostenlosen Anbieter. Echte Lerninhalte benötigen einen freigegebenen und technisch geeigneten KI-Dienst. Ist dieser nicht verfügbar, wird die Verarbeitung angehalten.',
                    ),
                    const SizedBox(height: 28),
                    AndroidDownload(state.api),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 32,
                      runSpacing: 22,
                      children: [
                        for (final item in [
                          (
                            'Eigene Zugänge',
                            'Eltern und Kinder melden sich unabhängig voneinander an.',
                          ),
                          (
                            'Klarer Lernablauf',
                            'Stoff bestätigen, verstehen, üben und gezielt wiederholen.',
                          ),
                          (
                            'Nachvollziehbarer Einblick',
                            'Antworten, Hinweise und Hilfewünsche bleiben in der Familie.',
                          ),
                        ])
                          SizedBox(
                            width: wide ? 330 : double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.$1,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  item.$2,
                                  style: const TextStyle(color: muted),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 44),
                    Wrap(
                      spacing: 16,
                      children: [
                        TextButton(
                          onPressed: () => openRoute(context, '/privacy'),
                          child: const Text('Datenschutz & Transparenz'),
                        ),
                        TextButton(
                          onPressed: () => openRoute(context, '/about'),
                          child: const Text('Projektstatus & Kontakt'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final AppState state;
  final String mode;
  final Uri linkUri;
  const AuthScreen(
    this.state, {
    super.key,
    required this.mode,
    required this.linkUri,
  });
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final family = TextEditingController();
  final code = TextEditingController();
  final token = TextEditingController();
  bool consent = false;
  String? result;
  String? error;
  @override
  void initState() {
    super.initState();
    _readLink();
  }

  @override
  void didUpdateWidget(covariant AuthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.linkUri != widget.linkUri || oldWidget.mode != widget.mode) {
      _readLink();
      result = null;
      error = null;
    }
  }

  void _readLink() {
    token.clear();
    if (!['reset', 'verify', 'invite'].contains(widget.mode)) return;
    try {
      final values = Uri.splitQueryString(widget.linkUri.fragment);
      final value = values['token'];
      if (value != null && RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(value)) {
        token.text = value;
      }
    } on FormatException {
      // A damaged email link must still allow manual code entry.
    }
  }

  @override
  void dispose() {
    for (final c in [username, password, name, family, code, token]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final title = switch (mode) {
      'register' => 'Ein Elternkonto für eure Familie',
      'recovery' => 'Passwort vergessen?',
      'reset' => 'Neues Elternpasswort',
      'verify' => 'E-Mail bestätigen',
      'invite' => 'Zur Familie dazukommen',
      _ => 'Willkommen zurück.',
    };
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cream,
        title: InkWell(onTap: () => context.go('/'), child: brand()),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 490),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    mode == 'login'
                        ? 'Eltern: E-Mail-Adresse. Kinder: eigener Benutzername.'
                        : mode == 'register'
                        ? 'Die öffentliche Registrierung erstellt ausschließlich ein Elternkonto. Kinderzugänge werden später von berechtigten Eltern angelegt.'
                        : 'Links sind zeitlich begrenzt und nur einmal verwendbar.',
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 24),
                  if (result != null)
                    Notice(result!, icon: Icons.check_circle_outline),
                  if (error != null) Notice(error!, warning: true),
                  if (['login', 'register', 'recovery'].contains(mode)) ...[
                    TextField(
                      controller: username,
                      autofillHints: mode == 'login'
                          ? [AutofillHints.username]
                          : [AutofillHints.email],
                      keyboardType: mode == 'login'
                          ? TextInputType.text
                          : TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: mode == 'login'
                            ? 'E-Mail oder Kinder-Benutzername'
                            : 'E-Mail-Adresse',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (['register', 'invite'].contains(mode)) ...[
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Dein Anzeigename',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (mode == 'register') ...[
                    TextField(
                      controller: family,
                      decoration: const InputDecoration(
                        labelText: 'Name deiner Familie',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if ([
                    'login',
                    'register',
                    'reset',
                    'invite',
                  ].contains(mode)) ...[
                    TextField(
                      controller: password,
                      obscureText: true,
                      autofillHints: mode == 'login'
                          ? [AutofillHints.password]
                          : [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: mode == 'invite'
                            ? 'Bestehendes oder neues Elternpasswort'
                            : mode == 'login'
                            ? 'Passwort'
                            : 'Passwort (mindestens 12 Zeichen)',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (mode == 'login') ...[
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'Administrator-Zweitfaktor',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      children: [
                        TextField(
                          controller: code,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'TOTP-Code',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (['reset', 'verify', 'invite'].contains(mode)) ...[
                    TextField(
                      controller: token,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Sicherer Link-Code',
                        helperText: 'Wird aus dem E-Mail-Link übernommen.',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (mode == 'register') ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: consent,
                      onChanged: (v) => setState(() => consent = v ?? false),
                      title: const Text(
                        'Ich bin volljährig und für die Einrichtung dieser Familie berechtigt.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ActionButton(
                    label: switch (mode) {
                      'register' => 'Elternkonto anlegen',
                      'recovery' => 'Wiederherstellungslink anfordern',
                      'verify' => 'E-Mail bestätigen',
                      'reset' => 'Passwort erneuern',
                      'invite' => 'Einladung annehmen',
                      _ => 'Anmelden',
                    },
                    onPressed: () async {
                      setState(() {
                        error = null;
                        result = null;
                      });
                      try {
                        if (mode == 'login') {
                          await widget.state.login(
                            username.text.trim(),
                            password.text,
                            totp: code.text.trim(),
                          );
                          if (context.mounted) context.go('/app');
                          return;
                        }
                        if (mode == 'register' && !consent) {
                          throw ApiError(
                            'Bitte die Volljährigkeit und Berechtigung bestätigen.',
                          );
                        }
                        final data = await widget.state.api.post(
                          switch (mode) {
                            'register' => '/auth/register',
                            'recovery' => '/auth/recovery',
                            'reset' => '/auth/reset',
                            'verify' => '/auth/verify',
                            _ => '/invitations/accept',
                          },
                          switch (mode) {
                            'register' => {
                              'email': username.text.trim(),
                              'password': password.text,
                              'display_name': name.text.trim(),
                              'family_name': family.text.trim(),
                              'adult_consent': consent,
                            },
                            'recovery' => {'email': username.text.trim()},
                            'reset' => {
                              'token': token.text,
                              'password': password.text,
                            },
                            'verify' => {'token': token.text},
                            _ => {
                              'token': token.text,
                              'password': password.text,
                              'display_name': name.text.trim(),
                            },
                          },
                        );
                        if (mounted) setState(() => result = data['message']);
                      } catch (e) {
                        if (mounted) setState(() => error = e.toString());
                      }
                    },
                  ),
                  const SizedBox(height: 18),
                  if (mode == 'login')
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => context.go('/recovery'),
                          child: const Text('Passwort vergessen'),
                        ),
                        TextButton(
                          onPressed: () => context.go('/register'),
                          child: const Text('Elternkonto erstellen'),
                        ),
                      ],
                    )
                  else
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Zur Anmeldung'),
                    ),
                  if (mode == 'register' || mode == 'recovery')
                    const Notice(
                      'Solange kein E-Mail-Dienst eingerichtet ist, meldet der Server die fehlende Voraussetzung ausdrücklich. Es wird kein Versand vorgetäuscht.',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InformationScreen extends StatelessWidget {
  final String kind;
  const InformationScreen(this.kind, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: brand(),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/'),
      ),
    ),
    body: SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind == 'privacy'
                        ? 'Datenschutz & Transparenz'
                        : 'SCHULPILOT · Entwicklungsstand',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  FutureBuilder<Json>(
                    future: Api().get('/legal'),
                    builder: (context, result) {
                      if (!result.hasData) return const SizedBox.shrink();
                      final data = result.data!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['complete'] == true
                                  ? 'Verantwortlicher Betreiber\n${data['operator']}\n${data['address']}\nSupport: ${data['support_email']}'
                                  : 'Die vollständigen Betreiber- und Kontaktangaben für den kommerziellen Start sind noch nicht hinterlegt.',
                            ),
                            const SizedBox(height: 10),
                            Text(
                              data['operator_data_approval'] == true
                                  ? 'Die Anbieter- und Datenschutzfreigabe des Betreibers liegt vor. Ob ein KI-Dienst tatsächlich verfügbar ist, hängt zusätzlich von seiner technischen Konfiguration ab.'
                                  : 'Echte Unterrichtsmaterialien benötigen eine dokumentierte Betreiberfreigabe.',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    kind == 'privacy'
                        ? '''Eltern und Kinder haben eigene Zugänge. Eltern sehen innerhalb ihrer berechtigten Familie Materialien, Lernaufträge, gestellte Aufgaben, Antworten, Hinweise, Erklärungen, Hilfewünsche und eine ungefähre aktive Lernzeit. Andere Apps, Webseiten außerhalb von SCHULPILOT und das übrige Gerät werden nicht überwacht.

Im öffentlichen Testraum werden ausschließlich synthetische Inhalte verarbeitet. Bitte dort keine echten Namen, Fotos oder Kinderantworten eingeben. Jeder Testraum ist getrennt und wird nach 24 Stunden gelöscht. Die feste Demo benötigt keine KI. Der ausdrücklich gekennzeichnete KI-Test sendet ausschließlich ein vom Server erzeugtes künstliches Testblatt bzw. festen Beispielstoff an die konfigurierten kostenlosen OpenRouter-Modelle. Freie Kontoeingaben werden dabei nicht übertragen.

Echte Lerninhalte werden nur über ausdrücklich freigegebene und technisch geeignete Anbieter verarbeitet. Ist kein passender geschützter Endpunkt verfügbar, wird die Verarbeitung mit einer verständlichen Meldung angehalten. Die aktuelle Betreiberfreigabe steht oben.

Fotos werden vor dem Upload zum Drehen und Zuschneiden angezeigt. Ausstehende zugeschnittene Fotos sind auf diesem Gerät 24 Stunden fortsetzbar (höchstens 8 Seiten / 3 MB). Ältere Einträge werden beim nächsten Appstart oder Öffnen des Assistenten bereinigt; Abmelden oder Entfernen löscht diese lokale Warteschlange. Der Server entfernt Metadaten und gibt private Bilder ausschließlich nach Berechtigungsprüfung aus. Eine Verkleinerung ersetzt nicht das Entfernen persönlicher Angaben im Bild.

Sitzungen sind widerrufbar. Eltern können Kinderkonten und ihr eigenes Konto löschen sowie einen Familienexport mit Materialien und Lernverlauf herunterladen. Beim Löschen des Familieninhabers wird dessen gesamte Familie gelöscht; eingeladene Eltern verlieren den Zugriff.

Aufbewahrung im Pilot: Materialien, Einheiten, Antworten, Aktivitäten und Nachrichten höchstens 365 Tage; technische Aufträge 30 Tage; abgelaufene Zugangstokens und Sitzungen weitere 7 Tage; tägliche Backups 14 Tage. Backups müssen vor einer Wiederherstellung mit zwischenzeitlichen Löschungen abgeglichen werden. Abrechnung und Betriebsprotokolle enthalten keine Fotos oder vollständigen Kinderantworten.

Es gibt keine Werbung, keinen Verkauf von Kinderprofilen und keine gemeinsame Inhaltsbibliothek aus privaten Lernmaterialien. Aktive Lernzeit bleibt eine Näherung. Eine einzelne richtige Antwort begründet keine sichere Beherrschung; fehlende Nutzung keine Aussage über Verständnis.'''
                        : '''Version 0.1.0 · Technischer Pilot

SCHULPILOT verbindet einen Flutter-Client für Web und Android mit einer eigenen Backend-API. Ein eigener Testraum enthält ausschließlich künstliche Materialien. Die Verfügbarkeit echter KI-Verarbeitung hängt zusätzlich von der freigegebenen Anbieterkonfiguration ab.

Registrierung, Verifikation, Einladungen und Wiederherstellung nutzen den eingerichteten verschlüsselten Gmail-SMTP-Versand. Diese Abläufe wurden über die öffentliche HTTPS-Adresse mit synthetischen Testkonten und tatsächlichem E-Mail-Eingang geprüft.

OpenAI und OpenRouter sind als serverseitige Adapter implementiert. Für das feste künstliche KI-Testblatt wurden kostenlose OpenRouter-Bild- und Schemaaufrufe tatsächlich durchgeführt. Die Namen der verwendeten Modelle werden angezeigt. Für echte Lerninhalte werden die dokumentierte Betreiberfreigabe und die technische Eignung des konkret ausgewählten Endpunkts getrennt geprüft. Codex CLI bleibt experimentell und benötigt einen separat isolierten Worker sowie eine Nutzungsfreigabe.

Erinnerungen erscheinen gebündelt innerhalb der App. Push für Android und Web ist mit Geräte-Opt-in, Sitzungswiderruf, neutralen Nachrichtentexten und Ruhezeiten implementiert. Ohne freigegebenes Firebase-Projekt und Dienstkonto bleibt der Versand gesperrt; eine echte Push-Zustellung wurde noch nicht nachgewiesen. Eine signierte Android-App-Bundle-Datei ist gebaut und geprüft; die Store-Einrichtung ist dokumentiert. Eine Play-Veröffentlichung und ein Zahlungscheckout sind noch nicht erfolgt.

Vor einem kommerziellen Start mit echten Daten fehlen außerdem die veröffentlichten Angaben zum verantwortlichen Betreiber, Kontakt, Impressum, abschließende rechtliche Datenschutzhinweise und die Abnahme des Betriebs. Diese Testseite enthält keine erfundenen Betreiberangaben.

Quellcode und technische Dokumentation: github.com/meinzeug/schulpilot''',
                    style: const TextStyle(fontSize: 15, height: 1.8),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
