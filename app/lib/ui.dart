import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'download_panel.dart';

const ink = Color(0xFF17243C);
const teal = Color(0xFF7047EB);
const electric = Color(0xFF37D9EA);
const mint = Color(0xFFEEF0FF);
const cream = Color(0xFFF5F7FC);
const orange = Color(0xFFF4AD54);
const muted = Color(0xFF718096);

void openRoute(BuildContext context, String path) {
  if (kIsWeb) {
    context.go(path);
  } else {
    context.push(path);
  }
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: teal,
    surface: Colors.white,
  ).copyWith(secondary: electric);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: cream,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        color: ink,
        height: 1.12,
        letterSpacing: -1.3,
      ),
      headlineMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        color: ink,
        letterSpacing: -.9,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -.4,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.45),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE8EDF6),
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8FAFE),
      floatingLabelStyle: const TextStyle(color: teal),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE1E7F2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE1E7F2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: teal, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: teal,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: Color(0xFFDDE4F0)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFE6EBF4)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: mint,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      height: 72,
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: mint,
      selectedColor: const Color(0xFFDFE2FF),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: teal,
      linearTrackColor: Color(0xFFE3E6FB),
      linearMinHeight: 6,
      borderRadius: BorderRadius.all(Radius.circular(6)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          color: const Color(0xFFEAF8FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Image.asset(
          'assets/brand/schulpilot-mark.png',
          width: 30,
          height: 30,
          excludeFromSemantics: true,
        ),
      ),
      const SizedBox(width: 11),
      Text(
        'SCHULPILOT',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
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
    semanticContainer: false,
    color: color,
    child: Padding(
      padding:
          MediaQuery.sizeOf(context).width < 600 &&
              padding == const EdgeInsets.all(24)
          ? const EdgeInsets.all(20)
          : padding,
      child: child,
    ),
  );
}

