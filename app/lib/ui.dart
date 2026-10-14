import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'download_panel.dart';

const ink = Color(0xFF173B40);
const teal = Color(0xFF19766D);
const mint = Color(0xFFE9F4EC);
const cream = Color(0xFFF7F8F2);
const orange = Color(0xFFE8A05B);
const muted = Color(0xFF647576);

void openRoute(BuildContext context, String path) {
  if (kIsWeb) {
    context.go(path);
  } else {
    context.push(path);
  }
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: teal, surface: Colors.white);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: cream,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        color: ink,
        height: 1.15,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.55),
      bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD9E2DE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD9E2DE)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: teal,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 19),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Color(0xFFD4DFD9)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE2E8DF)),
      ),
    ),
  );
}

Widget brand({bool light = false}) => FittedBox(
  fit: BoxFit.scaleDown,
  alignment: Alignment.centerLeft,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: light ? Colors.white.withValues(alpha: .12) : teal,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.near_me_rounded, color: Colors.white, size: 25),
      ),
      const SizedBox(width: 11),
      Text(
        'SCHULPILOT',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: light ? Colors.white : ink,
        ),
      ),
    ],
  ),
);

class Panel extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: Padding(padding: padding, child: child),
  );
}

class Notice extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool warning;
  const Notice(
    this.text, {
    super.key,
    this.icon = Icons.info_outline_rounded,
    this.warning = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFF1DE) : mint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: warning ? const Color(0xFF8B571D) : teal),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
        ),
      ],
    ),
  );
}

class Tag extends StatelessWidget {
  final String text;
  final Color color;
  const Tag(this.text, {super.key, this.color = mint});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
  );
}

class ActionButton extends StatefulWidget {
  final String label;
  final Future<void> Function() onPressed;
  final IconData? icon;
  final bool secondary;
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
  });
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 19),
        if (busy || widget.icon != null) const SizedBox(width: 9),
        Flexible(child: Text(busy ? 'Bitte warten …' : widget.label)),
      ],
    );
    Future<void> pressed() async {
      setState(() => busy = true);
      try {
        await widget.onPressed();
      } catch (e) {
        if (context.mounted) showError(context, e);
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }

    return widget.secondary
        ? OutlinedButton(onPressed: busy ? null : pressed, child: child)
        : FilledButton(onPressed: busy ? null : pressed, child: child);
  }
}

void showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is ApiError ? error.message : 'Die Aktion konnte nicht abgeschlossen werden. Bitte erneut versuchen.',
        ),
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
      ),
    );
void toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
    .showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );

class LoadView<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(T, VoidCallback) builder;
  const LoadView({super.key, required this.load, required this.builder});
  @override
  State<LoadView<T>> createState() => _LoadViewState<T>();
}

class _LoadViewState<T> extends State<LoadView<T>> {
  late Future<T> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  void refresh() => setState(() => future = widget.load());
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(snapshot.error.toString()),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: refresh,
                child: const Text('Erneut laden'),
              ),
            ],
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(64),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return widget.builder(snapshot.data as T, refresh);
    },
  );
}

