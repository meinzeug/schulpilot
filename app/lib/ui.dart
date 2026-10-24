import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'page_tools.dart';
import 'profile_avatar.dart';
import 'app_palette.dart';
export 'app_palette.dart';
import 'download_panel.dart';
import 'legal_links.dart';
import 'schulbuddy.dart';
import 'schulpilot_icons.dart';

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
  final token = state.api.token;
  final route = ModalRoute.of(context);
  return () {
    if (!context.mounted ||
        owner == null ||
        !identical(state.user, owner) ||
        state.familyId != family ||
        state.api.token != token ||
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
    borderRadius: BorderRadius.circular(16),
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
            fontFamily: 'Nunito',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: ink,
            height: 1.12,
            letterSpacing: -.6,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: ink,
            letterSpacing: -.5,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 20,
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
          bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.45),
          bodyMedium: TextStyle(fontSize: 15, color: ink, height: 1.45),
          bodySmall: TextStyle(fontSize: 14, color: muted, height: 1.4),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.cream,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: ink,
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
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: controlBorder, width: 1.25),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: controlBorder, width: 1.25),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: teal, width: 2.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: dangerInk, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: dangerInk, width: 2.5),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: p.actionPurple,
            foregroundColor: Colors.white,
            disabledBackgroundColor: p.surfaceHigh,
            disabledForegroundColor: muted,
            textStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            minimumSize: Size(48, 48),
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      color: p.panelSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: surfaceBorder),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.panelSurface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.surfaceHigh,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? ink : muted,
          size: 23,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          color: states.contains(WidgetState.selected) ? ink : muted,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
      height: 76,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: ink,
      unselectedLabelColor: muted,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      unselectedLabelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      indicatorColor: ink,
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
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: controlBorder),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      subtitleTextStyle: TextStyle(color: muted, fontSize: 14, height: 1.4),
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

/// The same transparent head and home action in public and signed-in headers.
Widget brand({
  bool light = false,
  bool compact = false,
  VoidCallback? onPressed,
}) => Builder(
  builder: (context) {
    final route = ModalRoute.of(context);
    return TextButton(
      key: const ValueKey('workspace-brand-home'),
      onPressed:
          onPressed ??
          () {
            if (!context.mounted || route?.isCurrent == false) return;
            FocusManager.instance.primaryFocus?.unfocus();
            GoRouter.maybeOf(context)?.go('/app');
          },
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        foregroundColor: light ? Colors.white : context.palette.ink,
      ),
      child: Semantics(
        label: 'SCHULPILOT – zur Startseite',
        excludeSemantics: true,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/brand/schulpilot-mark.png',
                width: 44,
                height: 44,
                excludeFromSemantics: true,
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                Text(
                  'SCHULPILOT',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .4,
                    color: light ? Colors.white : context.palette.ink,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  },
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
    this.padding = const EdgeInsets.all(18),
  });
  @override
  Widget build(BuildContext context) => Card(
    semanticContainer: false,
    color: context.palette.surface(color ?? panelColor(tone)),
    elevation: tone == PanelTone.subtle ? 0 : null,
    shape: tone == PanelTone.neutral
        ? null
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: context.palette
                  .resolve(panelAccent(tone))
                  .withValues(alpha: .65),
            ),
          ),
    child: Padding(
      padding:
          MediaQuery.sizeOf(context).width < 720 &&
              padding == const EdgeInsets.all(18)
          ? const EdgeInsets.all(16)
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
    this.padding = const EdgeInsets.all(18),
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
        MediaQuery.sizeOf(context).width < 720 &&
            widget.padding == const EdgeInsets.all(18)
        ? const EdgeInsets.all(16)
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
            borderRadius: BorderRadius.circular(16),
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
                  const SizedBox(height: 12),
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
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 720 ? 16 : 18),
    decoration: BoxDecoration(
      color: context.palette.mint,
      borderRadius: BorderRadius.circular(16),
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
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontSize: MediaQuery.sizeOf(context).width < 720 ? 24 : 28,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: TextStyle(color: context.palette.muted, height: 1.5),
        ),
        const SizedBox(height: 16),
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
  final bool focusContent;
  final bool retainNavigation;
  const PageFrame({
    super.key,
    required this.state,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions = const [],
    this.showTitle = true,
    this.focusContent = false,
    this.retainNavigation = false,
  });

  @override
  Widget build(BuildContext context) => PageToolsHost(
    state: state,
    child: WorkspaceShell(
      state: state,
      title: title,
      subtitle: subtitle,
      actions: actions,
      showTitle: showTitle,
      focusContent: focusContent,
      retainNavigation: retainNavigation,
      browser: kIsWeb,
      child: child,
    ),
  );
}

