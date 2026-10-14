import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'download_panel.dart';
import 'ui.dart';
import 'store_screens.dart';

class LandingScreen extends StatelessWidget {
  final AppState state;
  const LandingScreen(this.state, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final hero = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Tag('LERNEN MIT RÜCKENWIND'),
              const SizedBox(height: 24),
              Text(
                'Nach der Schule.\nMit Plan weiter.',
                style: TextStyle(
                  fontSize: wide ? 64 : 42,
                  color: ink,
                  height: 1.06,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2.3,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Heftfotos rein. Stoff verstehen. Mit passenden Übungen dranbleiben.',
                style: TextStyle(fontSize: 19, height: 1.5, color: muted),
              ),
              const SizedBox(height: 30),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () =>
                        context.go(kIsWeb ? '/angebote' : '/register'),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      kIsWeb ? 'Tarife ansehen' : 'Elternkonto erstellen',
                    ),
                  ),
                  ActionButton(
                    label: 'Demo ausprobieren',
                    secondary: true,
                    onPressed: () async {
                      await state.accept(await state.api.post('/demo'));
                      if (context.mounted) context.go('/app');
                    },
                  ),
                ],
              ),
            ],
          );
          final flow = Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF111C34), teal],
              ),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: electric,
                  size: 32,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Ein klarer nächster Schritt.',
                  style: TextStyle(
                    fontSize: 29,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                for (final item in [
                  (
                    Icons.document_scanner_rounded,
                    '01',
                    'Stoff sammeln',
                    'Die Heftseiten von heute.',
                  ),
                  (
                    Icons.lightbulb_outline_rounded,
                    '02',
                    'Verstehen & üben',
                    'Mit Hilfe, wenn es hakt.',
                  ),
                  (
                    Icons.check_circle_outline_rounded,
                    '03',
                    'Wissen festigen',
                    'Neue Aufgaben. Später wiederholen.',
                  ),
                ])
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(item.$1, color: Colors.white, size: 24),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.$3,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.$4,
                                style: const TextStyle(
                                  color: Color(0xFFC7CBED),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          item.$2,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 44 : 22,
                    vertical: 26,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: brand(),
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
                      SizedBox(height: wide ? 80 : 44),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 6, child: hero),
                            const SizedBox(width: 64),
                            Expanded(flex: 5, child: flow),
                          ],
                        )
                      else ...[
                        hero,
                        const SizedBox(height: 36),
                        flow,
                      ],
                      const SizedBox(height: 42),
                      Wrap(
                        spacing: 20,
                        runSpacing: 20,
                        children: [
                          for (final item in [
                            (
                              Icons.today_rounded,
                              'Ein Plan für heute',
                              'Überschaubare Einheiten statt Aufgabenberge.',
                            ),
                            (
                              Icons.support_agent_rounded,
                              'Hilfe im richtigen Moment',
                              'Verständliche Erklärungen und passende Hinweise.',
                            ),
                            (
                              Icons.family_restroom_rounded,
                              'Eltern bleiben im Bild',
                              'Was lief gut? Wo braucht dein Kind Unterstützung?',
                            ),
                          ])
                            SizedBox(
                              width: wide
                                  ? (constraints.maxWidth.clamp(0, 1240) -
                                            128) /
                                        3
                                  : double.infinity,
                              child: Panel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(item.$1, color: teal),
                                    const SizedBox(height: 18),
                                    Text(
                                      item.$2,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      item.$3,
                                      style: const TextStyle(color: muted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      if (kIsWeb) ...[
                        StoreSection(state),
                        const SizedBox(height: 32),
                      ],
                      if (kIsWeb) AndroidDownload(state.api),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: () => openRoute(context, '/privacy'),
                            child: const Text('Datenschutz'),
                          ),
                          TextButton(
                            onPressed: () => openRoute(context, '/about'),
                            child: const Text('Über SCHULPILOT'),
                          ),
                          if (kIsWeb)
                            TextButton(
                              onPressed: () => context.go('/bedingungen'),
                              child: const Text(
                                'Vertragsbedingungen & Widerruf',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
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
  final token = TextEditingController();
  bool consent = false, passwordVisible = false;
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
    for (final c in [username, password, name, family, token]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final title = switch (mode) {
      'register' => 'Euer Start mit Schulpilot',
      'recovery' => 'Passwort vergessen?',
      'reset' => 'Neues Elternpasswort',
      'verify' => 'E-Mail bestätigen',
      'invite' => 'Zur Familie dazukommen',
      _ => 'Willkommen zurück',
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
                        ? 'Mit deinem Benutzernamen und Passwort.'
                        : mode == 'register'
                        ? 'Erstelle dein Elternkonto. Danach richtest du die Zugänge deiner Kinder ein.'
                        : 'Übernimm den Code aus deiner E-Mail.',
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
                            ? 'E-Mail oder Benutzername'
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
                      obscureText: !passwordVisible,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: mode == 'login'
                          ? [AutofillHints.password]
                          : [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          tooltip: passwordVisible
                              ? 'Passwort verbergen'
                              : 'Passwort anzeigen',
                          icon: Icon(
                            passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(
                            () => passwordVisible = !passwordVisible,
                          ),
                        ),
                        labelText: mode == 'invite'
                            ? 'Bestehendes oder neues Elternpasswort'
                            : mode == 'login'
                            ? 'Passwort'
                            : 'Passwort (mindestens 12 Zeichen)',
                      ),
                    ),
                    const SizedBox(height: 16),
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
                          );
                          if (context.mounted) {
                            final next =
                                widget.linkUri.queryParameters['next'] ?? '';
                            context.go(
                              widget.state.isParent &&
                                      RegExp(
                                        r'^/bestellen/[a-z][a-z0-9-]{1,29}$',
                                      ).hasMatch(next)
                                  ? next
                                  : '/app',
                            );
                          }
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
                          onPressed: () => context.go(
                            Uri(
                              path: '/register',
                              queryParameters: widget.linkUri.queryParameters,
                            ).toString(),
                          ),
                          child: const Text('Elternkonto erstellen'),
                        ),
                      ],
                    )
                  else
                    TextButton(
                      onPressed: () => context.go(
                        Uri(
                          path: '/login',
                          queryParameters: widget.linkUri.queryParameters,
                        ).toString(),
                      ),
                      child: const Text('Zur Anmeldung'),
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
                        : 'Über Schulpilot',
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
                                  : 'Betreiber- und Kontaktangaben werden ergänzt.',
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

Echte Lerninhalte werden nur über ausdrücklich freigegebene und technisch geeignete Anbieter verarbeitet. Ist kein passender geschützter Endpunkt verfügbar, wird die Verarbeitung mit einer verständlichen Meldung angehalten. Die aktuelle Betreiberfreigabe steht oben. Nach einer abgeschlossenen Einheit wertet der freigegebene KI-Dienst auch die gespeicherten Aufgaben, Antworten, Fehlversuche und genutzten Hinweise aus und erstellt passende Anschlussübungen. Namen, Zugangsdaten und Familienkennungen werden dafür nicht benötigt. Die Gesamtbewertung und Wiederholungsplanung werden aus den gespeicherten Aktivitäten berechnet.

Fotos werden vor dem Upload zum Drehen und Zuschneiden angezeigt. Ausstehende zugeschnittene Fotos sind auf diesem Gerät 24 Stunden fortsetzbar (höchstens 8 Seiten / 3 MB). Ältere Einträge werden beim nächsten Appstart oder Öffnen des Assistenten bereinigt; Abmelden oder Entfernen löscht diese lokale Warteschlange. Der Server entfernt Metadaten und gibt private Bilder ausschließlich nach Berechtigungsprüfung aus. Eine Verkleinerung ersetzt nicht das Entfernen persönlicher Angaben im Bild.

Sitzungen sind widerrufbar. Eltern können Kinderkonten und ihr eigenes Konto löschen sowie einen Familienexport mit Materialien und Lernverlauf herunterladen. Beim Löschen des Familieninhabers wird dessen gesamte Familie gelöscht; eingeladene Eltern verlieren den Zugriff.

Aufbewahrung im Pilot: Materialien, Einheiten, Antworten, Aktivitäten und Nachrichten höchstens 365 Tage; technische Aufträge 30 Tage; abgelaufene Zugangstokens und Sitzungen weitere 7 Tage; tägliche Backups 14 Tage. Backups müssen vor einer Wiederherstellung mit zwischenzeitlichen Löschungen abgeglichen werden. Abrechnung und Betriebsprotokolle enthalten keine Fotos oder vollständigen Kinderantworten.

Benachrichtigungen sind freiwillig. Erst beim Einschalten auf einem angemeldeten Gerät wird Google Firebase Cloud Messaging initialisiert. Für Kinder ist vorher zusätzlich eine Freigabe durch die Eltern erforderlich. Firebase erhält dabei Installations- und Gerätetokens sowie technische Verbindungsdaten; Namen, Lerninhalte, Noten und Familienkennungen werden nicht mitgesendet. Die Verarbeitung ist nicht auf Deutschland oder die EU beschränkt. Analytics, Werbung und Firebase Authentication werden nicht verwendet. Ohne geeignete Google Play Services ist Android-Push nicht zugesichert. Ausschalten, Abmelden und Rechteentzug sperren den weiteren Versand im Backend. Gerätetokens werden verschlüsselt gespeichert, bei Abmeldung oder Entzug entfernt und nach 60 Tagen ohne Aktualisierung bereinigt; Versandstatus nach 14 Tagen. Das Löschen eines Push-Tokens ist keine Zusage einer sofortigen Löschung sämtlicher Firebase-Installationsdaten oder Google-Backups. Die allgemeinen Push-Freigaben und die tatsächlich beobachtete Zustellung werden getrennt geprüft.

Bei einer Bestellung speichern wir Tarif, Gesamtpreis, Vertragsfassung und Zahlungszuordnung. Zahlungsbelege bleiben für die gesetzliche Aufbewahrung acht Jahre nach Ende des Buchungsjahres erhalten; beim Löschen der Familie wird ihre Kontozuordnung entfernt. Diese Belege enthalten keine Kinderantworten oder Lernmaterialien. Die App liest keine Bankkonten aus; ein Administrator prüft Überweisungen im tatsächlichen Bankkonto.

Es gibt keine Werbung, keinen Verkauf von Kinderprofilen und keine gemeinsame Inhaltsbibliothek aus privaten Lernmaterialien. Aktive Lernzeit bleibt eine Näherung. Eine einzelne richtige Antwort begründet keine sichere Beherrschung; fehlende Nutzung keine Aussage über Verständnis.'''
                        : '''Schulpilot begleitet deinen Lernalltag: vom Foto deiner Heftseiten über Erklärungen und Übungen bis zur passenden Wiederholung.

Kinder lernen in ihrem eigenen Lernraum. Eltern sehen, was schon gelingt, und können helfen, wenn es hakt.

Die Demo enthält vorbereitete Beispiele. In deinem eigenen Konto übst du mit deinem Unterrichtsmaterial und KI-Unterstützung.

Version 0.1.0''',
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
