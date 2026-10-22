import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'app_palette.dart';
export 'app_palette.dart';
import 'download_panel.dart';
import 'schulbuddy.dart';

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

VoidCallback _workspaceLink(BuildContext context, AppState state, String path) {
  final owner = state.user;
  final family = state.familyId;
  final route = ModalRoute.of(context);
  return () {
    if (!context.mounted ||
        owner == null ||
        !identical(state.user, owner) ||
        state.familyId != family ||
        route?.isCurrent == false) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    context.go(path);
  };
}

ValueChanged<int> _workspaceSelection(
  BuildContext context,
  AppState state,
  List<(IconData, String, String)> entries,
) {
  final actions = [
    for (final entry in entries) _workspaceLink(context, state, entry.$3),
  ];
  return (index) {
    if (index >= 0 && index < actions.length) actions[index]();
  };
}

ThemeData appTheme({Brightness brightness = Brightness.light}) {
  final p = AppPalette(isDark: brightness == Brightness.dark);
  final ink = p.ink,
      teal = p.teal,
      mint = p.mint,
      cream = p.cream,
      muted = p.muted,
      surfaceLow = p.surfaceLow,
      surfaceBorder = p.surfaceBorder,
      controlBorder = p.controlBorder,
      cyanInk = p.cyanInk,
      cyanSurface = p.cyanSurface,
      dangerInk = p.dangerInk;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.actionPurple,
        brightness: brightness,
        surface: p.panelSurface,
      ).copyWith(
        primary: p.actionPurple,
        onPrimary: Colors.white,
        primaryContainer: mint,
        onPrimaryContainer: ink,
        secondary: cyanInk,
        onSecondary: p.isDark ? const Color(0xFF081F31) : Colors.white,
        secondaryContainer: cyanSurface,
        onSecondaryContainer: ink,
        surface: p.panelSurface,
        onSurface: ink,
        onSurfaceVariant: muted,
        surfaceContainerLowest: p.panelSurface,
        surfaceContainerLow: surfaceLow,
        surfaceContainer: cream,
        surfaceContainerHigh: p.surfaceHigh,
        surfaceContainerHighest: p.surfaceHigh,
        outline: controlBorder,
        outlineVariant: surfaceBorder,
        error: dangerInk,
        onError: p.isDark ? const Color(0xFF081F31) : Colors.white,
        errorContainer: p.dangerSurface,
        onErrorContainer: dangerInk,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Nunito',
    colorScheme: scheme,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  final focusSide = WidgetStateProperty.resolveWith<BorderSide>((states) {
    if (states.contains(WidgetState.focused)) {
      return BorderSide(color: teal, width: 2.5);
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
    brightness: brightness,
    fontFamily: 'Nunito',
    colorScheme: scheme,
    scaffoldBackgroundColor: cream,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineLarge: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: ink,
            height: 1.12,
            letterSpacing: -1.3,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: ink,
            letterSpacing: -.9,
          ),
          titleLarge: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -.4,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
            height: 1.4,
          ),
          bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.55),
          bodyMedium: TextStyle(fontSize: 15, color: ink, height: 1.5),
          bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.5),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.panelSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: ink,
      shape: Border(bottom: BorderSide(color: surfaceBorder)),
    ),
    dividerTheme: DividerThemeData(color: surfaceBorder, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceLow,
      labelStyle: TextStyle(color: muted, fontSize: 14),
      hintStyle: TextStyle(color: muted, fontSize: 14),
      helperStyle: TextStyle(color: muted),
      errorStyle: TextStyle(color: dangerInk),
      prefixIconColor: muted,
      suffixIconColor: muted,
      floatingLabelStyle: TextStyle(color: teal, fontWeight: FontWeight.w700),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: controlBorder, width: 1.25),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: controlBorder, width: 1.25),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: teal, width: 2.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dangerInk, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dangerInk, width: 2.5),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: p.actionPurple,
            foregroundColor: Colors.white,
            disabledBackgroundColor: p.surfaceHigh,
            disabledForegroundColor: muted,
            textStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            minimumSize: Size(48, 52),
            padding: EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            shape: rounded,
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? BorderSide(color: Colors.white, width: 2.5)
                  : BorderSide.none,
            ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: p.panelSurface,
        disabledForegroundColor: muted,
        textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        minimumSize: Size(48, 48),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: rounded,
      ).copyWith(side: focusSide),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(
            foregroundColor: teal,
            disabledForegroundColor: muted,
            minimumSize: Size(48, 48),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            shape: rounded,
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? BorderSide(color: teal, width: 2.5)
                  : BorderSide.none,
            ),
          ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style:
          IconButton.styleFrom(
            foregroundColor: muted,
            minimumSize: Size(48, 48),
            shape: rounded,
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? BorderSide(color: teal, width: 2.5)
                  : BorderSide.none,
            ),
          ),
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shadowColor: ink.withValues(alpha: .14),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      color: p.panelSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: surfaceBorder),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.panelSurface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.actionPurple,
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
    tabBarTheme: TabBarThemeData(
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
        side: BorderSide(color: controlBorder),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: surfaceBorder),
      ),
      tilePadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      childrenPadding: EdgeInsets.fromLTRB(16, 4, 16, 16),
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
      backgroundColor: p.panelSurface,
      selectedColor: mint,
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      labelStyle: TextStyle(
        color: teal,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: TextStyle(
        color: ink,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      checkmarkColor: teal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: teal,
      linearTrackColor: p.surfaceHigh,
      linearMinHeight: 8,
      borderRadius: BorderRadius.all(Radius.circular(6)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.isDark ? p.surfaceHigh : ink,
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 14),
      actionTextColor: electric,
      closeIconColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.panelSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.panelSurface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: controlBorder,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.panelSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: surfaceBorder),
      ),
      textStyle: TextStyle(color: ink, fontSize: 14),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(surfaceLow),
      headingTextStyle: TextStyle(color: ink, fontWeight: FontWeight.w700),
      dataTextStyle: TextStyle(color: ink, fontSize: 14),
      dividerThickness: 1,
    ),
    listTileTheme: ListTileThemeData(
      textColor: ink,
      iconColor: muted,
      selectedColor: teal,
      subtitleTextStyle: TextStyle(color: muted, fontSize: 13, height: 1.45),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.isDark ? p.surfaceHigh : ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(color: Colors.white, fontSize: 13),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
  );
}