/// A single, prominent next step with the same layout on mobile and web.
class FocusCard extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final IconData icon;
  final Widget action;
  const FocusCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.action,
    this.icon = Icons.auto_stories_rounded,
  });

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: electric.withValues(alpha: .3)),
      boxShadow: [
        BoxShadow(
          color: teal.withValues(alpha: .12),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF111C34), Color(0xFF31235E)],
      ),
    ),
    child: Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _CircuitPainter())),
        ),
        Positioned(
          right: -36,
          top: -35,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .05),
            ),
          ),
        ),
        Positioned(
          right: 32,
          top: 32,
          child: Icon(
            icon,
            size: 58,
            color: Colors.white.withValues(alpha: .12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  color: electric,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(right: 30),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 29,
                    height: 1.15,
                    letterSpacing: -.7,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFFD4D4EE), height: 1.5),
              ),
              const SizedBox(height: 24),
              FilledButtonTheme(
                data: FilledButtonThemeData(
                  style: FilledButton.styleFrom(
                    backgroundColor: electric,
                    foregroundColor: const Color(0xFF101B31),
                    minimumSize: const Size(48, 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 16,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                child: action,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CircuitPainter extends CustomPainter {
  const _CircuitPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = electric.withValues(alpha: .045)
      ..strokeWidth = .7;
    for (double x = size.width * .55; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(size.width * .55, y), Offset(size.width, y), grid);
    }
    final line = Paint()
      ..color = electric.withValues(alpha: .32)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width - 94, 0)
      ..lineTo(size.width - 94, 26)
      ..lineTo(size.width - 70, 50)
      ..lineTo(size.width, 50);
    canvas.drawPath(path, line);
    canvas.drawCircle(
      Offset(size.width - 94, 26),
      3,
      Paint()..color = electric.withValues(alpha: .6),
    );
    canvas.drawLine(
      Offset(0, size.height - 4),
      Offset(size.width * .2, size.height - 4),
      line,
    );
  }

  @override
  bool shouldRepaint(_CircuitPainter oldDelegate) => false;
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
        showCloseIcon: true,
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
  final bool showTitle;
  const PageFrame({
    super.key,
    required this.state,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions = const [],
    this.showTitle = true,
  });
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final uri = GoRouterState.of(context).uri.path;
    final entries = <(IconData, String, String)>[
      (
        Icons.grid_view_rounded,
        state.isChild
            ? 'Heute'
            : state.isAdmin
            ? 'Betrieb'
            : 'Familie',
        state.isAdmin ? '/admin' : '/app',
      ),
      if (state.isChild)
        (
          Icons.auto_stories_rounded,
          'Lernen',
          '/learn/${state.user!['child_id']}',
        ),
      if (state.isChild)
        (
          Icons.folder_open_rounded,
          'Hefte',
          '/library/${state.user!['child_id']}',
        ),
      if (state.isAdmin) (Icons.tune_rounded, 'Einrichtung', '/admin/settings'),
      if (kIsWeb && state.isOwner && !state.isDemo)
        (Icons.receipt_long_outlined, 'Tarif', '/bestellungen'),
      (Icons.person_outline_rounded, 'Konto', '/settings'),
    ];
    var selected = entries.indexWhere(
      (e) =>
          uri == e.$3 ||
          (e.$3.contains('after-school') && uri.startsWith(e.$3)),
    );
    if (selected < 0) selected = 0;
    if (state.isChild && uri.startsWith('/unit/')) selected = 1;
    if (state.isChild && uri.startsWith('/material/')) selected = 2;
    Widget sidebar() => Container(
      width: 252,
      padding: const EdgeInsets.fromLTRB(24, 34, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17243C), Color(0xFF111A30)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          brand(light: true),
          const SizedBox(height: 48),
          for (var i = 0; i < entries.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: selected == i
                      ? Colors.white.withValues(alpha: .12)
                      : null,
                  leading: Icon(
                    entries[i].$1,
                    color: selected == i
                        ? const Color(0xFFC7CBFF)
                        : Colors.white54,
                    size: 22,
                  ),
                  title: Text(
                    entries[i].$2,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: selected == i
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  onTap: () => context.go(entries[i].$3),
                ),
              ),
            ),
          const Spacer(),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF333D60),
              child: Text(
                ((state.user?['display_name'] as String?)?.trim().isNotEmpty ==
                            true
                        ? state.user!['display_name'] as String
                        : 'S')
                    .characters
                    .first,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              state.user?['display_name'] ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            subtitle: Text(
              state.isChild
                  ? 'Dein Lernraum'
                  : state.isParent
                  ? 'Elternkonto'
                  : 'Administration',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            onTap: () => context.go('/settings'),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: wide ? null : AppBar(title: brand(), toolbarHeight: 68),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (i) => context.go(entries[i].$3),
              destinations: [
                for (final e in entries)
                  NavigationDestination(icon: Icon(e.$1), label: e.$2),
              ],
            ),
      body: Row(
        children: [
          if (wide) sidebar(),
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  wide ? 44 : 20,
                  wide ? 40 : 24,
                  wide ? 44 : 20,
                  24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (state.isDemo)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 20),
                            child: Tag('Demo · nur Beispieldaten'),
                          ),
                        if (!state.isDemo &&
                            !state.isAdmin &&
                            state.user?['real_data_enabled'] == false)
                          const Notice(
                            'Testbetrieb · Bitte noch keine echten Kinderdaten eingeben.',
                          ),
                        if (showTitle)
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
                                    if (subtitle != null &&
                                        subtitle!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          subtitle!,
                                          style: const TextStyle(color: muted),
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
                        if (showTitle) const SizedBox(height: 26),
                        child,
                        if (kIsWeb && uri == '/app') ...[
                          const SizedBox(height: 28),
                          AndroidDownload(state.api),
                        ],
                        if (!state.isChild || uri == '/settings') ...[
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
                            ],
                          ),
                        ],
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
