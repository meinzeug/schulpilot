import 'package:flutter/material.dart';

import 'ui.dart';

/// Explicit local view controls. Submitting performs a read only; typing never
/// silently changes which saved collection the results claim to represent.
class ParentCollectionSearch extends StatelessWidget {
  final TextEditingController controller;
  final String label, appliedQuery;
  final String helperText;
  final VoidCallback onSearch, onClear;
  final bool enabled;
  const ParentCollectionSearch({
    super.key,
    required this.controller,
    required this.label,
    required this.appliedQuery,
    required this.onSearch,
    required this.onClear,
    this.enabled = true,
    this.helperText =
        'Mit Suchen bestätigen. Sucht auch auf weiteren Listenseiten.',
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: controller,
        enabled: enabled,
        textInputAction: TextInputAction.search,
        maxLength: 160,
        onSubmitted: enabled ? (_) => onSearch() : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          helperMaxLines: 3,
          suffixIcon: IconButton(
            tooltip: 'Suche leeren',
            onPressed: enabled ? onClear : null,
            icon: const Icon(Icons.clear_rounded),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: enabled ? onSearch : null,
          icon: const Icon(Icons.search_rounded),
          label: const Text('Suchen'),
        ),
      ),
      if (appliedQuery.isNotEmpty)
        Text(
          'Angezeigte Suche: „$appliedQuery“',
          style: TextStyle(color: context.palette.muted),
        ),
    ],
  );
}

/// An open page header shared by parent workspaces in both visual variants.
/// The local emblem is decorative and never represents measured progress.
class ParentChoiceFilter extends StatelessWidget {
  final String label, value;
  final List<(String, String)> choices;
  final ValueChanged<String> onChanged;
  final bool enabled;
  const ParentChoiceFilter({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      key: ValueKey((label, value)),
      initialValue: value,
      isExpanded: true,
      itemHeight: null,
      decoration: InputDecoration(labelText: label),
      items: [
        if (!choices.any((item) => item.$1 == value))
          DropdownMenuItem(value: value, child: Text('Auswahl: $value')),
        for (final item in choices)
          DropdownMenuItem(value: item.$1, child: Text(item.$2)),
      ],
      onChanged: enabled
          ? (next) {
              if (next != null && next != value) onChanged(next);
            }
          : null,
    ),
  );
}

class ParentWorkspaceHero extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final IconData icon;
  final List<Widget> facts, actions;
  const ParentWorkspaceHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.icon = Icons.diversity_1_rounded,
    this.facts = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 720) {
      return _CompactParentHero(this);
    }
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth > 700 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, color: palette.electric, size: 19),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                eyebrow,
                                style: TextStyle(
                                  color: palette.cyanInk,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                color: palette.ink,
                                fontSize: wide ? 37 : 30,
                                height: 1.14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.8,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(width: 28),
                    ExcludeSemantics(
                      child: SizedBox(
                        width: 96,
                        height: 96,
                        child: CustomPaint(
                          painter: _WorkspaceEmblem(
                            primary: palette.teal,
                            accent: palette.electric,
                            line: palette.surfaceBorder,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(spacing: 24, runSpacing: 12, children: facts),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(spacing: 10, runSpacing: 10, children: actions),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Mobile keeps the actual page title and every supplied action visible.
class _CompactParentHero extends StatefulWidget {
  final ParentWorkspaceHero content;
  const _CompactParentHero(this.content);

  @override
  State<_CompactParentHero> createState() => _CompactParentHeroState();
}

class _CompactParentHeroState extends State<_CompactParentHero> {
  bool expanded = false;

  @override
  void didUpdateWidget(covariant _CompactParentHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.title != widget.content.title ||
        oldWidget.content.subtitle != widget.content.subtitle) {
      expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        key: const ValueKey('compact-parent-heading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    content.title,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: context.palette.ink,
                    ),
                  ),
                ),
              ),
              Semantics(
                expanded: expanded,
                child: IconButton(
                  tooltip: expanded
                      ? 'Bereichsinfo schließen'
                      : 'Über diesen Bereich',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: () => setState(() => expanded = !expanded),
                  icon: Icon(
                    expanded ? Icons.close_rounded : Icons.info_outline_rounded,
                  ),
                ),
              ),
            ],
          ),
          expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        content.eyebrow,
                        style: TextStyle(
                          color: context.palette.cyanInk,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        content.subtitle,
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      if (content.facts.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: content.facts,
                        ),
                      ],
                    ],
                  ),
                )
              : const SizedBox.shrink(),
          if (content.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: content.actions),
          ],
        ],
      ),
    );
  }
}

class ParentHeroFact extends StatelessWidget {
  final IconData icon;
  final String label;
  const ParentHeroFact({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: context.palette.teal, size: 18),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          label,
          style: TextStyle(
            color: context.palette.ink,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    ],
  );
}

class ParentSectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? action;
  const ParentSectionHeading({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(icon, color: context.palette.teal, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: context.palette.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (action != null)
          Align(alignment: Alignment.centerRight, child: action!),
      ],
    ),
  );
}