Widget brand({bool light = false}) => Builder(
  builder: (context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Color(0xFFEAF8FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Image.asset(
            'assets/brand/schulpilot-mark.png',
            width: 30,
            height: 30,
            excludeFromSemantics: true,
          ),
        ),
        SizedBox(width: 11),
        Text(
          'SCHULPILOT',
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 19,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
            color: light ? Colors.white : context.palette.ink,
          ),
        ),
      ],
    ),
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
    color: context.palette.surface(color ?? panelColor(tone)),
    elevation: tone == PanelTone.subtle ? 0 : null,
    shape: tone == PanelTone.neutral
        ? null
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: context.palette
                  .resolve(panelAccent(tone))
                  .withValues(alpha: .65),
            ),
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

/// A summary with one clear destination. Keep editable fields, selectable text
/// and secondary controls outside this card; they need their own focus targets.
class ActionPanel extends StatefulWidget {
  final Widget child;
  final String actionLabel;
  final FutureOr<void> Function()? onPressed;
  final PanelTone tone;
  final Color? color;
  final EdgeInsets padding;
  final bool enabled;

  const ActionPanel({
    super.key,
    required this.child,
    required this.actionLabel,
    required this.onPressed,
    this.tone = PanelTone.neutral,
    this.color,
    this.padding = const EdgeInsets.all(24),
    this.enabled = true,
  });

  @override
  State<ActionPanel> createState() => _ActionPanelState();
}

class _ActionPanelState extends State<ActionPanel> {
  bool focused = false;
  bool activationQueued = false;
  bool busy = false;
  bool get enabled => widget.enabled && widget.onPressed != null && !busy;

  Future<void> activateCard() async {
    if (!mounted ||
        !enabled ||
        activationQueued ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    activationQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      activationQueued = false;
    });
    final action = widget.onPressed!;
    final route = ModalRoute.of(context);
    setState(() => busy = true);
    try {
      await Future<void>.sync(action);
    } catch (error) {
      if (mounted &&
          route?.isCurrent != false &&
          identical(widget.onPressed, action)) {
        showError(context, error);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final padding =
        MediaQuery.sizeOf(context).width < 600 &&
            widget.padding == const EdgeInsets.all(24)
        ? const EdgeInsets.all(20)
        : widget.padding;
    return MergeSemantics(
      child: Semantics(
        container: true,
        button: true,
        enabled: enabled,
        liveRegion: busy,
        onTap: enabled ? activateCard : null,
        child: Card(
          semanticContainer: false,
          color: p.surface(widget.color ?? panelColor(widget.tone)),
          clipBehavior: Clip.antiAlias,
          elevation: widget.tone == PanelTone.subtle ? 0 : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: focused ? p.teal : p.resolve(panelAccent(widget.tone)),
              width: focused ? 2.5 : 1,
            ),
          ),
          child: InkWell(
            excludeFromSemantics: true,
            onTap: enabled ? activateCard : null,
            onFocusChange: (value) {
              if (mounted && focused != value) setState(() => focused = value);
            },
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  widget.child,
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          busy
                              ? '${widget.actionLabel}: Bitte warten …'
                              : widget.actionLabel,
                          style: TextStyle(
                            color: enabled ? p.teal : p.muted,
                            fontWeight: FontWeight.w800,
                            decoration: enabled
                                ? TextDecoration.underline
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ExcludeSemantics(
                        child: busy
                            ? TickerMode(
                                enabled:
                                    ModalRoute.of(context)?.isCurrent != false,
                                child: const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : Icon(
                                enabled
                                    ? Icons.arrow_forward_rounded
                                    : Icons.lock_outline_rounded,
                                color: enabled ? p.teal : p.muted,
                              ),
                      ),
                    ],
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
  Widget build(BuildContext context) => Material(
    color: context.palette.surface(panelColor(tone)),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: tone == PanelTone.subtle || tone == PanelTone.neutral
            ? context.palette.surfaceBorder
            : context.palette.resolve(panelAccent(tone)).withValues(alpha: .65),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
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
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      color: context.palette.mint,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: context.palette.controlBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: context.palette.teal, size: 25),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                eyebrow,
                style: TextStyle(
                  color: context.palette.teal,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontSize: 29),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: TextStyle(color: context.palette.muted, height: 1.5),
        ),
        const SizedBox(height: 24),
        Align(alignment: Alignment.centerLeft, child: action),
      ],
    ),
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
      color: warning
          ? context.palette.warningSurface
          : context.palette.cyanSurface,
      border: Border.all(
        color: (warning ? context.palette.warningInk : context.palette.cyanInk)
            .withValues(alpha: .65),
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: warning ? context.palette.warningInk : context.palette.cyanInk,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: context.palette.ink,
              height: 1.5,
            ),
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
      color: context.palette.surface(color),
      border: Border.all(color: context.palette.surfaceBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.palette.ink,
      ),
    ),
  );
}

