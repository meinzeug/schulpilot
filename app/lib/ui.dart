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
      labelStyle: const TextStyle(
        color: ink,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        color: ink,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      checkmarkColor: ink,
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
  final Object? revision;
  const LoadView({
    super.key,
    required this.load,
    required this.builder,
    this.revision,
  });
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

  @override
  void didUpdateWidget(covariant LoadView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision) future = widget.load();
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
  Widget build(BuildContext context) => WorkspaceShell(
    state: state,
    title: title,
    subtitle: subtitle,
    actions: actions,
    showTitle: showTitle,
    browser: kIsWeb,
    child: child,
  );
}

/// Shared page content with navigation suited to its browser or native host.
class WorkspaceShell extends StatelessWidget {
  final AppState state;
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final bool showTitle;
  final bool browser;

  const WorkspaceShell({
    super.key,
    required this.state,
    required this.title,
    this.subtitle,
    required this.child,
    required this.browser,
    this.actions = const [],
    this.showTitle = true,
  });

  String get _roleLabel => state.isChild
      ? 'Dein Lernraum'
      : state.isAdmin
      ? 'Administration'
      : 'Familienbereich';

  List<(IconData, String, String)> _entries({required bool sidebar}) => [
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
    if (state.isAdmin) ...[
      (Icons.tune_rounded, 'Einrichtung', '/admin/settings'),
      if (sidebar) ...[
        (Icons.storefront_outlined, 'Verkauf', '/admin/verkauf'),
        (Icons.notifications_outlined, 'Push', '/admin/push'),
      ],
    ],
    if (browser && state.isOwner && !state.isDemo)
      (Icons.receipt_long_outlined, 'Tarif', '/bestellungen'),
    (Icons.person_outline_rounded, 'Konto', '/settings'),
  ];

