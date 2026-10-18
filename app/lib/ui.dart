import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'download_panel.dart';

// Shared light-surface palette. Cyan is an accent on navy, not a text color
// on white. Keep secondary text opaque so nested surfaces preserve contrast.
const ink = Color(0xFF14243D);
const teal = Color(0xFF5936CB);
const electric = Color(0xFF37D9EA);
const mint = Color(0xFFEEE9FF);
const cream = Color(0xFFE8EEF6);
const orange = Color(0xFFF4AD54);
const muted = Color(0xFF4C5F79);
const surfaceLow = Color(0xFFF2F5FA);
const surfaceBorder = Color(0xFFB8C6D9);
const controlBorder = Color(0xFF7788A2);
const cyanInk = Color(0xFF006575);
const cyanSurface = Color(0xFFE2F5FA);
const successInk = Color(0xFF16664C);
const successSurface = Color(0xFFE5F5ED);
const warningInk = Color(0xFF80500A);
const warningSurface = Color(0xFFFFF1DA);
const dangerInk = Color(0xFFA82D40);
const dangerSurface = Color(0xFFFFF0F2);

enum PanelTone { neutral, subtle, accent, info, success, warning, danger }

Color panelColor(PanelTone tone) => switch (tone) {
  PanelTone.neutral => Colors.white,
  PanelTone.subtle => surfaceLow,
  PanelTone.accent => mint,
  PanelTone.info => cyanSurface,
  PanelTone.success => successSurface,
  PanelTone.warning => warningSurface,
  PanelTone.danger => dangerSurface,
};

Color panelAccent(PanelTone tone) => switch (tone) {
  PanelTone.neutral || PanelTone.subtle => controlBorder,
  PanelTone.accent => teal,
  PanelTone.info => cyanInk,
  PanelTone.success => successInk,
  PanelTone.warning => warningInk,
  PanelTone.danger => dangerInk,
};