class ActionButton extends StatefulWidget {
  final String label;
  final Future<void> Function() onPressed;
  final IconData? icon;
  final bool secondary;
  final bool enabled;
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.enabled = true,
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
      if (!mounted || busy || !widget.enabled) return;
      setState(() => busy = true);
      final action = widget.onPressed;
      try {
        await action();
      } catch (e) {
        if (context.mounted) showError(context, e);
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }

    final accessibleChild = Semantics(
      liveRegion: busy,
      label: busy ? '${widget.label}: Bitte warten …' : widget.label,
      excludeSemantics: true,
      child: child,
    );
    return widget.secondary
        ? OutlinedButton(
            onPressed: busy || !widget.enabled ? null : pressed,
            child: accessibleChild,
          )
        : FilledButton(
            onPressed: busy || !widget.enabled ? null : pressed,
            child: accessibleChild,
          );
  }
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress();
  @override
  Widget build(BuildContext context) => TickerMode(
    enabled:
        ModalRoute.of(context)?.isCurrent != false &&
        !MediaQuery.disableAnimationsOf(context),
    child: CircularProgressIndicator(
      value: MediaQuery.disableAnimationsOf(context) ? .65 : null,
      strokeWidth: 2,
      color: DefaultTextStyle.of(context).style.color,
    ),
  );
}

