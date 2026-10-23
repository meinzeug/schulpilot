import 'package:flutter/material.dart';

import 'api.dart';
import 'math_content.dart';
import 'ui.dart';

/// Local editing aids for the student's own buffer. Never computes an answer.
class AnswerWritingTools extends StatefulWidget {
  final AppState state;
  final TextEditingController controller;
  final Object sourceKey;
  final bool enabled;
  final bool Function() isCurrent;
  final int maxLength;
  final FocusNode? inputFocus;
  const AnswerWritingTools({
    super.key,
    required this.state,
    required this.controller,
    required this.sourceKey,
    required this.enabled,
    required this.isCurrent,
    this.maxLength = 500,
    this.inputFocus,
  });

  @override
  State<AnswerWritingTools> createState() => _AnswerWritingToolsState();
}

class _AnswerWritingToolsState extends State<AnswerWritingTools>
    with WidgetsBindingObserver {
  Json? account;
  String? family, token;
  bool open = false, resumed = true;
  String tool = 'symbols';

  @override
  void initState() {
    super.initState();
    bind();
    resumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(ownerChanged);
  }

  void bind() {
    account = widget.state.user;
    family = widget.state.familyId;
    token = widget.state.api.token;
    open = false;
    tool = 'symbols';
  }

  void ownerChanged() {
    if (!mounted) return;
    if (!identical(account, widget.state.user) ||
        family != widget.state.familyId ||
        token != widget.state.api.token) {
      setState(() => open = false);
    }
  }

  bool get usable =>
      mounted &&
      resumed &&
      widget.enabled &&
      account != null &&
      identical(account, widget.state.user) &&
      family == widget.state.familyId &&
      token == widget.state.api.token &&
      widget.isCurrent();

  @override
  void didUpdateWidget(covariant AnswerWritingTools oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.removeListener(ownerChanged);
      widget.state.addListener(ownerChanged);
      bind();
    } else if (oldWidget.sourceKey != widget.sourceKey ||
        !identical(oldWidget.controller, widget.controller) ||
        oldWidget.enabled && !widget.enabled) {
      bind();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      resumed = state == AppLifecycleState.resumed;
      if (!resumed) open = false;
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(ownerChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<int> boundaries(String value) {
    var offset = 0;
    return [0, for (final part in value.characters) offset += part.length];
  }

  (int, int) selection(String value, TextSelection current) {
    if (!current.isValid ||
        current.start > value.length ||
        current.end > value.length) {
      return (value.length, value.length);
    }
    final stops = boundaries(value);
    return (
      stops.lastWhere((i) => i <= current.start),
      stops.firstWhere((i) => i >= current.end),
    );
  }

  String replaced(String symbol) {
    final value = widget.controller.value;
    final range = selection(value.text, value.selection);
    return value.text.replaceRange(range.$1, range.$2, symbol);
  }

  void insert(String symbol) {
    if (!usable) return;
    final value = widget.controller.value;
    final range = selection(value.text, value.selection);
    final next = replaced(symbol);
    if (next.runes.length > widget.maxLength) return;
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: range.$1 + symbol.length),
    );
    widget.inputFocus?.requestFocus();
  }

  void move(String direction) {
    if (!usable) return;
    final value = widget.controller.value;
    final stops = boundaries(value.text);
    final range = selection(value.text, value.selection);
    final caret = direction == 'left' ? range.$1 : range.$2;
    final offset = switch (direction) {
      'start' => 0,
      'end' => value.text.length,
      'left' when !value.selection.isCollapsed || range.$1 != range.$2 =>
        range.$1,
      'right' when !value.selection.isCollapsed || range.$1 != range.$2 =>
        range.$2,
      'left' => stops.where((i) => i < caret).lastOrNull ?? 0,
      _ => stops.where((i) => i > caret).firstOrNull ?? value.text.length,
    };
    widget.controller.selection = TextSelection.collapsed(offset: offset);
    widget.inputFocus?.requestFocus();
  }

  static const symbols = <(String, String)>[
    ('/', 'Bruchstrich'),
    ('·', 'Malpunkt'),
    ('×', 'Malzeichen'),
    ('÷', 'Geteiltzeichen'),
    ('−', 'Minuszeichen'),
    ('±', 'Plusminus'),
    ('√', 'Wurzelzeichen'),
    ('π', 'Pi'),
    ('²', 'Hoch zwei'),
    ('³', 'Hoch drei'),
    ('°', 'Gradzeichen'),
    ('%', 'Prozent'),
    ('(', 'Klammer auf'),
    (')', 'Klammer zu'),
    ('≤', 'Kleiner gleich'),
    ('≥', 'Größer gleich'),
    ('≠', 'Ungleich'),
    ('→', 'Pfeil nach rechts'),
    ('Δ', 'Delta'),
    ('μ', 'My'),
    ('Ω', 'Omega'),
  ];

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: widget.controller,
    builder: (context, value, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            expanded: open,
            child: TextButton.icon(
              key: const ValueKey('writing-tools-toggle'),
              onPressed: usable ? () => setState(() => open = !open) : null,
              icon: Icon(open ? Icons.expand_less : Icons.edit_note_rounded),
              label: const Text('Schreibwerkzeuge'),
            ),
          ),
        ),
        if (open && usable)
          SurfaceInset(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in const [
                      ('symbols', 'Zeichen'),
                      ('cursor', 'Cursor'),
                      ('preview', 'Eingabe ansehen'),
                    ])
                      ChoiceChip(
                        key: ValueKey('writing-tool-${entry.$1}'),
                        label: Text(entry.$2),
                        selected: tool == entry.$1,
                        onSelected: (_) {
                          if (usable) setState(() => tool = entry.$1);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (tool == 'symbols') ...[
                  const Text('Füge ein Zeichen an deiner Schreibposition ein.'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final item in symbols)
                        Tooltip(
                          message: item.$2,
                          child: Semantics(
                            label: '${item.$2} einfügen',
                            child: OutlinedButton(
                              key: ValueKey('writing-symbol-${item.$1}'),
                              onPressed:
                                  replaced(item.$1).runes.length <=
                                      widget.maxLength
                                  ? () => insert(item.$1)
                                  : null,
                              child: ExcludeSemantics(
                                child: Text(
                                  item.$1,
                                  style: const TextStyle(fontSize: 19),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (tool == 'cursor') ...[
                  const Text(
                    'Bewege nur die Schreibposition. Dein Text bleibt erhalten.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final item in const <(String, String, IconData)>[
                        ('start', 'Zum Textanfang', Icons.first_page_rounded),
                        (
                          'left',
                          'Ein Zeichen nach links',
                          Icons.chevron_left_rounded,
                        ),
                        (
                          'right',
                          'Ein Zeichen nach rechts',
                          Icons.chevron_right_rounded,
                        ),
                        ('end', 'Zum Textende', Icons.last_page_rounded),
                      ])
                        IconButton(
                          key: ValueKey('writing-cursor-${item.$1}'),
                          tooltip: item.$2,
                          onPressed: () => move(item.$1),
                          icon: Icon(item.$3),
                        ),
                    ],
                  ),
                ],
                if (tool == 'preview') ...[
                  const Text(
                    'Deine Eingabe · keine Bewertung',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (value.text.isEmpty)
                    const Text('Schreibe zuerst deine eigene Antwort.')
                  else
                    MathText(
                      value.text,
                      key: const ValueKey('writing-own-preview'),
                      style: const TextStyle(fontSize: 21, height: 1.5),
                    ),
                ],
              ],
            ),
          ),
      ],
    ),
  );
}