void openRoute(BuildContext context, String path) {
  if (kIsWeb) {
    context.go(path);
  } else {
    context.push(path);
  }
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: teal, surface: Colors.white)
      .copyWith(
        primary: teal,
        onPrimary: Colors.white,
        primaryContainer: mint,
        onPrimaryContainer: ink,
        secondary: cyanInk,
        onSecondary: Colors.white,
        secondaryContainer: cyanSurface,
        onSecondaryContainer: ink,
        surface: Colors.white,
        onSurface: ink,
        onSurfaceVariant: muted,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: surfaceLow,
        surfaceContainer: cream,
        surfaceContainerHigh: const Color(0xFFDDE5F1),
        surfaceContainerHighest: const Color(0xFFD2DDEB),
        outline: controlBorder,
        outlineVariant: surfaceBorder,
        error: dangerInk,
        onError: Colors.white,
        errorContainer: dangerSurface,
        onErrorContainer: dangerInk,
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  final focusSide = WidgetStateProperty.resolveWith<BorderSide>((states) {
    if (states.contains(WidgetState.focused)) {
      return const BorderSide(color: teal, width: 2.5);
    }
    return BorderSide(
      color: states.contains(WidgetState.disabled)
          ? surfaceBorder
          : controlBorder,
      width: 1.25,
    );
  });
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: cream,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineLarge: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: ink,
            height: 1.12,
            letterSpacing: -1.3,
          ),
          headlineMedium: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: ink,
            letterSpacing: -.9,
          ),
          titleLarge: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -.4,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
            height: 1.4,
          ),
          bodyLarge: const TextStyle(fontSize: 16, color: ink, height: 1.55),
          bodyMedium: const TextStyle(fontSize: 15, color: ink, height: 1.5),
          bodySmall: const TextStyle(fontSize: 12, color: muted, height: 1.5),
          labelLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: ink,
      shape: Border(bottom: BorderSide(color: surfaceBorder)),
    ),
    dividerTheme: const DividerThemeData(color: surfaceBorder, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceLow,
      labelStyle: const TextStyle(color: muted, fontSize: 14),
      hintStyle: const TextStyle(color: muted, fontSize: 14),
      helperStyle: const TextStyle(color: muted),
      errorStyle: const TextStyle(color: dangerInk),
      prefixIconColor: muted,
      suffixIconColor: muted,
      floatingLabelStyle: const TextStyle(
        color: teal,
        fontWeight: FontWeight.w700,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: controlBorder, width: 1.25),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: controlBorder, width: 1.25),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: teal, width: 2.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: dangerInk, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: dangerInk, width: 2.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: teal,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFDEE5F0),
            disabledForegroundColor: muted,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
            minimumSize: const Size(48, 52),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            shape: rounded,
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const BorderSide(color: Colors.white, width: 2.5)
                  : BorderSide.none,
            ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: Colors.white,
        disabledForegroundColor: muted,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: rounded,
      ).copyWith(side: focusSide),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(
            foregroundColor: teal,
            disabledForegroundColor: muted,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            shape: rounded,
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const BorderSide(color: teal, width: 2.5)
                  : BorderSide.none,
            ),
          ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style:
          IconButton.styleFrom(
            foregroundColor: muted,
            minimumSize: const Size(48, 48),
            shape: rounded,
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const BorderSide(color: teal, width: 2.5)
                  : BorderSide.none,
            ),
          ),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shadowColor: ink.withValues(alpha: .14),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: surfaceBorder),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: teal,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? Colors.white : muted,
          size: 23,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          color: states.contains(WidgetState.selected) ? teal : muted,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
      height: 76,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: teal,
      unselectedLabelColor: muted,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      unselectedLabelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      indicatorColor: teal,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: surfaceBorder,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      backgroundColor: surfaceLow,
      collapsedBackgroundColor: surfaceLow,
      textColor: ink,
      collapsedTextColor: ink,
      iconColor: teal,
      collapsedIconColor: muted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: controlBorder),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: surfaceBorder),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      clipBehavior: Clip.antiAlias,
    ),
    chipTheme: ChipThemeData(
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color:
              states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.selected)
              ? teal
              : controlBorder,
          width: states.contains(WidgetState.focused) ? 2.5 : 1,
        ),
      ),
      backgroundColor: Colors.white,
      selectedColor: mint,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      labelStyle: const TextStyle(
        color: teal,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        color: ink,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      checkmarkColor: teal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: teal,
      linearTrackColor: Color(0xFFD5DFEE),
      linearMinHeight: 8,
      borderRadius: BorderRadius.all(Radius.circular(6)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      actionTextColor: electric,
      closeIconColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: controlBorder,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: surfaceBorder),
      ),
      textStyle: const TextStyle(color: ink, fontSize: 14),
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(surfaceLow),
      headingTextStyle: TextStyle(color: ink, fontWeight: FontWeight.w700),
      dataTextStyle: TextStyle(color: ink, fontSize: 14),
      dividerThickness: 1,
    ),
    listTileTheme: const ListTileThemeData(
      textColor: ink,
      iconColor: muted,
      selectedColor: teal,
      subtitleTextStyle: TextStyle(color: muted, fontSize: 13, height: 1.45),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
  final PanelTone tone;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.color,
    this.tone = PanelTone.neutral,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => Card(
    semanticContainer: false,
    color: color ?? panelColor(tone),
    elevation: tone == PanelTone.subtle ? 0 : null,
    shape: tone == PanelTone.neutral
        ? null
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: panelAccent(tone).withValues(alpha: .45)),
          ),
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

/// An inset group inside a card, without another raised white card.
class SurfaceInset extends StatelessWidget {
  final Widget child;
  final PanelTone tone;
  final EdgeInsets padding;
  const SurfaceInset({
    super.key,
    required this.child,
    this.tone = PanelTone.subtle,
    this.padding = const EdgeInsets.all(16),
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: panelColor(tone),
      border: Border.all(
        color: tone == PanelTone.subtle || tone == PanelTone.neutral
            ? surfaceBorder
            : panelAccent(tone).withValues(alpha: .45),
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
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
      border: Border.all(color: const Color(0xFF526B94)),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .18),
          blurRadius: 20,
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
                  style:
                      FilledButton.styleFrom(
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
                      ).copyWith(
                        side: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.focused)
                              ? const BorderSide(color: ink, width: 2.5)
                              : BorderSide.none,
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
      color: warning ? warningSurface : cyanSurface,
      border: Border.all(
        color: (warning ? warningInk : cyanInk).withValues(alpha: .45),
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: warning ? warningInk : cyanInk),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: ink, height: 1.5),
          ),
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
      border: Border.all(color: surfaceBorder),
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
          const SizedBox(width: 18, height: 18, child: _ButtonProgress())
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

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress();
  @override
  Widget build(BuildContext context) => CircularProgressIndicator(
    strokeWidth: 2,
    color: DefaultTextStyle.of(context).style.color,
  );
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