/// Long labels and actions remain separate and readable on small screens.
class ParentManagementRow extends StatelessWidget {
  final Widget title, subtitle;
  final Widget? leading, action;
  const ParentManagementRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.palette.surfaceBorder)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      color: context.palette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                    child: title,
                  ),
                  const SizedBox(height: 5),
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 13,
                    ),
                    child: subtitle,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (action != null) ...[
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: action!),
        ],
      ],
    ),
  );
}

class _WorkspaceEmblem extends CustomPainter {
  final Color primary, accent, line;
  const _WorkspaceEmblem({
    required this.primary,
    required this.accent,
    required this.line,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width * .42, stroke..color = line);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-23, -30, 46, 60),
        const Radius.circular(8),
      ),
      stroke..color = primary,
    );
    canvas.drawLine(const Offset(-11, -13), const Offset(12, -13), stroke);
    canvas.drawLine(const Offset(-11, 0), const Offset(7, 0), stroke);
    canvas.drawLine(const Offset(-11, 13), const Offset(12, 13), stroke);
    canvas.restore();
    canvas.drawCircle(
      Offset(size.width * .85, size.height * .28),
      6,
      Paint()..color = accent,
    );
    canvas.drawCircle(
      Offset(size.width * .2, size.height * .8),
      4,
      Paint()..color = primary,
    );
  }

  @override
  bool shouldRepaint(_WorkspaceEmblem oldDelegate) =>
      primary != oldDelegate.primary ||
      accent != oldDelegate.accent ||
      line != oldDelegate.line;
}

/// A date range is applied explicitly; unsubmitted edits never relabel results.
class ParentDateRange extends StatefulWidget {
  final String? start, end;
  final bool enabled;
  final void Function(String? start, String? end) onApply;
  const ParentDateRange({
    super.key,
    this.start,
    this.end,
    this.enabled = true,
    required this.onApply,
  });
  @override
  State<ParentDateRange> createState() => _ParentDateRangeState();
}

class _ParentDateRangeState extends State<ParentDateRange> {
  final form = GlobalKey<FormState>();
  late final TextEditingController start, end;
  String? parse(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    final parts = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(value);
    final iso = parts == null
        ? value
        : '${parts[3]}-${parts[2]!.padLeft(2, '0')}-${parts[1]!.padLeft(2, '0')}';
    final parsed = DateTime.tryParse(iso);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(iso) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != iso) {
      return null;
    }
    return iso;
  }

  String display(String? value) => value == null ? '' : friendlyDate(value);
  @override
  void initState() {
    super.initState();
    start = TextEditingController(text: display(widget.start));
    end = TextEditingController(text: display(widget.end));
  }

  @override
  void didUpdateWidget(covariant ParentDateRange old) {
    super.didUpdateWidget(old);
    if (old.start != widget.start) start.text = display(widget.start);
    if (old.end != widget.end) end.text = display(widget.end);
  }

  @override
  void dispose() {
    start.dispose();
    end.dispose();
    super.dispose();
  }

  void apply() {
    if (!widget.enabled || form.currentState?.validate() != true) return;
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onApply(parse(start.text), parse(end.text));
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in [(start, 'Zeitraum von'), (end, 'Zeitraum bis')])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              controller: entry.$1,
              enabled: widget.enabled,
              keyboardType: TextInputType.datetime,
              textInputAction: identical(entry.$1, start)
                  ? TextInputAction.next
                  : TextInputAction.done,
              decoration: InputDecoration(
                labelText: entry.$2,
                hintText: 'TT.MM.JJJJ · optional',
              ),
              onFieldSubmitted: identical(entry.$1, end)
                  ? (_) => apply()
                  : null,
              validator: (value) {
                if ((value ?? '').trim().isNotEmpty && parse(value!) == null) {
                  return 'Nutze ein gültiges Datum: TT.MM.JJJJ.';
                }
                final from = parse(start.text), to = parse(end.text);
                if (identical(entry.$1, end) &&
                    from != null &&
                    to != null &&
                    from.compareTo(to) > 0) {
                  return 'Das Ende muss am oder nach dem Beginn liegen.';
                }
                return null;
              },
            ),
          ),
        OutlinedButton.icon(
          onPressed: widget.enabled ? apply : null,
          icon: const Icon(Icons.date_range_outlined),
          label: const Text('Zeitraum anwenden'),
        ),
        if (widget.start != null || widget.end != null)
          Text(
            'Angezeigter Zeitraum: ${widget.start == null ? 'ohne Beginn' : friendlyDate(widget.start)} bis ${widget.end == null ? 'ohne Ende' : friendlyDate(widget.end)} (einschließlich)',
          ),
      ],
    ),
  );
}

/// The actual applied selection remains visible when detailed controls close.
class ParentAppliedFilters extends StatelessWidget {
  final List<(String label, VoidCallback remove)> filters;
  final bool enabled;
  const ParentAppliedFilters({
    super.key,
    required this.filters,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => filters.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Angewendete Filter',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in filters)
                    InputChip(
                      label: Text(item.$1),
                      onDeleted: enabled ? item.$2 : null,
                      deleteButtonTooltipMessage:
                          'Filter „${item.$1}“ entfernen',
                    ),
                ],
              ),
            ],
          ),
        );
}
