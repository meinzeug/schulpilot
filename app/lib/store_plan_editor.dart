import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Local catalogue comparison; opening and changing it never sends a request.
class StorePlanComparison extends StatefulWidget {
  final List<Json> plans;
  const StorePlanComparison(this.plans, {super.key});
  @override
  State<StorePlanComparison> createState() => _StorePlanComparisonState();
}

class _StorePlanComparisonState extends State<StorePlanComparison> {
  int children = 1;
  @override
  Widget build(BuildContext context) {
    final matching =
        widget.plans.where((p) => (p['children'] as num) >= children).toList()
          ..sort(
            (a, b) =>
                (a['price_cents'] as num).compareTo(b['price_cents'] as num),
          );
    return ExpansionTile(
      title: const Text('Tarife nach Kinderzahl vergleichen'),
      childrenPadding: const EdgeInsets.only(bottom: 20),
      children: [
        DropdownButtonFormField<int>(
          initialValue: children,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Benötigte Kinderzugänge',
          ),
          items: [
            for (var n = 1; n <= 20; n++)
              DropdownMenuItem(
                value: n,
                child: Text('$n ${n == 1 ? 'Kinderzugang' : 'Kinderzugänge'}'),
              ),
          ],
          onChanged: (n) {
            if (n != null) setState(() => children = n);
          },
        ),
        const SizedBox(height: 12),
        const Text(
          'Passende aktuell angebotene Tarife, nach Gesamtpreis sortiert. Die KI-Schritte gelten gemeinsam je Laufzeit; es wird nichts automatisch ausgewählt oder bestellt.',
        ),
        if (matching.isEmpty)
          const Text(
            'Kein aktuell angebotener Tarif deckt diese Kinderzahl ab.',
          ),
        for (final plan in matching)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${plan['name']} · ${_price(plan['price_cents'] as int)}',
            ),
            subtitle: Text(
              '${plan['children']} Kinderzugänge · ${plan['calls']} KI-Schritte · 30 Tage',
            ),
          ),
      ],
    );
  }
}

String _price(int cents) =>
    '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')} €';

/// Structured edits only change the existing in-memory JSON draft. The caller
/// retains the explicit, revision-bound publication action.
class StorePlanEditor extends StatefulWidget {
  final AppState state;
  final TextEditingController controller;
  final bool enabled;
  const StorePlanEditor(
    this.state, {
    super.key,
    required this.controller,
    required this.enabled,
  });
  @override
  State<StorePlanEditor> createState() => _StorePlanEditorState();
}