  void refresh() => setState(() {
    future = widget.load();
  });
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
    if (!state.isAdmin)
      (
        Icons.translate_rounded,
        'Wörter',
        state.isChild ? '/vocabulary/${state.user!['child_id']}' : '/words',
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
    if (!state.isAdmin &&
        (path.startsWith('/vocabulary/') ||
            path.startsWith('/language-projects/'))) {
      return entries.indexWhere((entry) => entry.$2 == 'Wörter');
    }
    if (state.isChild &&
        (path.startsWith('/unit/') ||
            path.startsWith('/progress/') ||
            path.startsWith('/learning-preparation/'))) {
      return 1;
    }
    if (state.isChild && path.startsWith('/material/')) {
      return entries.indexWhere((entry) => entry.$2 == 'Hefte');
    }
    if (path == '/notifications') return entries.length - 1;
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
      appBar: desktop
          ? null
          : AppBar(
              title: brand(),
              toolbarHeight: 68,
              actions: [NotificationBell(state), const SizedBox(width: 12)],
            ),
      bottomNavigationBar: desktop
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: surfaceBorder)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0F14243D),
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (i) => context.go(entries[i].$3),
                destinations: [
                  for (final entry in entries)
                    NavigationDestination(
                      icon: Icon(entry.$1),
                      label: entry.$2,
                    ),
                ],
              ),
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
                    notificationBell: NotificationBell(state),
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
                            : width < 360
                            ? 16
                            : 20,
                        desktop ? 32 : 24,
                        sidebar
                            ? 36
                            : desktop
                            ? 28
                            : width < 360
                            ? 16
                            : 20,
                        32,
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
                    child: _NavigationSurface(
                      selected: i == selected,
                      child: ListTile(
                        selected: i == selected,
                        focusColor: Colors.transparent,
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

class _NavigationSurface extends StatefulWidget {
  final bool selected;
  final Widget child;
  const _NavigationSurface({required this.selected, required this.child});
  @override
  State<_NavigationSurface> createState() => _NavigationSurfaceState();
}

class _NavigationSurfaceState extends State<_NavigationSurface> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onFocusChange: (value) => setState(() => focused = value),
    child: Material(
      color: focused
          ? const Color(0xFF354B70)
          : widget.selected
          ? const Color(0xFF303A60)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: focused || widget.selected ? electric : Colors.transparent,
          width: focused ? 2.5 : 1,
        ),
      ),
      child: widget.child,
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
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: cyanSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Image.asset(
                'assets/brand/schulpilot-mark.png',
                width: 34,
                excludeFromSemantics: true,
              ),
            ),
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
  final Widget notificationBell;
  const _WorkspaceHeader({
    required this.roleLabel,
    required this.section,
    required this.displayName,
    required this.compact,
    required this.notificationBell,
  });

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('workspace-header'),
    height: 80,
    padding: EdgeInsets.symmetric(horizontal: compact ? 28 : 36),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: surfaceBorder)),
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
        notificationBell,
        const SizedBox(width: 8),
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

class NotificationBell extends StatelessWidget {
  final AppState state;
  const NotificationBell(this.state, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state.inbox,
    builder: (context, _) => IconButton.outlined(
      key: const ValueKey('notification-bell'),
      tooltip: state.isAdmin ? 'Push-Status' : 'Benachrichtigungen',
      style:
          IconButton.styleFrom(
            backgroundColor: surfaceLow,
            foregroundColor: ink,
            side: const BorderSide(color: controlBorder),
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.focused)
                    ? teal
                    : controlBorder,
                width: states.contains(WidgetState.focused) ? 2.5 : 1,
              ),
            ),
          ),
      onPressed: () =>
          context.go(state.isAdmin ? '/admin/push' : '/notifications'),
      icon: Badge(
        isLabelVisible: !state.isAdmin && state.inbox.unread > 0,
        label: Text('${state.inbox.unread > 99 ? '99+' : state.inbox.unread}'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
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
            Semantics(
              header: true,
              child: Text(
                title!,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontSize: constraints.maxWidth < 500 ? 28 : 32),
              ),
            ),
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
            Semantics(
              header: true,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
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
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: teal, size: 22),
            ),
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