void popCurrentRoute<T>(BuildContext context, [T? result]) {
  if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
    Navigator.pop(context, result);
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
void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        showCloseIcon: true,
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
      ),
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
  int request = 0;
  bool pending = false;

  void startLoad() {
    final current = ++request;
    pending = true;
    future = Future<T>.sync(widget.load).whenComplete(() {
      if (mounted && current == request) pending = false;
    });
  }

  @override
  void initState() {
    super.initState();
    startLoad();
  }

  @override
  void didUpdateWidget(covariant LoadView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision) startLoad();
  }

  void refresh() {
    if (!mounted || pending) return;
    setState(startLoad);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      // A changed future retains the previous snapshot until it completes.
      // Never offer an old child's/filter's actions under the new context.
      if (snapshot.connectionState != ConnectionState.done) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Center(
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Wird geladen …'),
                ],
              ),
            ),
          ),
        );
      }
      if (snapshot.hasError) {
        return Panel(
          child: Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Das Laden hat nicht geklappt',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.error is ApiError
                      ? (snapshot.error as ApiError).message
                      : 'Bitte versuche es noch einmal. Deine gespeicherten Daten bleiben erhalten.',
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Erneut laden'),
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Notice('Hier sind gerade keine Daten verfügbar.'),
              OutlinedButton.icon(
                onPressed: refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Erneut laden'),
              ),
            ],
          ),
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

  Future<String?> _moreMenu(
    BuildContext context,
    List<(IconData, String, String)> entries,
    String path,
  ) async {
    final account = state.user;
    final family = state.familyId;
    if (account == null) return null;
    ModalRoute<dynamic>? ownRoute;
    void closeOldMenu() {
      if (identical(state.user, account) && state.familyId == family) return;
      final route = ownRoute;
      scheduleMicrotask(() {
        if ((!identical(state.user, account) || state.familyId != family) &&
            route?.isActive == true) {
          route!.navigator?.removeRoute(route);
        }
      });
    }

    state.addListener(closeOldMenu);
    try {
      final selected = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          ownRoute ??= ModalRoute.of(ctx);
          closeOldMenu();
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Semantics(
                      header: true,
                      child: const Text('Weitere Bereiche'),
                    ),
                  ),
                  for (final entry in entries.skip(3))
                    ListTile(
                      leading: Icon(entry.$1),
                      title: Text(entry.$2),
                      selected: path == entry.$3,
                      onTap: () {
                        if (ctx.mounted &&
                            identical(state.user, account) &&
                            state.familyId == family &&
                            ownRoute?.isCurrent == true) {
                          Navigator.pop(ctx, entry.$3);
                        }
                      },
                    ),
                ],
              ),
            ),
          );
        },
      );
      return identical(state.user, account) && state.familyId == family
          ? selected
          : null;
    } finally {
      state.removeListener(closeOldMenu);
    }
  }

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
        Icons.edit_note_rounded,
        'Hausaufgaben',
        '/homework/${state.user!['child_id']}',
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
      (Icons.storefront_outlined, 'Verkauf', '/admin/verkauf'),
      (Icons.notifications_outlined, 'Push', '/admin/push'),
    ],
    if (browser && state.isOwner && !state.isDemo)
      (Icons.receipt_long_outlined, 'Tarif', '/bestellungen'),
    (Icons.person_outline_rounded, 'Konto', '/settings'),
  ];

  int _selected(List<(IconData, String, String)> entries, String path) {
    final index = entries.indexWhere((entry) => path == entry.$3);
    if (index >= 0) return index;
    if (state.isChild && path.startsWith('/homework/')) {
      return entries.indexWhere((entry) => entry.$2 == 'Hausaufgaben');
    }
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
    if (state.isChild &&
        (path.startsWith('/material/') || path.startsWith('/library/'))) {
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
    final compactChild = !desktop && state.isChild;
    final mobileEntries = compactChild ? entries.take(3).toList() : entries;
    final maxWidth = state.isChild
        ? 1060.0
        : state.isAdmin
        ? 1440.0
        : 1360.0;
    final name = (state.user?['display_name'] as String?)?.trim();
    final displayName = name == null || name.isEmpty ? 'Konto' : name;
    final owner = state.user;
    final family = state.familyId;

    Future<void> selectDestination(int i) async {
      if (owner == null ||
          !identical(state.user, owner) ||
          state.familyId != family ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      if (compactChild && i == 3) {
        final route = await _moreMenu(context, entries, path);
        if (route != null &&
            context.mounted &&
            identical(state.user, owner) &&
            state.familyId == family) {
          _workspaceLink(context, state, route)();
        }
      } else {
        if (i >= 0 && i < mobileEntries.length) {
          _workspaceLink(context, state, mobileEntries[i].$3)();
        }
      }
    }

    return Scaffold(
      appBar: desktop
          ? null
          : AppBar(
              title: brand(),
              toolbarHeight: 68,
              actions: [
                SchulbuddyButton(),
                AppearanceToggle(state),
                NotificationBell(state),
                AccountMenu(state, compact: true),
                SizedBox(width: 8),
              ],
            ),
      bottomNavigationBar: desktop
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                color: context.palette.panelSurface,
                border: Border(
                  top: BorderSide(color: context.palette.surfaceBorder),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0F14243D),
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: NavigationBar(
                selectedIndex: compactChild && selected >= 3 ? 3 : selected,
                onDestinationSelected: selectDestination,
                destinations: [
                  for (var i = 0; i < mobileEntries.length; i++)
                    if (mobileEntries[i].$2 == 'Hausaufgaben')
                      Semantics(
                        label: 'Hausaufgaben',
                        excludeSemantics: true,
                        onTap: () => selectDestination(i),
                        child: NavigationDestination(
                          icon: Icon(mobileEntries[i].$1),
                          label: 'Haus\naufgaben',
                          tooltip: 'Hausaufgaben',
                        ),
                      )
                    else
                      NavigationDestination(
                        icon: Icon(mobileEntries[i].$1),
                        label: mobileEntries[i].$2,
                      ),
                  if (compactChild)
                    NavigationDestination(
                      icon: Icon(Icons.more_horiz_rounded),
                      label: 'Mehr',
                      tooltip: 'Weitere Bereiche',
                    ),
                ],
              ),
            ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sidebar)
            _WorkspaceSidebar(
              state: state,
              entries: entries,
              selected: selected,
              roleLabel: _roleLabel,
            ),
          if (rail)
            _WorkspaceRail(state: state, entries: entries, selected: selected),
          Expanded(
            child: Column(
              children: [
                if (desktop)
                  _WorkspaceHeader(
                    state: state,
                    roleLabel: _roleLabel,
                    section: state.isAdmin && path == '/admin/verkauf'
                        ? 'Verkauf'
                        : state.isAdmin && path == '/admin/push'
                        ? 'Push'
                        : path.startsWith('/messages/')
                        ? 'Nachrichten & Wünsche'
                        : path == '/notifications'
                        ? 'Neuigkeiten'
                        : entries[selected].$2,
                    displayName: displayName,
                    compact: rail,
                    notificationBell: NotificationBell(state),
                  ),
                Expanded(
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      key: ValueKey('workspace-scroll'),
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
                            key: ValueKey('workspace-content'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (state.isDemo)
                                Padding(
                                  padding: EdgeInsets.only(bottom: 20),
                                  child: Tag('Demo · nur Beispieldaten'),
                                ),
                              if (!state.isDemo &&
                                  !state.isAdmin &&
                                  state.user?['real_data_enabled'] == false)
                                Notice(
                                  'Testbetrieb · Bitte noch keine echten Kinderdaten eingeben.',
                                ),
                              if (showTitle || actions.isNotEmpty) ...[
                                _WorkspaceHeading(
                                  title: showTitle ? title : null,
                                  subtitle: showTitle ? subtitle : null,
                                  actions: actions,
                                ),
                                SizedBox(height: 26),
                              ],
                              child,
                              if (browser && path == '/app') ...[
                                SizedBox(height: 28),
                                AndroidDownload(state.api),
                              ],
                              if (!state.isChild || path == '/settings') ...[
                                SizedBox(height: 24),
                                Wrap(
                                  spacing: 12,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          openRoute(context, '/privacy'),
                                      child: Text('Datenschutz'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          openRoute(context, '/about'),
                                      child: Text('Über SCHULPILOT'),
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
  final AppState state;
  final List<(IconData, String, String)> entries;
  final int selected;
  final String roleLabel;

  const _WorkspaceSidebar({
    required this.state,
    required this.entries,
    required this.selected,
    required this.roleLabel,
  });

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('workspace-sidebar'),
    width: 248,
    margin: EdgeInsets.fromLTRB(12, 12, 0, 12),
    decoration: BoxDecoration(
      color: context.palette.panelSurface,
      border: Border.all(color: context.palette.surfaceBorder),
      borderRadius: BorderRadius.circular(26),
    ),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
            child: TextButton(
              key: const ValueKey('workspace-brand-home'),
              onPressed: _workspaceLink(
                context,
                state,
                state.isAdmin ? '/admin' : '/app',
              ),
              child: brand(),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(28, 0, 20, 16),
            child: Text(
              roleLabel,
              style: TextStyle(
                color: context.palette.muted,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: .4,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (var i = 0; i < entries.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: _NavigationSurface(
                      selected: i == selected,
                      child: ListTile(
                        selected: i == selected,
                        focusColor: Colors.transparent,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: Icon(
                          entries[i].$1,
                          color: i == selected
                              ? context.palette.teal
                              : context.palette.muted,
                          size: 22,
                        ),
                        title: Text(
                          entries[i].$2,
                          style: TextStyle(
                            color: i == selected
                                ? context.palette.ink
                                : context.palette.muted,
                            fontSize: 14,
                            fontWeight: i == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        onTap: _workspaceLink(context, state, entries[i].$3),
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
          ? context.palette.cyanSurface
          : widget.selected
          ? context.palette.mint
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: focused || widget.selected
              ? context.palette.teal
              : Colors.transparent,
          width: focused ? 2.5 : 1,
        ),
      ),
      child: widget.child,
    ),
  );
}

class _WorkspaceRail extends StatelessWidget {
  final AppState state;
  final List<(IconData, String, String)> entries;
  final int selected;
  const _WorkspaceRail({
    required this.state,
    required this.entries,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('workspace-rail'),
    width: 104,
    color: context.palette.panelSurface,
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: IconButton(
              key: const ValueKey('workspace-brand-home'),
              tooltip: 'Zur Übersicht',
              onPressed: _workspaceLink(
                context,
                state,
                state.isAdmin ? '/admin' : '/app',
              ),
              icon: Container(
                padding: EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: context.palette.cyanSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Image.asset(
                  'assets/brand/schulpilot-mark.png',
                  width: 34,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
          Expanded(
            child: NavigationRail(
              scrollable: true,
              minWidth: 104,
              backgroundColor: context.palette.panelSurface,
              indicatorColor: context.palette.mint,
              selectedIconTheme: IconThemeData(color: context.palette.teal),
              unselectedIconTheme: IconThemeData(color: context.palette.muted),
              selectedLabelTextStyle: TextStyle(
                color: context.palette.ink,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              unselectedLabelTextStyle: TextStyle(
                color: context.palette.muted,
                fontSize: 12,
              ),
              labelType: NavigationRailLabelType.all,
              selectedIndex: selected,
              onDestinationSelected: _workspaceSelection(
                context,
                state,
                entries,
              ),
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
  final AppState state;
  final String roleLabel;
  final String section;
  final String displayName;
  final bool compact;
  final Widget notificationBell;
  const _WorkspaceHeader({
    required this.state,
    required this.roleLabel,
    required this.section,
    required this.displayName,
    required this.compact,
    required this.notificationBell,
  });

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('workspace-header'),
    height: 88,
    padding: EdgeInsets.symmetric(horizontal: compact ? 28 : 36),
    decoration: BoxDecoration(
      color: context.palette.panelSurface,
      border: Border(bottom: BorderSide(color: context.palette.surfaceBorder)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: TextButton(
                  key: const ValueKey('workspace-home-breadcrumb'),
                  onPressed: _workspaceLink(
                    context,
                    state,
                    state.isAdmin ? '/admin' : '/app',
                  ),
                  child: Text(
                    roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: context.palette.muted,
                  size: 18,
                ),
              ),
              Flexible(
                child: Text(
                  section,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 16),
        SchulbuddyButton(),
        AppearanceToggle(state),
        SizedBox(width: 8),
        notificationBell,
        SizedBox(width: 8),
        AccountMenu(state, nameWidth: compact ? 140 : 200),
      ],
    ),
  );
}

bool _sameHeaderAccount(AppState state, Json? snapshot) =>
    snapshot != null && identical(state.user, snapshot);

String notificationActionLabel(Json item) {
  final path = Uri.tryParse('${item['route'] ?? ''}')?.path ?? '';
  if (path.startsWith('/messages/')) return 'Nachricht ansehen';
  if (path.startsWith('/homework/') || path.startsWith('/parent-homework/')) {
    return 'Hausaufgabe ansehen';
  }
  if (path.startsWith('/unit/')) return 'Lernrunde ansehen';
  if (path.startsWith('/material/')) return 'Heftseite ansehen';
  if (path.startsWith('/after-school/')) return 'Schultag ansehen';
  if (path.startsWith('/family-call/')) return 'Live-Hilfe öffnen';
  if (path.startsWith('/parent-plan/')) return 'Lernplan ansehen';
  if (path.startsWith('/progress/')) return 'Lernstand ansehen';
  return 'Neuigkeit öffnen';
}

MenuStyle _headerMenuStyle(BuildContext context, {double width = 352}) =>
    MenuStyle(
      backgroundColor: WidgetStatePropertyAll(context.palette.panelSurface),
      side: WidgetStatePropertyAll(
        BorderSide(color: context.palette.surfaceBorder),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      maximumSize: WidgetStatePropertyAll(
        Size(
          (MediaQuery.sizeOf(context).width - 24).clamp(0, width),
          (MediaQuery.sizeOf(context).height - 100).clamp(120, 640),
        ),
      ),
    );

class AccountMenu extends StatefulWidget {
  final AppState state;
  final bool compact;
  final double nameWidth;
  const AccountMenu(
    this.state, {
    super.key,
    this.compact = false,
    this.nameWidth = 200,
  });
  @override
  State<AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends State<AccountMenu> {
  final _menu = MenuController();
  Json? _snapshot;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.state.user;
    widget.state.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant AccountMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_changed);
      widget.state.addListener(_changed);
      _changed();
    }
  }

  void _changed() {
    if (!_sameHeaderAccount(widget.state, _snapshot)) _menu.close();
    if (mounted) {
      setState(() {
        _snapshot = widget.state.user;
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    super.dispose();
  }

  Future<void> _logout(Json? snapshot) async {
    final account = snapshot?['id'] as String?;
    if (_signingOut ||
        account == null ||
        !_sameHeaderAccount(widget.state, snapshot)) {
      return;
    }
    setState(() => _signingOut = true);
    try {
      await widget.state.logout(expectedAccountId: account);
      if (mounted && widget.state.user == null) context.go('/login');
    } catch (error) {
      if (mounted && _sameHeaderAccount(widget.state, snapshot)) {
        showError(context, error);
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final snapshot = state.user;
    final rawName = (state.user?['display_name'] as String?)?.trim();
    final name = rawName == null || rawName.isEmpty ? 'Konto' : rawName;
    final avatar = CircleAvatar(
      radius: 17,
      backgroundColor: context.palette.mint,
      foregroundColor: context.palette.teal,
      child: Text(name.characters.first.toUpperCase()),
    );
    return MenuAnchor(
      controller: _menu,
      crossAxisUnconstrained: false,
      style: _headerMenuStyle(context, width: 288),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Text(name, style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        MenuItemButton(
          key: ValueKey('account-settings'),
          leadingIcon: Icon(Icons.settings_outlined),
          onPressed: _signingOut
              ? null
              : () {
                  if (_sameHeaderAccount(state, snapshot)) {
                    context.go('/settings');
                  }
                },
          child: Text('Einstellungen'),
        ),
        MenuItemButton(
          key: ValueKey('account-logout'),
          leadingIcon: Icon(Icons.logout_rounded),
          onPressed: _signingOut ? null : () => _logout(snapshot),
          child: Text(_signingOut ? 'Wird abgemeldet …' : 'Abmelden'),
        ),
      ],
      builder: (context, menu, _) {
        void toggle() => menu.isOpen ? menu.close() : menu.open();
        return widget.compact
            ? Semantics(
                label: 'Konto öffnen',
                child: IconButton(
                  key: ValueKey('account-menu'),
                  tooltip: 'Konto öffnen',
                  onPressed: _signingOut ? null : toggle,
                  icon: ExcludeSemantics(child: avatar),
                ),
              )
            : Tooltip(
                message: 'Konto öffnen',
                child: TextButton(
                  key: ValueKey('account-menu'),
                  onPressed: _signingOut ? null : toggle,
                  style: TextButton.styleFrom(
                    foregroundColor: context.palette.ink,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      avatar,
                      SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: widget.nameWidth),
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.expand_more_rounded, size: 18),
                    ],
                  ),
                ),
              );
      },
    );
  }
}

class NotificationBell extends StatefulWidget {
  final AppState state;
  const NotificationBell(this.state, {super.key});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _menu = MenuController();
  Json? _snapshot;
  bool _opening = false;
  int _openRevision = 0;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.state.user;
    widget.state.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant NotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _menu.close();
      _opening = false;
      _openRevision++;
      oldWidget.state.removeListener(_changed);
      widget.state.addListener(_changed);
      _changed();
    }
  }

  void _changed() {
    if (!_sameHeaderAccount(widget.state, _snapshot)) {
      _menu.close();
      _opening = false;
      _openRevision++;
    }
    if (mounted) {
      setState(() {
        _snapshot = widget.state.user;
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    super.dispose();
  }

  Future<void> _openItem(Json item, Json? snapshot) async {
    final state = widget.state;
    final route = ModalRoute.of(context);
    if (_opening ||
        !_sameHeaderAccount(state, snapshot) ||
        route?.isCurrent == false) {
      return;
    }
    final revision = ++_openRevision;
    setState(() => _opening = true);
    try {
      if (item['read'] != true) {
        await state.inbox.markRead([item['id'] as String]);
      }
    } catch (_) {
      if (mounted &&
          revision == _openRevision &&
          identical(widget.state, state) &&
          _sameHeaderAccount(state, snapshot) &&
          route?.isCurrent != false) {
        toast(
          context,
          'Die Lesemarkierung konnte nicht gespeichert werden. Die Nachricht bleibt ungelesen.',
        );
      }
    }
    if (mounted &&
        identical(widget.state, state) &&
        revision == _openRevision &&
        _sameHeaderAccount(state, snapshot)) {
      setState(() => _opening = false);
      if (route?.isCurrent != false) context.go(item['route'] as String);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state.inbox,
    builder: (context, _) {
      final state = widget.state;
      final inbox = state.inbox;
      final account = state.user?['id'] as String?;
      final snapshot = state.user;
      final width = (MediaQuery.sizeOf(context).width - 56)
          .clamp(0, 320)
          .toDouble();
      return MenuAnchor(
        controller: _menu,
        crossAxisUnconstrained: false,
        style: _headerMenuStyle(context),
        onOpen: () {
          if (!state.isAdmin) {
            inbox.activate(account);
            inbox.refresh();
          }
        },
        menuChildren: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Text(
              state.isAdmin ? 'Push-Betrieb' : 'Deine Neuigkeiten',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (state.isAdmin)
            SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Geräte und Versandstatus prüfen.',
                  style: TextStyle(color: context.palette.muted),
                ),
              ),
            )
          else ...[
            if (inbox.loading)
              SizedBox(width: width, child: LinearProgressIndicator()),
            if (inbox.error != null)
              SizedBox(
                width: width,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    inbox.error!,
                    style: TextStyle(color: context.palette.dangerInk),
                  ),
                ),
              ),
            if (!inbox.loading && !inbox.hasLoaded && inbox.error == null)
              Padding(
                padding: EdgeInsets.all(16),
                child: Text('Neuigkeiten werden geladen …'),
              ),
            if (inbox.hasLoaded && inbox.items.isEmpty && inbox.error == null)
              SizedBox(
                width: width,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Hier erscheint Neues zu deinem Lernen und deiner Familie.',
                    style: TextStyle(color: context.palette.muted),
                  ),
                ),
              ),
            for (final item in inbox.items.take(4))
              MenuItemButton(
                key: ValueKey('notice-preview-${item['id']}'),
                leadingIcon: Icon(
                  item['read'] == true
                      ? Icons.notifications_none_rounded
                      : Icons.notifications_active_outlined,
                  color: item['read'] == true
                      ? context.palette.muted
                      : context.palette.teal,
                ),
                onPressed: _opening ? null : () => _openItem(item, snapshot),
                child: SizedBox(
                  width: (width - 64).clamp(0, 256).toDouble(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'] as String,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: item['read'] == true
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '${item['read'] == true ? 'Gelesen' : 'Ungelesen'} · ${state.isParent ? '${item['child_name']} · ' : ''}${DateFormat('dd.MM. · HH:mm').format(DateTime.fromMillisecondsSinceEpoch((item['created'] as num).toInt() * 1000))}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notificationActionLabel(item),
                          style: TextStyle(
                            color: context.palette.teal,
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (inbox.items.length > 4)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  '4 von ${inbox.items.length} geladenen Neuigkeiten. Die übrigen findest du unter „Alle anzeigen“.',
                  style: TextStyle(color: context.palette.muted, fontSize: 12),
                ),
              ),
          ],
          Divider(height: 12),
          MenuItemButton(
            key: ValueKey('notifications-all'),
            leadingIcon: Icon(Icons.list_alt_rounded),
            onPressed: () {
              if (_sameHeaderAccount(state, snapshot)) {
                context.go(state.isAdmin ? '/admin/push' : '/notifications');
              }
            },
            child: Text('Alle anzeigen'),
          ),
        ],
        builder: (context, menu, _) => IconButton.outlined(
          key: ValueKey('notification-bell'),
          tooltip: state.isAdmin ? 'Push-Status' : 'Benachrichtigungen',
          style:
              IconButton.styleFrom(
                backgroundColor: context.palette.surfaceLow,
                foregroundColor: context.palette.ink,
                side: BorderSide(color: context.palette.controlBorder),
              ).copyWith(
                side: WidgetStateProperty.resolveWith(
                  (states) => BorderSide(
                    color: states.contains(WidgetState.focused)
                        ? context.palette.teal
                        : context.palette.controlBorder,
                    width: states.contains(WidgetState.focused) ? 2.5 : 1,
                  ),
                ),
              ),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          icon: Semantics(
            label: state.isAdmin
                ? 'Push-Status'
                : state.inbox.unread > 0
                ? 'Benachrichtigungen, ${state.inbox.unread} ungelesen'
                : 'Benachrichtigungen',
            excludeSemantics: true,
            child: Badge(
              isLabelVisible: !state.isAdmin && state.inbox.unread > 0,
              label: ExcludeSemantics(
                child: Text(
                  '${state.inbox.unread > 99 ? '99+' : state.inbox.unread}',
                ),
              ),
              child: Icon(Icons.notifications_none_rounded),
            ),
          ),
        ),
      );
    },
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
              child: Text(
                subtitle!,
                style: TextStyle(color: context.palette.muted),
              ),
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

Widget heading(String title, {String? subtitle, Widget? trailing}) => Builder(
  builder: (context) => Padding(
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
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: context.palette.ink,
                  ),
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  ),
);

Widget stat(String value, String label, IconData icon, {Color color = mint}) =>
    Builder(
      builder: (context) => SizedBox(
        width: 200,
        child: Panel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.palette.surface(color),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: context.palette.teal, size: 22),
              ),
              const SizedBox(height: 15),
              Text(
                value,
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: context.palette.ink,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: context.palette.muted),
              ),
            ],
          ),
        ),
      ),
    );

String statusLabel(String? status) => switch (status) {
  'not_started' => 'Nicht begonnen',
  'active' => 'Begonnen',
  'paused' => 'Pausiert',
  'planned' => 'Geplant',
  'ready' => 'Bereit',
  'pending' || 'queued' || 'running' || 'processing' => 'Wird vorbereitet',
  'needs_review' => 'Text kurz prüfen',
  'blocked' => 'Vorbereitung pausiert',
  'failed' => 'Vorbereitung nicht gelungen',
  'due' => 'Zum Wiederholen',
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

String friendlyDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null || date.year < 2000) return 'noch offen';
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

class AssessmentTrail extends StatelessWidget {
  final List entries;
  const AssessmentTrail(this.entries, {super.key});
  @override
  Widget build(BuildContext context) => entries.isEmpty
      ? const SizedBox.shrink()
      : ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('Bewertung nachgeprüft'),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: [
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${outcomeLabel(entry['previous_outcome'])} → ${outcomeLabel(entry['outcome'])}',
                ),
              ),
            Text(
              'Deine ursprüngliche Antwort, die Lernzeit und die erfassten Hilfen bleiben erhalten.',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
          ],
        );
}

/// Own form fields until the closing route animation has actually disposed them.
class DialogControllerScope extends StatefulWidget {
  final List<TextEditingController> controllers;
  final Widget child;
  const DialogControllerScope({
    super.key,
    required this.controllers,
    required this.child,
  });
  @override
  State<DialogControllerScope> createState() => _DialogControllerScopeState();
}

class _DialogControllerScopeState extends State<DialogControllerScope> {
  @override
  Widget build(BuildContext context) => widget.child;
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String text, {
  String confirmLabel = 'Bestätigen',
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            autofocus: destructive,
            onPressed: () {
              if (ctx.mounted && ModalRoute.of(ctx)?.isCurrent == true) {
                Navigator.pop(ctx, false);
              }
            },
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: context.palette.dangerInk,
                    foregroundColor: context.palette.dangerSurface,
                  )
                : null,
            onPressed: () {
              if (ctx.mounted && ModalRoute.of(ctx)?.isCurrent == true) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

String counted(num count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';
String schoolDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null || date.year < 2000 || date.year > 2100) {
    return 'Termin noch offen';
  }
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

/// Display choice only. It performs no provider, learning or account request.
class AppearanceToggle extends StatelessWidget {
  final AppState state;
  const AppearanceToggle(this.state, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => IconButton.outlined(
      key: const ValueKey('appearance-toggle'),
      tooltip: state.darkAppearance ? 'Helles Design' : 'Dunkles Design',
      onPressed: () => state.setAppearance(!state.darkAppearance),
      icon: Icon(
        state.darkAppearance
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
      ),
    ),
  );
}
