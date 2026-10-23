import 'package:flutter/material.dart';

import 'schulpilot_icons.dart';
import 'subject_badge.dart';
import 'ui.dart';

/// A visual grouping only: dates, ordering and actions stay with the caller.
class PlanSectionTitle extends StatelessWidget {
  final String title;
  const PlanSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 14),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final heading = Semantics(
          header: true,
          child: Text(
            title,
            style: TextStyle(
              color: context.palette.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
        final line = Divider(color: context.palette.surfaceBorder);
        if (constraints.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, const SizedBox(height: 4), line],
          );
        }
        return Row(
          children: [
            Flexible(child: heading),
            const SizedBox(width: 16),
            Expanded(child: line),
          ],
        );
      },
    ),
  );
}

enum PlanPillTone { neutral, info, success, warning }

class PlanPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final PlanPillTone tone;
  const PlanPill(
    this.label, {
    super.key,
    this.icon,
    this.tone = PlanPillTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (background, foreground) = switch (tone) {
      PlanPillTone.info => (p.mint, p.teal),
      PlanPillTone.success => (p.successSurface, p.successInk),
      PlanPillTone.warning => (p.warningSurface, p.warningInk),
      PlanPillTone.neutral => (p.surfaceLow, p.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            LearningNavIcon(icon!, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uses only the public local catalog for decoration. Unknown labels stay local.
class PlanSubjectMark extends StatelessWidget {
  final String? subject;
  final String? coverKey;
  const PlanSubjectMark({super.key, this.subject, this.coverKey});

  static const _publicNames = {
    'mathematik': 'mathematik',
    'mathe': 'mathematik',
    'deutsch': 'deutsch',
    'deutsch als zweitsprache': 'deutsch-als-zweitsprache',
    'englisch': 'englisch',
    'französisch': 'franzoesisch',
    'spanisch': 'spanisch',
    'latein': 'latein',
    'biologie': 'biologie',
    'sachunterricht': 'sachunterricht',
    'chemie': 'chemie',
    'physik': 'physik',
    'geschichte': 'geschichte',
    'geographie': 'geographie',
    'erdkunde': 'geographie',
    'informatik': 'informatik',
    'wirtschaft': 'wirtschaft',
    'gemeinschaftskunde': 'gemeinschaftskunde',
    'musik': 'musik',
    'kunst': 'kunst',
    'sport': 'sport',
    'technik': 'technik',
    'ethik': 'ethik',
    'religion': 'religion',
    'lern- und arbeitstechniken': 'lern-und-arbeitstechniken',
    'kreativität und bewegung': 'kreativitaet-und-bewegung',
  };

  @override
  Widget build(BuildContext context) => SubjectBadge(
    coverKey ?? _publicNames[subject?.trim().toLowerCase()],
    size: 36,
  );
}

class PlanDateMark extends StatelessWidget {
  final String? date;
  final IconData icon;
  const PlanDateMark({
    super.key,
    this.date,
    this.icon = Icons.calendar_today_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final day = DateTime.tryParse(date ?? '');
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.palette.surfaceHigh,
          borderRadius: BorderRadius.circular(11),
        ),
        child: day == null
            ? LearningNavIcon(icon, size: 21, color: context.palette.teal)
            : Text(
                '${day.day}',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: context.palette.ink,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

class PlanDayCard extends StatelessWidget {
  final String title;
  final Widget? summary;
  final List<Widget> children;
  const PlanDayCard({
    super.key,
    required this.title,
    this.summary,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlanSectionTitle(title),
        if (summary != null) ...[summary!, const SizedBox(height: 10)],
        ...children,
      ],
    ),
  );
}

/// A compact topic surface with a flexible height and a full-size touch target.
/// The caller retains every availability and account check in [onTap].
class PlanRow extends StatelessWidget {
  final Widget title;
  final Widget? subtitle, leading, trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry contentPadding;
  const PlanRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 13,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = Padding(
      padding: contentPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle.merge(
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                  child: title,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 7),
                  DefaultTextStyle.merge(
                    style: TextStyle(color: p.muted, fontSize: 13, height: 1.5),
                    child: subtitle!,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: IconTheme(
                data: IconThemeData(color: p.muted, size: 19),
                child: trailing!,
              ),
            ),
          ],
        ],
      ),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: onTap == null
          ? Material(
              color: p.panelSurface,
              shape: shape.copyWith(
                side: BorderSide(color: p.surfaceBorder.withValues(alpha: .55)),
              ),
              child: content,
            )
          : SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onTap,
                style: ButtonStyle(
                  alignment: Alignment.centerLeft,
                  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                  minimumSize: const WidgetStatePropertyAll(Size(48, 56)),
                  backgroundColor: WidgetStatePropertyAll(p.panelSurface),
                  shape: WidgetStatePropertyAll(shape),
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.focused)
                          ? p.teal
                          : p.surfaceBorder.withValues(alpha: .55),
                      width: states.contains(WidgetState.focused) ? 2.5 : 1,
                    ),
                  ),
                ),
                child: content,
              ),
            ),
    );
  }
}
