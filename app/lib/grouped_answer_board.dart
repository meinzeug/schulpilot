import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'math_content.dart';
import 'ui.dart';

/// Only the public field schema is read here. Solutions stay on the server.
class GroupedAnswerField {
  final String id, label, kind;
  final List<String> options;
  const GroupedAnswerField(this.id, this.label, this.kind, this.options);
}

class GroupedAnswerSpec {
  final List<GroupedAnswerField> fields;
  const GroupedAnswerSpec._(this.fields);

  static GroupedAnswerSpec? tryParse(Object? value) {
    if (value is! Map || value['version'] != 1 || value['fields'] is! List) {
      return null;
    }
    final raw = value['fields'] as List;
    if (raw.length < 2 || raw.length > 4) return null;
    final result = <GroupedAnswerField>[];
    final ids = <String>{};
    for (final item in raw) {
      if (item is! Map) return null;
      final id = item['id'], label = item['label'], kind = item['kind'];
      final options = item['options'];
      if (id is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,48}$').hasMatch(id) ||
          !ids.add(id) ||
          label is! String ||
          label.trim().isEmpty ||
          label.runes.length > 160 ||
          !['text', 'select'].contains(kind) ||
          options is! List ||
          options.any(
            (v) => v is! String || v.trim().isEmpty || v.runes.length > 160,
          )) {
        return null;
      }
      final choices = options.cast<String>();
      if ((kind == 'text' && choices.isNotEmpty) ||
          (kind == 'select' &&
              (choices.length < 2 ||
                  choices.length > 6 ||
                  choices.toSet().length != choices.length))) {
        return null;
      }
      result.add(
        GroupedAnswerField(
          id,
          label,
          kind as String,
          List.unmodifiable(choices),
        ),
      );
    }
    return GroupedAnswerSpec._(List.unmodifiable(result));
  }

  Map<String, String> decode(String answer) {
    if (answer.isEmpty || answer.runes.length > 8192) return {};
    try {
      final value = jsonDecode(answer);
      if (value is! Map ||
          value.length != 2 ||
          value['version'] != 1 ||
          value['fields'] is! Map) {
        return {};
      }
      final entries = value['fields'] as Map;
      if (entries.keys.any((id) => !fields.any((f) => f.id == id))) return {};
      final result = <String, String>{};
      for (final field in fields) {
        final text = entries.containsKey(field.id) ? entries[field.id] : '';
        if (text is! String ||
            text.runes.length > 160 ||
            (text.isNotEmpty &&
                field.kind == 'select' &&
                !field.options.contains(text))) {
          return {};
        }
        result[field.id] = text;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  String encode(Map<String, String> values) => jsonEncode({
    'version': 1,
    'fields': {for (final field in fields) field.id: values[field.id] ?? ''},
  });

  int filled(Map<String, String> values) =>
      fields.where((f) => (values[f.id] ?? '').trim().isNotEmpty).length;

  bool ready(String answer) =>
      answer.runes.length <= 1000 && filled(decode(answer)) == fields.length;

  String readable(String answer) {
    final values = decode(answer);
    return fields
        .map(
          (f) =>
              '${f.label}: ${values[f.id]?.isNotEmpty == true ? values[f.id] : 'Nicht ausgefüllt'}',
        )
        .join('\n');
  }
}

/// Controlled input only: typing and selecting never assess or submit a field.
class GroupedAnswerBoard extends StatefulWidget {
  final GroupedAnswerSpec spec;
  final String questionId, answer;
  final Object sourceKey;
  final bool disabled;
  final ValueChanged<String> onChanged;
  const GroupedAnswerBoard({
    super.key,
    required this.spec,
    required this.questionId,
    required this.sourceKey,
    required this.answer,
    required this.disabled,
    required this.onChanged,
  });

  @override
  State<GroupedAnswerBoard> createState() => _GroupedAnswerBoardState();
}

class _GroupedAnswerBoardState extends State<GroupedAnswerBoard>
    with WidgetsBindingObserver {
  final _controllers = <String, TextEditingController>{};
  final _focus = <String, FocusNode>{};
  final _targets = <String, GlobalKey>{};
  Object _epoch = Object();
  DialogRoute<String>? _selector;
  bool _resumed = true;
  bool _updating = false;

  bool get _enabled =>
      mounted &&
      !widget.disabled &&
      _resumed &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    _resumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _syncControllers();
  }

  void _invalidate() {
    _epoch = Object();
    for (final node in _focus.values) {
      node.unfocus();
    }
    final route = _selector;
    _selector = null;
    if (route != null) {
      Future<void>.microtask(() {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  void _syncControllers() {
    _updating = true;
    final ids = widget.spec.fields.map((f) => f.id).toSet();
    for (final id in _controllers.keys.toList()) {
      if (!ids.contains(id)) {
        _controllers.remove(id)!.dispose();
        _focus.remove(id)!.dispose();
        _targets.remove(id);
      }
    }
    final values = widget.spec.decode(widget.answer);
    for (final field in widget.spec.fields) {
      final controller = _controllers.putIfAbsent(
        field.id,
        () => TextEditingController(),
      );
      _focus.putIfAbsent(field.id, () => FocusNode());
      _targets.putIfAbsent(field.id, GlobalKey.new);
      final value = values[field.id] ?? '';
      if (controller.text != value) {
        controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
    }
    _updating = false;
  }

  @override
  void didUpdateWidget(covariant GroupedAnswerBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.questionId != widget.questionId ||
        !listEquals(
          oldWidget.spec.fields
              .map((f) => (f.id, f.label, f.kind, f.options.join('\u0000')))
              .toList(),
          widget.spec.fields
              .map((f) => (f.id, f.label, f.kind, f.options.join('\u0000')))
              .toList(),
        ) ||
        (!oldWidget.disabled && widget.disabled)) {
      _invalidate();
    }
    _syncControllers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false && _selector == null) {
      _invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (!_resumed) _invalidate();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _invalidate();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _change(GroupedAnswerField field, String value) {
    if (_updating || !_enabled || value.runes.length > 160) return;
    if (field.kind == 'select' && !field.options.contains(value)) return;
    final values = widget.spec.decode(widget.answer);
    values[field.id] = value;
    widget.onChanged(
      values.values.every((v) => v.isEmpty) ? '' : widget.spec.encode(values),
    );
  }

  Future<void> _choose(GroupedAnswerField field) async {
    if (!_enabled) return;
    final epoch = _epoch;
    final values = widget.spec.decode(widget.answer);
    final route = DialogRoute<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        scrollable: true,
        title: MathText(field.label),
        content: SizedBox(
          width: 440,
          child: RadioGroup<String>(
            groupValue: values[field.id],
            onChanged: (value) => Navigator.of(dialog).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < field.options.length; i++)
                  RadioListTile<String>(
                    key: ValueKey('group-option-${field.id}-$i'),
                    value: field.options[i],
                    title: MathText(
                      field.options[i],
                      style: const TextStyle(fontSize: 16, height: 1.4),
                    ),
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 56,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Zurück zur Aufgabe'),
          ),
        ],
      ),
    );
    _selector = route;
    final value = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    if (identical(_selector, route)) _selector = null;
    if (value != null && identical(epoch, _epoch) && _enabled) {
      _change(field, value);
    }
  }

  Future<void> _firstOpen() async {
    if (!_enabled) return;
    final values = widget.spec.decode(widget.answer);
    final field = widget.spec.fields
        .where((f) => (values[f.id] ?? '').trim().isEmpty)
        .firstOrNull;
    if (field == null) return;
    final epoch = _epoch;
    final target = _targets[field.id]?.currentContext;
    if (target != null) {
      await Scrollable.ensureVisible(
        target,
        alignment: .25,
        duration: const Duration(milliseconds: 180),
      );
    }
    if (!mounted || !identical(epoch, _epoch) || !_enabled) return;
    _focus[field.id]?.requestFocus();
    if (field.kind == 'select') await _choose(field);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final values = widget.spec.decode(widget.answer);
    final filled = widget.spec.filled(values);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            '$filled von ${widget.spec.fields.length} Feldern ausgefüllt',
            key: const ValueKey('grouped-filled'),
            style: TextStyle(color: p.muted, fontSize: 14, height: 1.4),
          ),
        ),
        if (filled < widget.spec.fields.length)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('grouped-first-open'),
              onPressed: _enabled ? _firstOpen : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                alignment: Alignment.centerLeft,
              ),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Erstes offenes Feld'),
            ),
          ),
        const SizedBox(height: 8),
        for (var i = 0; i < widget.spec.fields.length; i++) ...[
          Builder(
            key: _targets[widget.spec.fields[i].id],
            builder: (context) {
              final field = widget.spec.fields[i];
              final value = values[field.id] ?? '';
              final epoch = _epoch;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MathText(
                    '${i + 1}. ${field.label}',
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (field.kind == 'text')
                    TextField(
                      key: ValueKey(
                        'group-field-${widget.questionId}-${field.id}',
                      ),
                      controller: _controllers[field.id],
                      focusNode: _focus[field.id],
                      enabled: _enabled,
                      maxLength: 160,
                      inputFormatters: [
                        TextInputFormatter.withFunction(
                          (before, after) =>
                              after.text.runes.length <= 160 ? after : before,
                        ),
                      ],
                      buildCounter:
                          (
                            context, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => Text(
                            '${_controllers[field.id]!.text.runes.length}/160',
                            semanticsLabel:
                                '${_controllers[field.id]!.text.runes.length} von 160 Zeichen',
                            style: TextStyle(color: p.muted, fontSize: 12),
                          ),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontSize: 16, height: 1.4),
                      scrollPadding: const EdgeInsets.all(24),
                      decoration: InputDecoration(
                        labelText: 'Deine Eingabe',
                        semanticCounterText: 'Höchstens 160 Zeichen',
                        contentPadding: const EdgeInsets.all(14),
                        constraints: const BoxConstraints(minHeight: 56),
                      ),
                      onChanged: (value) {
                        if (identical(epoch, _epoch)) _change(field, value);
                      },
                      onSubmitted: (_) {
                        if (!_enabled || !identical(epoch, _epoch)) return;
                        if (i + 1 < widget.spec.fields.length) {
                          _focus[widget.spec.fields[i + 1].id]?.requestFocus();
                        } else {
                          FocusManager.instance.primaryFocus?.unfocus();
                        }
                      },
                    )
                  else
                    OutlinedButton(
                      key: ValueKey(
                        'group-field-${widget.questionId}-${field.id}',
                      ),
                      focusNode: _focus[field.id],
                      onPressed: _enabled
                          ? () {
                              if (identical(epoch, _epoch)) _choose(field);
                            }
                          : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 56),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.all(14),
                        backgroundColor: p.surfaceLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: MathText(
                              value.isEmpty ? 'Antwort auswählen' : value,
                              style: const TextStyle(fontSize: 16, height: 1.4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.expand_more_rounded, size: 22),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
        ],
        if (widget.answer.runes.length > 1000)
          const Notice(
            'Die Eingaben sind zusammen zu lang. Kürze sie, damit du speichern und prüfen kannst.',
            warning: true,
          ),
      ],
    );
  }
}

/// Saved values and server verdicts only; never computes whether a value is right.
class GroupedAnswerSummary extends StatelessWidget {
  final GroupedAnswerSpec? spec;
  final String answer;
  final Object? parts;
  const GroupedAnswerSummary({
    super.key,
    required this.spec,
    required this.answer,
    this.parts,
  });

  @override
  Widget build(BuildContext context) {
    final schema = spec;
    if (schema == null) {
      return const Text('Die gespeicherte Feldantwort ist vorhanden.');
    }
    final values = schema.decode(answer);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in schema.fields)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Builder(
              builder: (context) {
                final savedParts = parts is List
                    ? (parts as List)
                          .whereType<Map>()
                          .where((p) => p['id'] == field.id)
                          .toList()
                    : <Map>[];
                final result = savedParts.isEmpty
                    ? null
                    : savedParts.first['outcome'];
                final label = switch (result) {
                  'correct' => 'Richtig',
                  'incorrect' => 'Noch einmal prüfen',
                  'uncertain' => 'Bewertung offen',
                  _ => null,
                };
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label != null) ...[
                      Icon(
                        result == 'correct'
                            ? Icons.check_circle_outline_rounded
                            : result == 'incorrect'
                            ? Icons.refresh_rounded
                            : Icons.help_outline_rounded,
                        semanticLabel: label,
                        color: result == 'correct'
                            ? context.palette.successInk
                            : context.palette.warningInk,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MathText(
                            field.label,
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                          MathText(
                            values[field.id]?.isNotEmpty == true
                                ? values[field.id]!
                                : 'Nicht ausgefüllt',
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (label != null)
                            Text(
                              label,
                              style: TextStyle(
                                color: context.palette.muted,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}