class PageFrame extends StatelessWidget {
  final AppState state;
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  const PageFrame({
    super.key,
    required this.state,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final uri = GoRouterState.of(context).uri.path;
    Widget nav() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        brand(light: true),
        const SizedBox(height: 46),
        Text(
          state.isChild
              ? 'DEIN LERNRAUM'
              : state.isAdmin
              ? 'PLATTFORM'
              : 'FÜR DEINE FAMILIE',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .55),
            fontSize: 10,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 16),
        for (final entry in [
          (
            Icons.space_dashboard_outlined,
            state.isChild ? 'Mein Tag' : 'Überblick',
            '/app',
          ),
          (Icons.tune_rounded, 'Zugänge & Einstellungen', '/settings'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              tileColor: uri == entry.$3
                  ? Colors.white.withValues(alpha: .12)
                  : null,
              leading: Icon(entry.$1, color: Colors.white70, size: 21),
              title: Text(
                entry.$2,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              onTap: () => context.go(entry.$3),
            ),
          ),
        if (state.isAdmin)
          ListTile(
            leading: const Icon(Icons.shield_outlined, color: Colors.white70),
            title: const Text(
              'KI & Betrieb',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () => context.go('/admin'),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.favorite_outline_rounded,
                color: Color(0xFFB1D8BB),
              ),
              const SizedBox(height: 10),
              const Text(
                'Ein kleiner Schritt\nreicht für heute.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Lernen in deinem Tempo.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(
            backgroundColor: Color(0xFF517371),
            child: Icon(Icons.person_outline, color: Colors.white),
          ),
          title: Text(
            state.user?['display_name'] ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          subtitle: Text(
            state.isParent
                ? 'Elternkonto'
                : state.isChild
                ? 'Kinderkonto'
                : 'Administrator',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: wide
          ? null
          : AppBar(
              backgroundColor: cream,
              title: brand(),
              actions: [
                IconButton(
                  tooltip: 'Überblick',
                  onPressed: () => context.go('/app'),
                  icon: const Icon(Icons.home_outlined),
                ),
                IconButton(
                  tooltip: 'Einstellungen',
                  onPressed: () => context.go('/settings'),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
      body: Row(
        children: [
          if (wide)
            Container(
              width: 252,
              color: ink,
              padding: const EdgeInsets.fromLTRB(22, 32, 22, 22),
              child: Material(color: ink, child: nav()),
            ),
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(wide ? 38 : 18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (state.isDemo)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 22),
                            child: Notice(
                              'Synthetischer Testraum · eigene Testfamilie · automatische Löschung nach 24 Stunden. Bitte keine echten Kinderdaten eingeben.',
                              icon: Icons.science_outlined,
                            ),
                          ),
                        if (!state.isDemo &&
                            !state.isAdmin &&
                            state.user?['real_data_enabled'] == false)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 22),
                            child: Notice(
                              'Testbetrieb · Bitte ausschließlich synthetische Kinderprofile und Lernangaben verwenden. Die Verarbeitung echter Kinderdaten ist noch nicht freigegeben.',
                              icon: Icons.science_outlined,
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                  if (subtitle != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        subtitle!,
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (wide) ...actions,
                          ],
                        ),
                        if (!wide && actions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: actions,
                            ),
                          ),
                        const SizedBox(height: 28),
                        child,
                        const SizedBox(height: 34),
                        if (kIsWeb) ...[
                          AndroidDownload(state.api),
                          const SizedBox(height: 24),
                        ],
                        Wrap(
                          spacing: 18,
                          children: [
                            TextButton(
                              onPressed: () => openRoute(context, '/privacy'),
                              child: const Text('Datenschutz & Transparenz'),
                            ),
                            TextButton(
                              onPressed: () => openRoute(context, '/about'),
                              child: const Text('Projektstatus'),
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
        ],
      ),
    );
  }
}

Widget heading(String title, {String? subtitle, Widget? trailing}) => Padding(
  padding: const EdgeInsets.only(top: 6, bottom: 18),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  subtitle,
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
      ?trailing,
    ],
  ),
);

Widget stat(String value, String label, IconData icon, {Color color = mint}) =>
    SizedBox(
      width: 200,
      child: Panel(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: teal, size: 22),
            const SizedBox(height: 15),
            Text(
              value,
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 12, color: muted)),
          ],
        ),
      ),
    );

String statusLabel(String? status) => switch (status) {
  'not_started' => 'Nicht begonnen',
  'active' => 'Begonnen',
  'paused' => 'Pausiert',
  'practiced_today' => 'Heute schon geübt',
  'completed' => 'Abgeschlossen',
  _ => status ?? '',
};
String typeLabel(String? type) => switch (type) {
  'choice' => 'Auswahl',
  'gap' => 'Lückentext',
  'match' => 'Zuordnung',
  'short' => 'Kurze Antwort',
  _ => type ?? '',
};
String outcomeLabel(String? outcome) => switch (outcome) {
  'correct' => 'Richtig',
  'incorrect' => 'Noch nicht richtig',
  'uncertain' => 'Nicht sicher bewertbar',
  _ => outcome ?? '',
};

Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String text,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bestätigen'),
          ),
        ],
      ),
    ) ??
    false;
