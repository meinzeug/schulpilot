import 'package:flutter/material.dart';

/// Semantic colours for two deliberately designed cyberpunk appearances.
/// Personal photos and scientific values are never recoloured.
@immutable
class AppPalette {
  final bool isDark;
  const AppPalette({required this.isDark});
  Color get ink => isDark ? const Color(0xFFEFF6FF) : const Color(0xFF17233C);
  Color get muted => isDark ? const Color(0xFFADBED5) : const Color(0xFF4C5F79);
  Color get teal => isDark ? const Color(0xFFB49AFF) : const Color(0xFF623BEA);
  Color get electric => const Color(0xFF5DE7F5);
  Color get cream => isDark ? const Color(0xFF080F1F) : const Color(0xFFF4F5FC);
  Color get panelSurface => isDark ? const Color(0xFF132139) : Colors.white;
  Color get surfaceLow =>
      isDark ? const Color(0xFF111F35) : const Color(0xFFEBEFF8);
  Color get surfaceHigh =>
      isDark ? const Color(0xFF1C304A) : const Color(0xFFDDE5F1);
  Color get surfaceBorder =>
      isDark ? const Color(0xFF334D70) : const Color(0xFFB8C6D9);
  Color get controlBorder =>
      isDark ? const Color(0xFF7895BB) : const Color(0xFF7788A2);
  Color get mint => isDark ? const Color(0xFF2A2448) : const Color(0xFFEEE9FF);
  Color get cyanInk =>
      isDark ? const Color(0xFF67E8F0) : const Color(0xFF006575);
  Color get cyanSurface =>
      isDark ? const Color(0xFF10313D) : const Color(0xFFDDF6F5);
  Color get successInk =>
      isDark ? const Color(0xFF8BE2B8) : const Color(0xFF16664C);
  Color get successSurface =>
      isDark ? const Color(0xFF15382D) : const Color(0xFFE5F5ED);
  Color get warningInk =>
      isDark ? const Color(0xFFFFD28E) : const Color(0xFF80500A);
  Color get warningSurface =>
      isDark ? const Color(0xFF3A2C19) : const Color(0xFFFFF1DA);
  Color get dangerInk =>
      isDark ? const Color(0xFFFFA7B6) : const Color(0xFFA82D40);
  Color get dangerSurface =>
      isDark ? const Color(0xFF3B2030) : const Color(0xFFFFF0F2);
  Color get actionPurple => const Color(0xFF7048D5);

  /// Map historical semantic constants used by existing controlled components.
  Color resolve(Color value) =>
      <Color, Color>{
        const Color(0xFF14243D): ink,
        const Color(0xFF5936CB): teal,
        const Color(0xFF37D9EA): electric,
        const Color(0xFFEEE9FF): mint,
        const Color(0xFFE8EEF6): cream,
        const Color(0xFF4C5F79): muted,
        const Color(0xFFF2F5FA): surfaceLow,
        const Color(0xFFB8C6D9): surfaceBorder,
        const Color(0xFF7788A2): controlBorder,
        const Color(0xFF006575): cyanInk,
        const Color(0xFFE2F5FA): cyanSurface,
        const Color(0xFF16664C): successInk,
        const Color(0xFFE5F5ED): successSurface,
        const Color(0xFF80500A): warningInk,
        const Color(0xFFFFF1DA): warningSurface,
        const Color(0xFFA82D40): dangerInk,
        const Color(0xFFFFF0F2): dangerSurface,
      }[value] ??
      value;
  Color surface(Color value) =>
      value == Colors.white ? panelSurface : resolve(value);
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      AppPalette(isDark: Theme.of(this).brightness == Brightness.dark);
}
