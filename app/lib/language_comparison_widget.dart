import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_graphic_frame.dart';
import 'ui.dart';

enum LanguageComparisonFocus { differences, commonWords, none }

/// Formal comparison of already disclosed, source-validated original examples.
/// No grammar judgment, generated example, request or learning evidence.
class LanguageComparisonWidget extends StatefulWidget {
  final Json block;
  final AppState? state;
  final Widget? action;

  const LanguageComparisonWidget(
    this.block, {
    super.key,
    this.state,
    this.action,
  });

  @override
  State<LanguageComparisonWidget> createState() =>
      _LanguageComparisonWidgetState();
}

class _LanguageComparisonWidgetState extends State<LanguageComparisonWidget>
    with WidgetsBindingObserver {
  static final words = RegExp(
    r"[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*",
    unicode: true,
  );
  AppState? ownerState;
  Json? owner;
  String? ownerId, family, token;
  String snapshot = '';
  ModalRoute<dynamic>? route;
  bool invalidated = false, foreground = true;
  int generation = 0;
  LanguageComparisonFocus focus = LanguageComparisonFocus.differences;

  String fingerprint() {
    try {
      return jsonEncode(widget.block);
    } catch (_) {
      return '';
    }
  }

  bool get ownerCurrent =>
      mounted &&
      !invalidated &&
      ownerState != null &&
      identical(widget.state, ownerState) &&
      ownerId?.isNotEmpty == true &&
      identical(ownerState!.user, owner) &&
      ownerState!.user?['id']?.toString() == ownerId &&
      ownerState!.familyId == family &&
      ownerState!.api.token == token;

  bool get current =>
      ownerCurrent && snapshot.isNotEmpty && snapshot == fingerprint();
  bool get active => current && foreground && route?.isCurrent != false;

  bool get disclosed => const {
    'given',
    'hint1',
    'hint2',
    'hint3',
    'solution',
  }.contains(widget.block['disclosure']);

  List<String>? get originals {
    final value = widget.block['labels'];
    if (value is! List || value.length < 2 || value.length > 4) return null;
    final result = <String>[];
    final distinct = <String>{};
    for (final text in value) {
      if (text is! String ||
          text.trim().isEmpty ||
          text.runes.length > 160 ||
          !distinct.add(text.replaceAll(RegExp(r'\s+'), ' ').trim())) {
        return null;
      }
      result.add(text); // Preserve every original character and whitespace.
    }
    for (final key in ['numbers', 'connections', 'marks']) {
      final field = widget.block[key];
      if (field != null && (field is! List || field.isNotEmpty)) return null;
    }
    if ((widget.block['unit'] ?? '') != '' ||
        widget.block['scene'] != null ||
        widget.block['text_probe'] != null ||
        widget.block['lab'] != null) {
      return null;
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    ownerState = widget.state;
    owner = ownerState?.user;
    ownerId = owner?['id']?.toString();
    family = ownerState?.familyId;
    token = ownerState?.api.token;
    snapshot = fingerprint();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    ownerState?.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void accountChanged() {
    if (!mounted || ownerCurrent) return;
    setState(() {
      invalidated = true;
      generation++;
    });
  }

  @override
  void didUpdateWidget(covariant LanguageComparisonWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.state, ownerState) || !ownerCurrent) {
      invalidated = true;
      generation++;
    } else if (snapshot != fingerprint()) {
      snapshot = fingerprint();
      generation++;
      focus = LanguageComparisonFocus.differences;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context);
    if ((route != null && !identical(route, next)) ||
        next?.isCurrent == false) {
      generation++;
    }
    route = next;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (!mounted) return;
    setState(() {
      foreground = value == AppLifecycleState.resumed;
      generation++;
    });
  }

  @override
  void dispose() {
    ownerState?.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<TextSpan> spans(String original, Set<String> common) {
    final palette = context.palette;
    final result = <TextSpan>[];
    var offset = 0;
    for (final match in words.allMatches(original)) {
      if (match.start > offset) {
        result.add(TextSpan(text: original.substring(offset, match.start)));
      }
      final word = match.group(0)!;
      final marked = switch (focus) {
        LanguageComparisonFocus.differences => !common.contains(word),
        LanguageComparisonFocus.commonWords => common.contains(word),
        LanguageComparisonFocus.none => false,
      };
      result.add(
        TextSpan(
          text: word,
          style: marked
              ? TextStyle(
                  color: focus == LanguageComparisonFocus.commonWords
                      ? palette.cyanInk
                      : palette.teal,
                  backgroundColor: focus == LanguageComparisonFocus.commonWords
                      ? palette.cyanSurface
                      : palette.mint,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                )
              : null,
        ),
      );
      offset = match.end;
    }
    if (offset < original.length) {
      result.add(TextSpan(text: original.substring(offset)));
    }
    return result;
  }

  String label(LanguageComparisonFocus value) => switch (value) {
    LanguageComparisonFocus.differences => 'Unterschiede',
    LanguageComparisonFocus.commonWords => 'Gleiche Wörter',
    LanguageComparisonFocus.none => 'Ohne Markierung',
  };

  @override
  Widget build(BuildContext context) {
    if (widget.block['kind'] != 'forms' ||
        widget.block['variant'] != 'classification' ||
        !disclosed) {
      return const SizedBox.shrink();
    }
    if (!current) {
      return const Notice(
        'Diese Textbeispiele sind nicht mehr für dieses Konto geöffnet. Öffne die Lernrunde erneut.',
      );
    }
    if (!foreground) return const SizedBox.shrink();
    final texts = originals;
    if (texts == null) {
      return const Notice('Dieser Originalvergleich ist hier nicht verfügbar.');
    }
    final sets = [
      for (final text in texts)
        words.allMatches(text).map((match) => match.group(0)!).toSet(),
    ];
    final common = sets
        .skip(1)
        .fold<Set<String>>(
          sets.first,
          (shared, next) => shared.intersection(next),
        );
    final epoch = generation;
    final rawTitle = widget.block['title'];
    final title = rawTitle is String && rawTitle.runes.length <= 160
        ? rawTitle
        : 'Originaltexte vergleichen';
    return ExcludeFocus(
      excluding: !active,
      child: IgnorePointer(
        ignoring: !active,
        child: LearningGraphicFrame(
          key: const ValueKey('language-comparison'),
          title: title,
          // Its own zoom covers this route; keep the launcher state mounted.
          // IgnorePointer/ExcludeFocus and owner/route guards still block it.
          action: widget.action,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in LanguageComparisonFocus.values)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth,
                        ),
                        child: Semantics(
                          selected: focus == value,
                          child: OutlinedButton(
                            key: ValueKey('language-comparison-${value.name}'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              backgroundColor: focus == value
                                  ? context.palette.mint
                                  : null,
                            ),
                            onPressed: active
                                ? () {
                                    if (!active || epoch != generation) return;
                                    setState(() => focus = value);
                                  }
                                : null,
                            child: Text(
                              label(value),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  switch (focus) {
                    LanguageComparisonFocus.differences => 'Markiert und unterstrichen: Wörter, die nicht in allen Beispielen gleich vorkommen.',
                    LanguageComparisonFocus.commonWords => 'Markiert und unterstrichen: Wörter mit gleicher Schreibweise in allen Beispielen.',
                    LanguageComparisonFocus.none =>
                      'Alle Originaltexte ohne Markierung.',
                  },
                  key: const ValueKey('language-comparison-legend'),
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
              for (final (index, text) in texts.indexed) ...[
                if (index > 0) const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.palette.panelSurface,
                    border: Border.all(color: context.palette.surfaceBorder),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Beispiel ${index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(children: spans(text, common)),
                        key: ValueKey('language-comparison-original-$index'),
                        semanticsLabel: text,
                        style: const TextStyle(fontSize: 17, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