/// Shared page content with navigation suited to its browser or native host.
class WorkspaceShell extends StatefulWidget {
  final AppState state;
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final bool showTitle;
  final bool focusContent;
  final bool retainNavigation;
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
    this.focusContent = false,
    this.retainNavigation = false,
  });

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell>
    with WidgetsBindingObserver {
  AppState get state => widget.state;
  String get title => widget.title;
  String? get subtitle => widget.subtitle;
  Widget get child => widget.child;
  List<Widget> get actions => widget.actions;
  bool get showTitle => widget.showTitle;
  bool get browser => widget.browser;
  final scroll = ScrollController();
  final contentFocus = FocusNode(debugLabel: 'Hauptinhalt');
  final skipFocus = FocusNode(debugLabel: 'Zum Hauptinhalt');
  final workspaceFocus = FocusNode(
    debugLabel: 'Workspace',
    skipTraversal: true,
  );
  bool farDown = false;
  ModalRoute<dynamic>? toolRoute;
  Json? boundOwner;
  String? boundFamily, boundToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bindOwner();
    state.addListener(ownerChanged);
    scroll.addListener(scrolled);
    skipFocus.addListener(skipFocused);
    HardwareKeyboard.instance.addHandler(unfocusedShortcut);
  }

  bool unfocusedShortcut(KeyEvent event) {
    if (event is! KeyDownEvent ||
        !ownerCurrent ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent == false ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return false;
    }
    final primary = FocusManager.instance.primaryFocus;
    // Descendant shortcuts use normal focus dispatch. This fallback only covers
    // a fresh Navigator scope, so late field/album autofocus remains untouched.
    if (primary == workspaceFocus ||
        (primary?.ancestors.contains(workspaceFocus) ?? false)) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyK &&
        (keyboard.isControlPressed || keyboard.isMetaPressed) &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      unawaited(openWorkspaceTool());
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.f1 &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      unawaited(openWorkspaceTool(help: true));
      return true;
    }
    return false;
  }

  void bindOwner() {
    boundOwner = state.user;
    boundFamily = state.familyId;
    boundToken = state.api.token;
  }

  bool get ownerCurrent =>
      boundOwner != null &&
      identical(boundOwner, state.user) &&
      boundFamily == state.familyId &&
      boundToken == state.api.token;
  void ownerChanged() {
    if (ownerCurrent) return;
    closeTool();
    bindOwner();
    if (mounted) setState(() {});
  }

  void closeTool() {
    final old = toolRoute;
    toolRoute = null;
    if (old?.isActive == true) {
      scheduleMicrotask(() {
        if (old?.isActive == true) old!.navigator?.removeRoute(old);
      });
    }
  }

  void scrolled() {
    final next = scroll.hasClients && scroll.offset > 500;
    if (mounted && next != farDown) setState(() => farDown = next);
  }

  void skipFocused() {
    if (mounted) setState(() {});
  }

  void goToTop({bool focus = false}) {
    if (!ownerCurrent || ModalRoute.of(context)?.isCurrent == false) return;
    if (scroll.hasClients) {
      if (MediaQuery.disableAnimationsOf(context)) {
        scroll.jumpTo(0);
      } else {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    }
    if (focus) contentFocus.requestFocus();
  }

  @override
  void didUpdateWidget(covariant WorkspaceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, state)) {
      oldWidget.state.removeListener(ownerChanged);
      closeTool();
      bindOwner();
      state.addListener(ownerChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value != AppLifecycleState.resumed) closeTool();
  }

  @override
  void dispose() {
    state.removeListener(ownerChanged);
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(unfocusedShortcut);
    closeTool();
    scroll.dispose();
    contentFocus.dispose();
    skipFocus.dispose();
    workspaceFocus.dispose();
    super.dispose();
  }

  Future<void> openWorkspaceTool({bool help = false}) async {
    final hostRoute = ModalRoute.of(context);
    if (!ownerCurrent || hostRoute?.isCurrent == false || toolRoute != null) {
      return;
    }
    final account = boundOwner, family = boundFamily, token = boundToken;
    final path = GoRouterState.of(context).uri.path;
    final entries = _entries(sidebar: false);
    bool current() =>
        mounted &&
        identical(state.user, account) &&
        state.familyId == family &&
        state.api.token == token &&
        hostRoute?.isActive != false &&
        GoRouterState.of(context).uri.path == path;
    final query = TextEditingController();
    ModalRoute<dynamic>? own;
    try {
      final destination = await showDialog<String>(
        context: context,
        builder: (ctx) {
          own ??= ModalRoute.of(ctx);
          toolRoute = own;
          if (!current()) {
            closeTool();
            return const SizedBox.shrink();
          }
          return StatefulBuilder(
            builder: (ctx, refresh) {
              final needle = query.text.trim().toLowerCase();
              final shown = entries
                  .where((entry) => entry.$2.toLowerCase().contains(needle))
                  .toList();
              return AlertDialog(
                title: Text(help ? 'Tastatur & Bedienung' : 'Bereich wechseln'),
                content: SizedBox(
                  width: 440,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: help
                          ? [
                              const Text('Strg / ⌘ + K: Bereiche durchsuchen'),
                              const SizedBox(height: 12),
                              const Text('F1: Diese Bedienhilfe öffnen'),
                              const SizedBox(height: 12),
                              const Text(
                                'Tab / Umschalt + Tab: Zum nächsten / vorherigen Bedienelement',
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Am Seitenanfang erscheint bei Tastaturfokus „Zum Hauptinhalt“. Eingaben werden dabei nicht gesendet.',
                              ),
                              const SizedBox(height: 12),
                              const Text('Escape: Diesen Dialog schließen'),
                            ]
                          : [
                              TextField(
                                controller: query,
                                autofocus: true,
                                maxLength: 80,
                                decoration: const InputDecoration(
                                  labelText: 'Bereich suchen',
                                  counterText: '',
                                ),
                                onChanged: (_) {
                                  if (current()) refresh(() {});
                                },
                              ),
                              const SizedBox(height: 12),
                              if (shown.isEmpty)
                                const Text(
                                  'Kein Bereich passt zu deiner Suche.',
                                ),
                              for (final entry in shown)
                                ListTile(
                                  leading: LearningNavIcon(entry.$1),
                                  title: Text(entry.$2),
                                  selected: path == entry.$3,
                                  onTap: () {
                                    if (current() &&
                                        toolRoute?.isCurrent == true) {
                                      Navigator.pop(ctx, entry.$3);
                                    }
                                  },
                                ),
                            ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      if (ctx.mounted && current() && own?.isCurrent == true) {
                        Navigator.pop(ctx);
                      }
                    },
                    child: const Text('Schließen'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (mounted &&
          destination != null &&
          current() &&
          entries.any((entry) => entry.$3 == destination)) {
        _workspaceLink(context, state, destination)();
      }
    } finally {
      await own?.completed;
      if (identical(toolRoute, own)) toolRoute = null;
      query.dispose();
    }
  }

  Future<String?> _moreMenu(
    BuildContext context,
    List<(IconData, String, String)> entries,
    String path,
  ) async {
    final account = state.user;
    final family = state.familyId;
    final token = state.api.token;
    if (account == null) return null;
    ModalRoute<dynamic>? ownRoute;
    void closeOldMenu() {
      if (identical(state.user, account) &&
          state.familyId == family &&
          state.api.token == token) {
        return;
      }
      final route = ownRoute;
      scheduleMicrotask(() {
        if ((!identical(state.user, account) ||
                state.familyId != family ||
                state.api.token != token) &&
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
                      leading: LearningNavIcon(entry.$1),
                      title: Text(entry.$2),
                      selected: path == entry.$3,
                      onTap: () {
                        if (ctx.mounted &&
                            identical(state.user, account) &&
                            state.familyId == family &&
                            state.api.token == token &&
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
      return identical(state.user, account) &&
              state.familyId == family &&
              state.api.token == token
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
    final focusedMobile = widget.focusContent && !desktop;
    // A compact notebook still belongs to the app's normal navigation shell.
    final hideNavigation = focusedMobile && !widget.retainNavigation;
    final path = GoRouterState.of(context).uri.path;
    final entries = _entries(sidebar: sidebar);
    final selected = _selected(entries, path);
    final compactChild = !desktop && state.isChild;
    final mobileEntries = compactChild ? entries.take(3).toList() : entries;
    final maxWidth = state.isChild
        ? 1160.0
        : state.isAdmin
        ? 1440.0
        : 1360.0;
    final name = (state.user?['display_name'] as String?)?.trim();
    final displayName = name == null || name.isEmpty ? 'Konto' : name;
    final owner = state.user;
    final family = state.familyId;
    final token = state.api.token;

    Future<void> selectDestination(int i) async {
      if (owner == null ||
          !identical(state.user, owner) ||
          state.familyId != family ||
          state.api.token != token ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      if (compactChild && i == 3) {
        final route = await _moreMenu(context, entries, path);
        if (route != null &&
            context.mounted &&
            identical(state.user, owner) &&
            state.familyId == family &&
            state.api.token == token) {
          _workspaceLink(context, state, route)();
        }
      } else {
        if (i >= 0 && i < mobileEntries.length) {
          _workspaceLink(context, state, mobileEntries[i].$3)();
        }
      }
    }

    final returnEntry = state.isChild && path != entries[selected].$3
        ? entries[selected]
        : null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            openWorkspaceTool(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            openWorkspaceTool(),
        const SingleActivator(LogicalKeyboardKey.f1): () =>
            openWorkspaceTool(help: true),
      },
      child: Focus(
        focusNode: workspaceFocus,
        child: Stack(
          children: [
            Scaffold(
              appBar: desktop || hideNavigation
                  ? null
                  : AppBar(
                      automaticallyImplyLeading: !focusedMobile,
                      leading: returnEntry == null || focusedMobile
                          ? null
                          : IconButton(
                              tooltip: 'Zu ${returnEntry.$2}',
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              onPressed: _workspaceLink(
                                context,
                                state,
                                returnEntry.$3,
                              ),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                      title: brand(
                        compact: width < 360,
                        onPressed: _workspaceLink(
                          context,
                          state,
                          state.isAdmin ? '/admin' : '/app',
                        ),
                      ),
                      toolbarHeight: 56,
                      actions: [
                        SchulbuddyButton(),
                        NotificationBell(state),
                        AccountMenu(
                          state,
                          compact: true,
                          appearanceInMenu: true,
                          onChooseArea: () => openWorkspaceTool(),
                          onKeyboardHelp: () => openWorkspaceTool(help: true),
                        ),
                        SizedBox(width: 8),
                      ],
                    ),
              bottomNavigationBar: desktop || hideNavigation
                  ? null
                  : SafeArea(
                      top: false,
                      child: Container(
                        margin: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: context.palette.panelSurface,
                          border: Border.all(
                            color: context.palette.surfaceBorder,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: NavigationBar(
                          height:
                              MediaQuery.textScalerOf(context).scale(1) > 1.4
                              ? 96
                              : 72,
                          labelBehavior: NavigationDestinationLabelBehavior
                              .onlyShowSelected,
                          selectedIndex: compactChild && selected >= 3
                              ? 3
                              : selected,
                          onDestinationSelected: selectDestination,
                          destinations: [
                            for (var i = 0; i < mobileEntries.length; i++)
                              if (mobileEntries[i].$2 == 'Hausaufgaben')
                                Semantics(
                                  label: 'Hausaufgaben',
                                  excludeSemantics: true,
                                  onTap: () => selectDestination(i),
                                  child: NavigationDestination(
                                    icon: LearningNavIcon(mobileEntries[i].$1),
                                    label: 'Haus\naufgaben',
                                    tooltip: 'Hausaufgaben',
                                  ),
                                )
                              else
                                NavigationDestination(
                                  icon: LearningNavIcon(mobileEntries[i].$1),
                                  label: mobileEntries[i].$2,
                                ),
                            if (compactChild)
                              NavigationDestination(
                                icon: LearningNavIcon(Icons.more_horiz_rounded),
                                label: selected >= 3
                                    ? entries[selected].$2
                                    : 'Mehr',
                                tooltip: selected >= 3
                                    ? '${entries[selected].$2} · Weitere Bereiche'
                                    : 'Weitere Bereiche',
                              ),
                          ],
                        ),
                      ),
                    ),
              body: SafeArea(
                top: focusedMobile,
                bottom: focusedMobile,
                left: focusedMobile,
                right: focusedMobile,
                child: Row(
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
                      _WorkspaceRail(
                        state: state,
                        entries: entries,
                        selected: selected,
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          if (desktop &&
                              (!widget.focusContent || widget.retainNavigation))
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
                              onChooseArea: () => openWorkspaceTool(),
                              onKeyboardHelp: () =>
                                  openWorkspaceTool(help: true),
                            ),
                          Expanded(
                            child: Stack(
                              children: [
                                SelectionArea(
                                  child: SingleChildScrollView(
                                    key: ValueKey('workspace-scroll'),
                                    controller: scroll,
                                    padding: EdgeInsets.fromLTRB(
                                      desktop ? 20 : 16,
                                      desktop
                                          ? 16
                                          : focusedMobile
                                          ? 8
                                          : 12,
                                      desktop ? 20 : 16,
                                      // Keep final actions clear of the floating
                                      // return-to-top target from the first scroll.
                                      96,
                                    ),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: maxWidth,
                                        ),
                                        child: Focus(
                                          focusNode: contentFocus,
                                          skipTraversal: true,
                                          child: Column(
                                            key: ValueKey('workspace-content'),
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (returnEntry != null &&
                                                  desktop &&
                                                  !widget.focusContent)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 8,
                                                      ),
                                                  child: Wrap(
                                                    spacing: 6,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment
                                                            .center,
                                                    children: [
                                                      TextButton.icon(
                                                        key: const ValueKey(
                                                          'workspace-context-return',
                                                        ),
                                                        onPressed:
                                                            _workspaceLink(
                                                              context,
                                                              state,
                                                              returnEntry.$3,
                                                            ),
                                                        icon: const Icon(
                                                          Icons
                                                              .arrow_back_rounded,
                                                          size: 18,
                                                        ),
                                                        label: Text(
                                                          'Zu ${returnEntry.$2}',
                                                        ),
                                                      ),
                                                      const Icon(
                                                        Icons
                                                            .chevron_right_rounded,
                                                        size: 18,
                                                      ),
                                                      Text(
                                                        title,
                                                        style: TextStyle(
                                                          color: context
                                                              .palette
                                                              .muted,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (state.isDemo)
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                    bottom: 12,
                                                  ),
                                                  child: Tag(
                                                    'Demo · nur Beispieldaten',
                                                  ),
                                                ),
                                              if (!state.isDemo &&
                                                  !state.isAdmin &&
                                                  state.user?['real_data_enabled'] ==
                                                      false)
                                                Notice(
                                                  'Testbetrieb · Bitte noch keine echten Kinderdaten eingeben.',
                                                ),
                                              if (showTitle ||
                                                  actions.isNotEmpty) ...[
                                                _WorkspaceHeading(
                                                  title: showTitle
                                                      ? title
                                                      : null,
                                                  subtitle: showTitle
                                                      ? subtitle
                                                      : null,
                                                  actions: actions,
                                                ),
                                                SizedBox(height: 16),
                                              ],
                                              child,
                                              if (browser &&
                                                  state.user != null &&
                                                  !state.isChild &&
                                                  path == '/app') ...[
                                                SizedBox(height: 28),
                                                AndroidDownload(state.api),
                                              ],
                                              if (!state.isChild ||
                                                  path == '/settings') ...[
                                                SizedBox(height: 24),
                                                Wrap(
                                                  spacing: 12,
                                                  children: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          openRoute(
                                                            context,
                                                            '/privacy',
                                                          ),
                                                      child: Text(
                                                        'Datenschutz',
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: () =>
                                                          openRoute(
                                                            context,
                                                            '/about',
                                                          ),
                                                      child: Text(
                                                        'Über SCHULPILOT',
                                                      ),
                                                    ),
                                                    PublicLegalLinks(
                                                      state.api.base,
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
                                if (farDown)
                                  Positioned(
                                    right: 12,
                                    bottom: 12,
                                    child: FloatingActionButton.small(
                                      heroTag: null,
                                      tooltip: 'Zum Seitenanfang',
                                      onPressed: () => goToTop(),
                                      child: const Icon(
                                        Icons.vertical_align_top_rounded,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              left: 12,
              right: 12,
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: ExcludeSemantics(
                    excluding: !skipFocus.hasFocus,
                    child: IgnorePointer(
                      ignoring: !skipFocus.hasFocus,
                      child: Opacity(
                        opacity: skipFocus.hasFocus ? 1 : 0,
                        child: FilledButton(
                          focusNode: skipFocus,
                          key: const ValueKey('workspace-skip'),
                          onPressed: () => goToTop(focus: true),
                          child: const Text('Zum Hauptinhalt'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
  Widget build(BuildContext context) => _WorkspaceIconRail(
    key: const ValueKey('workspace-sidebar'),
    expanded: false,
    state: state,
    entries: entries,
    selected: selected,
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
  Widget build(BuildContext context) => _WorkspaceIconRail(
    key: const ValueKey('workspace-rail'),
    state: state,
    entries: entries,
    selected: selected,
  );
}

/// A compact global navigation that leaves room for the actual learning content.
class _WorkspaceIconRail extends StatelessWidget {
  final bool expanded;
  final AppState state;
  final List<(IconData, String, String)> entries;
  final int selected;

  const _WorkspaceIconRail({
    super.key,
    this.expanded = false,
    required this.state,
    required this.entries,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accountIndex = entries.indexWhere((entry) => entry.$3 == '/settings');
    final selectDestination = _workspaceSelection(context, state, entries);
    final navigationIndexes = [
      for (var i = 0; i < entries.length; i++)
        if (i != accountIndex) i,
    ];

    Widget destination(int index) => _WorkspaceNavButton(
      expanded: expanded,
      icon: entries[index].$1,
      label: entries[index].$2,
      selected: index == selected,
      onPressed: () => selectDestination(index),
    );

    return Container(
      width: expanded ? 224 : 80,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: palette.panelSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.surfaceBorder.withValues(alpha: .5)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: IconButton(
                key: const ValueKey('workspace-brand-home'),
                tooltip: 'Zur Übersicht',
                style: IconButton.styleFrom(
                  fixedSize: Size(expanded ? 208 : 48, 48),
                  padding: const EdgeInsets.all(8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _workspaceLink(
                  context,
                  state,
                  state.isAdmin ? '/admin' : '/app',
                ),
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/brand/schulpilot-mark.png',
                      width: 32,
                      height: 32,
                      excludeFromSemantics: true,
                    ),
                    if (expanded) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'SCHULPILOT',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.ink,
                            fontFamily: 'Nunito',
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: NavigationRail(
                scrollable: true,
                extended: expanded,
                minExtendedWidth: 208,
                minWidth: 64,
                selectedLabelTextStyle: TextStyle(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                ),
                unselectedLabelTextStyle: TextStyle(
                  color: palette.muted,
                  fontWeight: FontWeight.w600,
                ),
                groupAlignment: -1,
                backgroundColor: Colors.transparent,
                useIndicator: false,
                indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                labelType: NavigationRailLabelType.none,
                selectedIndex: navigationIndexes.contains(selected)
                    ? navigationIndexes.indexOf(selected)
                    : null,
                onDestinationSelected: (index) =>
                    selectDestination(navigationIndexes[index]),
                destinations: [
                  for (final index in navigationIndexes)
                    NavigationRailDestination(
                      icon: Tooltip(
                        message: entries[index].$2,
                        excludeFromSemantics: true,
                        preferBelow: false,
                        child: _WorkspaceRailIcon(
                          icon: entries[index].$1,
                          selected: index == selected,
                        ),
                      ),
                      label: Text(entries[index].$2),
                    ),
                ],
              ),
            ),
            if (accountIndex >= 0) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Divider(height: 1, color: palette.surfaceBorder),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 14, top: 2),
                child: destination(accountIndex),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceRailIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;

  const _WorkspaceRailIcon({required this.icon, required this.selected});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final focused = Focus.maybeOf(context)?.hasFocus ?? false;
    return SizedBox(
      width: 64,
      height: 48,
      child: Stack(
        children: [
          if (selected)
            Positioned(
              left: 0,
              top: 15,
              bottom: 15,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: palette.teal,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          Center(
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected
                    ? palette.surfaceHigh
                    : focused
                    ? palette.surfaceLow
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(13),
                border: focused
                    ? Border.all(color: palette.teal, width: 2.5)
                    : null,
              ),
              child: LearningNavIcon(
                icon,
                size: 24,
                color: selected ? palette.ink : palette.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceNavButton extends StatefulWidget {
  final bool expanded;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _WorkspaceNavButton({
    this.expanded = false,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  State<_WorkspaceNavButton> createState() => _WorkspaceNavButtonState();
}

class _WorkspaceNavButtonState extends State<_WorkspaceNavButton> {
  bool focused = false;
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: widget.label,
      excludeFromSemantics: true,
      preferBelow: false,
      child: Semantics(
        label: widget.label,
        button: true,
        selected: widget.selected,
        onTap: widget.onPressed,
        child: SizedBox(
          width: widget.expanded ? 208 : 64,
          height: 48,
          child: Stack(
            children: [
              if (widget.selected)
                Positioned(
                  left: 0,
                  top: 15,
                  bottom: 15,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: palette.teal,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              Center(
                child: Material(
                  color: widget.selected
                      ? palette.surfaceHigh
                      : hovered
                      ? palette.surfaceLow
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: focused
                        ? BorderSide(color: palette.teal, width: 2.5)
                        : BorderSide.none,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    excludeFromSemantics: true,
                    onTap: widget.onPressed,
                    onFocusChange: (value) {
                      if (mounted && focused != value) {
                        setState(() => focused = value);
                      }
                    },
                    onHover: (value) {
                      if (mounted && hovered != value) {
                        setState(() => hovered = value);
                      }
                    },
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    child: SizedBox(
                      width: widget.expanded ? 208 : 48,
                      height: 48,
                      child: widget.expanded
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  LearningNavIcon(
                                    widget.icon,
                                    size: 24,
                                    color: widget.selected
                                        ? palette.ink
                                        : palette.muted,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ExcludeSemantics(
                                      child: Text(
                                        widget.label,
                                        style: TextStyle(
                                          color: widget.selected
                                              ? palette.ink
                                              : palette.muted,
                                          fontWeight: widget.selected
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : LearningNavIcon(
                              widget.icon,
                              size: 24,
                              color: widget.selected
                                  ? palette.ink
                                  : palette.muted,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  final AppState state;
  final String roleLabel;
  final String section;
  final String displayName;
  final bool compact;
  final Widget notificationBell;
  final VoidCallback onChooseArea, onKeyboardHelp;

  const _WorkspaceHeader({
    required this.state,
    required this.roleLabel,
    required this.section,
    required this.displayName,
    required this.compact,
    required this.notificationBell,
    required this.onChooseArea,
    required this.onKeyboardHelp,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = compact || MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Container(
      key: const ValueKey('workspace-header'),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Tooltip(
                    message: roleLabel,
                    child: TextButton(
                      key: const ValueKey('workspace-home-breadcrumb'),
                      onPressed: _workspaceLink(
                        context,
                        state,
                        state.isAdmin ? '/admin' : '/app',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: context.palette.ink,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: const Text(
                        'SCHULPILOT',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .4,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!narrow) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      section,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (narrow)
            IconButton(
              key: const ValueKey('workspace-area-switch'),
              tooltip: 'Bereiche',
              onPressed: onChooseArea,
              icon: const Icon(Icons.search_rounded, size: 22),
            )
          else
            TextButton.icon(
              key: const ValueKey('workspace-area-switch'),
              onPressed: onChooseArea,
              icon: const Icon(Icons.search_rounded, size: 20),
              label: const Text('Bereiche'),
            ),
          IconButton(
            tooltip: 'Tastatur & Bedienung',
            onPressed: onKeyboardHelp,
            icon: const Icon(Icons.keyboard_outlined, size: 22),
          ),
          SchulbuddyButton(),
          AppearanceToggle(state),
          notificationBell,
          AccountMenu(state, compact: narrow, nameWidth: 128),
        ],
      ),
    );
  }
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
  final bool appearanceInMenu;
  final double nameWidth;
  final VoidCallback? onChooseArea, onKeyboardHelp;
  const AccountMenu(
    this.state, {
    super.key,
    this.compact = false,
    this.appearanceInMenu = false,
    this.nameWidth = 200,
    this.onChooseArea,
    this.onKeyboardHelp,
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
    final avatar = ProfileAvatar(state, size: 36);
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
        if (widget.onChooseArea != null)
          MenuItemButton(
            key: const ValueKey('workspace-area-switch'),
            leadingIcon: const Icon(Icons.search_rounded),
            onPressed: _signingOut
                ? null
                : () {
                    if (_sameHeaderAccount(state, snapshot)) {
                      widget.onChooseArea!();
                    }
                  },
            child: const Text('Bereich wechseln'),
          ),
        if (widget.onKeyboardHelp != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.keyboard_outlined),
            onPressed: _signingOut
                ? null
                : () {
                    if (_sameHeaderAccount(state, snapshot)) {
                      widget.onKeyboardHelp!();
                    }
                  },
            child: const Text('Tastatur & Bedienung'),
          ),
        if (widget.appearanceInMenu)
          MenuItemButton(
            key: const ValueKey('account-appearance'),
            leadingIcon: Icon(
              state.darkAppearance
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            onPressed: _signingOut
                ? null
                : () {
                    if (mounted && _sameHeaderAccount(state, snapshot)) {
                      state.setAppearance(!state.darkAppearance);
                    }
                  },
            child: Text(
              state.darkAppearance ? 'Helles Design' : 'Dunkles Design',
            ),
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
        builder: (context, menu, _) => IconButton(
          key: ValueKey('notification-bell'),
          tooltip: state.isAdmin ? 'Push-Status' : 'Benachrichtigungen',
          style:
              IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: Colors.transparent,
                foregroundColor: context.palette.ink,
              ).copyWith(
                side: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? BorderSide(color: context.palette.teal, width: 2)
                      : BorderSide.none,
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
              child: Image.asset(
                'assets/brand/schulpilot-bell-header.png',
                width: 36,
                height: 36,
                excludeFromSemantics: true,
              ),
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
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontSize: MediaQuery.sizeOf(context).width < 720
                                ? 24
                                : 28,
                            height: 1.2,
                          ),
                    ),
                  ),
                ),
                const PageToolsButton(),
              ],
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
      if (constraints.maxWidth < 760 &&
          title != null &&
          actions.length == 1 &&
          actions.single is IconButton) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: actions.single,
            ),
          ],
        );
      }
      if (constraints.maxWidth >= 760 && title != null && actions.isNotEmpty) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
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
          if (title != null && actions.isNotEmpty) const SizedBox(height: 12),
          if (actions.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    },
  );
}

Widget heading(String title, {String? subtitle, Widget? trailing}) => Builder(
  builder: (context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 12),
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
                    fontSize: 18,
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
                      fontSize: 14,
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