  int _selected(List<(IconData, String, String)> entries, String path) {
    final index = entries.indexWhere((entry) => path == entry.$3);
    if (index >= 0) return index;
    if (state.isChild && path.startsWith('/unit/')) return 1;
    if (state.isChild && path.startsWith('/material/')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final sidebar = browser && width >= 1050;
    final rail = browser && !sidebar && width >= 720;
    final desktop = sidebar || rail;
    final path = GoRouterState.of(context).uri.path;
    final entries = _entries(sidebar: sidebar);
    final selected = _selected(entries, path);
    final maxWidth = state.isChild
        ? 1060.0
        : state.isAdmin
        ? 1440.0
        : 1360.0;
    final name = (state.user?['display_name'] as String?)?.trim();
    final displayName = name == null || name.isEmpty ? 'Konto' : name;

    return Scaffold(
      appBar: desktop ? null : AppBar(title: brand(), toolbarHeight: 68),
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (i) => context.go(entries[i].$3),
              destinations: [
                for (final entry in entries)
                  NavigationDestination(icon: Icon(entry.$1), label: entry.$2),
              ],
            ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sidebar)
            _WorkspaceSidebar(
              entries: entries,
              selected: selected,
              roleLabel: _roleLabel,
            ),
          if (rail) _WorkspaceRail(entries: entries, selected: selected),
          Expanded(
            child: Column(
              children: [
                if (desktop)
                  _WorkspaceHeader(
                    roleLabel: _roleLabel,
                    section: state.isAdmin && path == '/admin/verkauf'
                        ? 'Verkauf'
                        : state.isAdmin && path == '/admin/push'
                        ? 'Push'
                        : entries[selected].$2,
                    displayName: displayName,
                    compact: rail,
                  ),
                Expanded(
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      key: const ValueKey('workspace-scroll'),
                      padding: EdgeInsets.fromLTRB(
                        sidebar
                            ? 36
                            : desktop
                            ? 28
                            : 20,
                        desktop ? 32 : 24,
                        sidebar
                            ? 36
                            : desktop
                            ? 28
                            : 20,
                        24,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Column(
                            key: const ValueKey('workspace-content'),
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
                              if (showTitle || actions.isNotEmpty) ...[
                                _WorkspaceHeading(
                                  title: showTitle ? title : null,
                                  subtitle: showTitle ? subtitle : null,
                                  actions: actions,
                                ),
                                const SizedBox(height: 26),
                              ],
                              child,
                              if (browser && path == '/app') ...[
                                const SizedBox(height: 28),
                                AndroidDownload(state.api),
                              ],
                              if (!state.isChild || path == '/settings') ...[
                                const SizedBox(height: 24),
                                Wrap(
                                  spacing: 12,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          openRoute(context, '/privacy'),
                                      child: const Text('Datenschutz'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          openRoute(context, '/about'),
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
          ),
        ],
      ),
    );
  }
}

class _WorkspaceSidebar extends StatelessWidget {
  final List<(IconData, String, String)> entries;
  final int selected;
  final String roleLabel;

  const _WorkspaceSidebar({
    required this.entries,
    required this.selected,
    required this.roleLabel,
  });

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('workspace-sidebar'),
    width: 248,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [ink, Color(0xFF111A30)],
      ),
      border: Border(right: BorderSide(color: Color(0xFF354361))),
    ),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
            child: brand(light: true),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 20, 16),
            child: Text(
              roleLabel,
              style: const TextStyle(
                color: Color(0xFFBBC9E0),
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: .4,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (var i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: i == selected
                          ? const Color(0xFF303A60)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        selected: i == selected,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: Icon(
                          entries[i].$1,
                          color: i == selected
                              ? electric
                              : const Color(0xFFBBC9E0),
                          size: 22,
                        ),
                        title: Text(
                          entries[i].$2,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: i == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        onTap: () => context.go(entries[i].$3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _WorkspaceRail extends StatelessWidget {
  final List<(IconData, String, String)> entries;
  final int selected;
  const _WorkspaceRail({required this.entries, required this.selected});

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('workspace-rail'),
    width: 104,
    color: ink,
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Image.asset('assets/brand/schulpilot-mark.png', width: 34),
          ),
          Expanded(
            child: NavigationRail(
              scrollable: true,
              minWidth: 104,
              backgroundColor: ink,
              indicatorColor: const Color(0xFF303A60),
              selectedIconTheme: const IconThemeData(color: electric),
              unselectedIconTheme: const IconThemeData(
                color: Color(0xFFBBC9E0),
              ),
              selectedLabelTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: Color(0xFFBBC9E0),
                fontSize: 12,
              ),
              labelType: NavigationRailLabelType.all,
              selectedIndex: selected,
              onDestinationSelected: (i) => context.go(entries[i].$3),
              destinations: [
                for (final entry in entries)
                  NavigationRailDestination(
                    icon: Icon(entry.$1),
                    label: Text(entry.$2),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _WorkspaceHeader extends StatelessWidget {
  final String roleLabel;
  final String section;
  final String displayName;
  final bool compact;
  const _WorkspaceHeader({
    required this.roleLabel,
    required this.section,
    required this.displayName,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('workspace-header'),
    height: 80,
    padding: EdgeInsets.symmetric(horizontal: compact ? 28 : 36),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE2E7F0))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: muted,
                  size: 18,
                ),
              ),
              Flexible(
                child: Text(
                  section,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Tooltip(
          message: 'Konto öffnen',
          child: TextButton(
            onPressed: () => context.go('/settings'),
            style: TextButton.styleFrom(
              foregroundColor: ink,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: mint,
                  foregroundColor: teal,
                  child: Text(displayName.characters.first.toUpperCase()),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 140 : 200),
                  child: Text(
                    displayName,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _WorkspaceHeading extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  const _WorkspaceHeading({this.title, this.subtitle, required this.actions});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(title!, style: Theme.of(context).textTheme.headlineMedium),
          if (subtitle?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(subtitle!, style: const TextStyle(color: muted)),
            ),
        ],
      );
      if (constraints.maxWidth >= 760 && title != null && actions.isNotEmpty) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 24),
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) heading,
          if (title != null && actions.isNotEmpty) const SizedBox(height: 16),
          if (actions.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    },
  );
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