class _StorePlanEditorState extends State<StorePlanEditor> {
  late final owner = widget.state.user;
  bool get own =>
      mounted && identical(widget.state.user, owner) && widget.enabled;
  List<Json>? read() {
    try {
      final list = jsonDecode(widget.controller.text);
      if (list is! List ||
          list.any(
            (p) =>
                p is! Map ||
                p.keys.any(
                  (k) => !{
                    'id',
                    'name',
                    'price_cents',
                    'children',
                    'calls',
                  }.contains(k),
                ),
          )) {
        return null;
      }
      return list.map((p) => Json.from(p as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  void write(List<Json> list) {
    if (own) {
      widget.controller.text = const JsonEncoder.withIndent('  ').convert(list);
    }
  }

  Future<void> edit({int? index, bool duplicate = false}) async {
    final list = read();
    if (!own ||
        list == null ||
        (index == null || duplicate) && list.length >= 6) {
      return;
    }
    final before = widget.controller.text;
    final original = index == null ? null : list[index];
    final route = DialogRoute<Json>(
      context: context,
      builder: (_) => _PlanDialog(
        original: original,
        duplicate: duplicate,
        existingIds: list.indexed
            .where((e) => duplicate || e.$1 != index)
            .map((e) => '${e.$2['id']}')
            .toSet(),
      ),
    );
    void changed() {
      if (!own && route.isActive) route.navigator?.removeRoute(route);
    }

    widget.state.addListener(changed);
    try {
      final result = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(route);
      if (!own || result == null || widget.controller.text != before) return;
      if (index == null || duplicate) {
        list.add(result);
      } else {
        list[index] = result;
      }
      write(list);
    } finally {
      widget.state.removeListener(changed);
    }
  }

  Future<void> remove(int index) async {
    final list = read();
    if (!own || list == null || list.length <= 1) return;
    final before = widget.controller.text;
    final confirmed = await confirmDialog(
      context,
      'Tarif aus dem Entwurf entfernen?',
      '${list[index]['name']} (${list[index]['id']}) wird nur aus diesem Verkaufsentwurf entfernt. Vorhandene Bestellungen behalten ihren gespeicherten Tarifstand. Veröffentlicht wird erst beim Speichern.',
      confirmLabel: 'Tarif aus Entwurf entfernen',
      destructive: true,
    );
    if (confirmed && own && widget.controller.text == before) {
      list.removeAt(index);
      write(list);
    }
  }

  void move(int index, int direction) {
    final list = read(), target = index + direction;
    if (!own || list == null || target < 0 || target >= list.length) return;
    final item = list.removeAt(index);
    list.insert(target, item);
    write(list);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final list = read();
      return ExpansionTile(
        title: const Text('Tarife mit Formular bearbeiten'),
        children: [
          const Text(
            'Alle Änderungen bleiben ein lokaler Verkaufsentwurf. Der feste Zeitraum bleibt 30 Tage; gespeicherte Bestellungen werden nicht umgeschrieben.',
          ),
          if (list == null)
            const Text(
              'Zuerst die JSON-Tarifliste korrigieren. Das Formular ersetzt keinen unlesbaren oder unbekannten Entwurf.',
            ),
          if (list != null) ...[
            for (final (index, plan) in list.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${plan['name'] ?? 'Name fehlt'} · ${plan['id'] ?? 'Kennung fehlt'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: own ? () => edit(index: index) : null,
                          child: Text('Tarif ${index + 1} bearbeiten'),
                        ),
                        TextButton(
                          onPressed: own && list.length < 6
                              ? () => edit(index: index, duplicate: true)
                              : null,
                          child: Text('Tarif ${index + 1} duplizieren'),
                        ),
                        TextButton(
                          onPressed: own && list.length > 1
                              ? () => remove(index)
                              : null,
                          child: Text('Tarif ${index + 1} entfernen'),
                        ),
                        IconButton(
                          tooltip: 'Tarif ${index + 1} nach oben',
                          onPressed: own && index > 0
                              ? () => move(index, -1)
                              : null,
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: 'Tarif ${index + 1} nach unten',
                          onPressed: own && index + 1 < list.length
                              ? () => move(index, 1)
                              : null,
                          icon: const Icon(Icons.arrow_downward),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: own && list.length < 6 ? () => edit() : null,
              icon: const Icon(Icons.add),
              label: const Text('Tarif zum Entwurf hinzufügen'),
            ),
            if (list.length >= 6)
              const Text('Höchstens sechs Tarife pro Verkaufsstand.'),
          ],
        ],
      );
    },
  );
}

class _PlanDialog extends StatefulWidget {
  final Json? original;
  final bool duplicate;
  final Set<String> existingIds;
  const _PlanDialog({
    required this.original,
    required this.duplicate,
    required this.existingIds,
  });
  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  final form = GlobalKey<FormState>();
  late final values = <String, TextEditingController>{
    for (final key in ['id', 'name', 'price_cents', 'children', 'calls'])
      key: TextEditingController(
        text: key == 'id' && widget.duplicate
            ? ''
            : '${widget.original?[key] ?? ''}',
      ),
  };
  final focuses = List.generate(5, (_) => FocusNode());
  final keys = List.generate(5, (_) => GlobalKey<FormFieldState<String>>());
  @override
  void dispose() {
    for (final c in values.values) {
      c.dispose();
    }
    for (final f in focuses) {
      f.dispose();
    }
    super.dispose();
  }

  String? validate(String key, String? raw) {
    final value = (raw ?? '').trim();
    if (key == 'id') {
      if (!RegExp(r'^[a-z][a-z0-9-]{1,29}$').hasMatch(value)) {
        return '2 bis 30 Kleinbuchstaben, Ziffern oder Bindestriche; mit Buchstabe beginnen.';
      }
      if (widget.existingIds.contains(value)) {
        return 'Diese Kennung ist bereits im Entwurf vorhanden.';
      }
    } else if (key == 'name') {
      if (value.isEmpty || value.runes.length > 40) {
        return 'Einen Namen mit 1 bis 40 Zeichen eingeben.';
      }
    } else {
      final range = {
        'price_cents': (100, 25000),
        'children': (1, 20),
        'calls': (10, 10000),
      }[key]!;
      final number = int.tryParse(value);
      if (number == null || number < range.$1 || number > range.$2) {
        return 'Eine ganze Zahl von ${range.$1} bis ${range.$2} eingeben.';
      }
    }
    return null;
  }

  void save() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (!form.currentState!.validate()) {
      final first = keys.indexWhere((k) => k.currentState?.hasError == true);
      if (first >= 0) {
        focuses[first].requestFocus();
        final context = keys[first].currentContext;
        if (context != null) Scrollable.ensureVisible(context, alignment: .2);
      }
      return;
    }
    Navigator.of(context).pop(<String, dynamic>{
      for (final entry in values.entries)
        entry.key: ['id', 'name'].contains(entry.key)
            ? entry.value.text.trim()
            : int.parse(entry.value.text.trim()),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.duplicate
          ? 'Tarif als neue Kennung duplizieren'
          : widget.original == null
          ? 'Neuer Tarif im Entwurf'
          : 'Tarif im Entwurf bearbeiten',
    ),
    scrollable: true,
    content: SizedBox(
      width: 460,
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Keine Veröffentlichung und keine Bestellung. Preise und Leistungen bewusst eintragen; Laufzeit 30 Tage.',
            ),
            for (final (index, entry) in const {
              'id': 'Tarifkennung',
              'name': 'Tarifname',
              'price_cents': 'Gesamtpreis in Cent',
              'children': 'Kinderzugänge',
              'calls': 'KI-Schritte je Laufzeit',
            }.entries.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: TextFormField(
                  key: keys[index],
                  focusNode: focuses[index],
                  controller: values[entry.key],
                  enabled:
                      entry.key != 'id' ||
                      widget.original == null ||
                      widget.duplicate,
                  autocorrect: false,
                  keyboardType: index > 1
                      ? TextInputType.number
                      : TextInputType.text,
                  textInputAction: index == 4
                      ? TextInputAction.done
                      : TextInputAction.next,
                  onFieldSubmitted: (_) {
                    if (index == 4) {
                      save();
                    } else {
                      focuses[index + 1].requestFocus();
                    }
                  },
                  validator: (v) => validate(entry.key, v),
                  decoration: InputDecoration(
                    labelText: entry.value,
                    errorMaxLines: 4,
                    helperText:
                        entry.key == 'id' &&
                            widget.original != null &&
                            !widget.duplicate
                        ? 'Die bestehende Kennung bleibt erhalten.'
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          if (ModalRoute.of(context)?.isCurrent == true) {
            Navigator.of(context).pop();
          }
        },
        child: const Text('Abbrechen'),
      ),
      FilledButton(onPressed: save, child: const Text('In Entwurf übernehmen')),
    ],
  );
}
