import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'admin_workspace_ui.dart';
import 'ui.dart';

class AiCostPanel extends StatefulWidget {
  final AppState state;
  final VoidCallback? onOpenRouting;
  const AiCostPanel(this.state, {super.key, this.onOpenRouting});
  @override
  State<AiCostPanel> createState() => _AiCostPanelState();
}

class _AiCostPanelState extends State<AiCostPanel> {
  bool anomaliesOnly = false;
  AppState get state => widget.state;
  bool anomaly(dynamic value) =>
      value is Map &&
      ((value['unknown_calls'] as num? ?? 0) > 0 ||
          (value['unusable_calls'] as num? ?? 0) > 0);
  String number(dynamic value) => value is num && value.isFinite && value >= 0
      ? '$value'
      : 'nicht gemeldet';
  String usd(dynamic value) => value is num && value.isFinite && value >= 0
      ? '${(value / 1000000).toStringAsFixed(6)} USD'
      : 'nicht gemeldet';
  String eur(dynamic value) => value is num && value.isFinite && value >= 0
      ? '${(value / 1000000).toStringAsFixed(6)} €'
      : 'nicht gemeldet';
  void modelDetails(String model, Json value) {
    showAdminDetails(
      context,
      state,
      title: 'Verbrauch für $model',
      notice: 'Aggregierte Betriebsdaten aus dem geladenen Stand. Ein Aufruf oder geringer Preis belegt keinen Lernerfolg.',
      rows: [
        ('Modellkennung', model),
        ('Aufrufe', number(value['calls'])),
        ('Erfasste Kosten', usd(value['billed_micros_usd'])),
        ('Kosten noch offen', number(value['unknown_calls'])),
        ('Unbrauchbare Ergebnisse', number(value['unusable_calls'])),
        ('Latenz P50', '${number(value['p50_ms'])} ms'),
        ('Latenz P95', '${number(value['p95_ms'])} ms'),
      ],
      continueLabel: widget.onOpenRouting == null
          ? null
          : 'Routingregeln ansehen',
      onContinue: widget.onOpenRouting,
    );
  }

  @override
  Widget build(BuildContext context) => LoadView<Json>(
    load: () => state.api.get('/admin/ai-costs'),
    builder: (data, reload) => AdminWorkSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'KI-Verbrauch & Qualität',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: reload,
                tooltip: 'Kosten aktualisieren',
                icon: Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Text(
            '${number(data['peak_calls_per_minute'])} Aufrufe / Minute in der Spitze · ${number(data['escalations'])} schwierige Fälle',
          ),
          const SizedBox(height: 10),
          if ((data['models'] as Map? ?? {}).isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: SurfaceInset(
                child: Text('Noch kein zuordenbarer Modellverbrauch erfasst.'),
              ),
            ),
          if (data['budget_policy'] is Map) ...[
            Text(
              'Pro Kind und Monat: Ziel ${eur(data['budget_policy']['target_eur_micros'])} · Warnung ${eur(data['budget_policy']['warning_eur_micros'])} · Grenze ${eur(data['budget_policy']['hard_eur_micros'])}',
            ),
            for (final row in data['child_budgets'] as List? ?? [])
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  onTap: () => showAdminDetails(
                    context,
                    state,
                    title: 'Kostenstelle ${row['cost_centre']}',
                    notice: 'Anonyme Kostenstelle. Diese Ansicht öffnet keine privaten Familien- oder Lerninhalte.',
                    rows: [
                      (
                        'Gespeicherter Budgetstatus',
                        _budgetState(row['state']),
                      ),
                      (
                        'Mit Reservierungen gebunden',
                        eur(row['held_eur_micros']),
                      ),
                      ('Offene Abrechnungen', number(row['unsettled_calls'])),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    row['state'] == 'within_target'
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    color: row['state'] == 'within_target'
                        ? context.palette.successInk
                        : context.palette.warningInk,
                  ),
                  title: Text('Kostenstelle ${row['cost_centre']}'),
                  subtitle: Text(
                    '${_budgetState(row['state'])} · ${eur(row['held_eur_micros'])} einschließlich Reservierungen · ${number(row['unsettled_calls'])} Abrechnungen offen',
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Alle Modelle'),
                selected: !anomaliesOnly,
                onSelected: (_) => setState(() => anomaliesOnly = false),
              ),
              ChoiceChip(
                label: const Text('Offene Kosten / unbrauchbar'),
                selected: anomaliesOnly,
                onSelected: (_) => setState(() => anomaliesOnly = true),
              ),
            ],
          ),
          if (anomaliesOnly &&
              !Json.from(data['models'] ?? {}).values.any(anomaly))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Keine Modelle mit offenen Kosten oder unbrauchbaren Ergebnissen im geladenen Stand.',
              ),
            ),
          const ExpansionTile(
            title: Text('Was bedeuten P50 und P95?'),
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Latenz ist die Dauer eines Aufrufs in Millisekunden. P50: Die Hälfte der gemessenen Aufrufe war höchstens so langsam. P95: 95 Prozent waren höchstens so langsam. Fehlende Werte sind keine gemessene Null.',
                ),
              ),
            ],
          ),
          for (final entry in Json.from(
            data['models'] ?? {},
          ).entries.where((e) => !anomaliesOnly || anomaly(e.value))) ...[
            ActionPanel(
              padding: const EdgeInsets.all(14),
              actionLabel: 'Verbrauch für ${entry.key} ansehen',
              onPressed: () => modelDetails(entry.key, Json.from(entry.value)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${number(entry.value['calls'])} Aufrufe · ${usd(entry.value['billed_micros_usd'])} erfasst',
                  ),
                  Text(
                    '${number(entry.value['unknown_calls'])} Kosten offen · ${number(entry.value['unusable_calls'])} unbrauchbare Ergebnisse',
                  ),
                  Text(
                    'P50 ${entry.value['p50_ms'] ?? 'offen'} ms · P95 ${entry.value['p95_ms'] ?? 'offen'} ms',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            data['note'] ?? '',
            style: TextStyle(color: context.palette.muted),
          ),
          if (data['completed_costed_sessions'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: SurfaceInset(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Zuordnung zu Lernrunden',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${counted(data['completed_costed_sessions'] as num? ?? 0, 'abgeschlossene Runde', 'abgeschlossene Runden')} mit zuordenbaren Kosten.',
                    ),
                    if (data['cost_per_completed_session_micros_usd'] is num)
                      Text(
                        'Ø ${usd(data['cost_per_completed_session_micros_usd'])} zugeordnete Auftragskosten je Runde.',
                      ),
                    if (data['cost_per_independently_practiced_goal_micros_usd']
                        is num) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${data['independently_practiced_goals']} Lernziele mit selbstständiger Anwendung · Ø ${usd(data['cost_per_independently_practiced_goal_micros_usd'])} zugeordnete Kosten.',
                      ),
                      Text(
                        data['goal_cost_notice']?.toString() ?? 'Kostenverteilung auf geübte Ziele; keine dauerhafte Beherrschung.',
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${data['attribution_notice'] ?? 'Nur eindeutig zugeordnete Aufträge; keine vollständigen Kosten je Lernerfolg.'}',
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (data['operator_probes'] is Map) ...[
            const SizedBox(height: 10),
            Text(
              'Künstliche Anbieterprüfungen: ${number(data['operator_probes']['calls'])} Aufrufe · ${usd(data['operator_probes']['billed_micros_usd'])} erfasst · ${number(data['operator_probes']['unknown_calls'])} Kosten offen.',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
          ],
          ExpansionTile(
            title: const Text('Kostenstellen'),
            children: [
              if ((data['cost_centres'] as List? ?? []).isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Noch keine zugeordneten Kostenstellen.'),
                ),
              for (final row in data['cost_centres'] as List? ?? [])
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    onTap: () => showAdminDetails(
                      context,
                      state,
                      title: 'Kostenstelle ${row[0]}',
                      notice: 'Aggregierte technische Zuordnung ohne private Lerninhalte.',
                      rows: [
                        ('Kostenstellenkennung', '${row[0]}'),
                        ('Aufrufe', number(row[1]['calls'])),
                        ('Erfasste Kosten', usd(row[1]['billed_micros_usd'])),
                        ('Kosten noch offen', number(row[1]['unknown_calls'])),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    title: Text('Konto ${row[0]}'),
                    subtitle: Text(
                      '${row[1]['calls']} Aufrufe · keine privaten Lerninhalte',
                    ),
                  ),
                ),
            ],
          ),
          CreditReceiptForm(state, onSaved: reload),
        ],
      ),
    ),
  );
}

String _budgetState(dynamic value) => switch (value) {
  'within_target' => 'Innerhalb des Kostenziels',
  'over_target' => 'Kostenziel überschritten',
  'warning' => 'Warnschwelle erreicht',
  'blocked' => 'Kostengrenze erreicht',
  _ => 'Status nicht gemeldet',
};

class CreditReceiptForm extends StatefulWidget {
  final AppState state;
  final VoidCallback onSaved;
  const CreditReceiptForm(this.state, {super.key, required this.onSaved});
  @override
  State<CreditReceiptForm> createState() => _CreditReceiptFormState();
}

class _CreditReceiptFormState extends State<CreditReceiptForm> {
  final id = TextEditingController(),
      credits = TextEditingController(),
      fee = TextEditingController();
  final form = GlobalKey<FormState>();
  final focuses = List.generate(3, (_) => FocusNode());
  bool saving = false;
  String? error;
  late final Object? owner = widget.state.user;
  int? amount(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d{1,4}(\.\d{1,6})?$').hasMatch(normalized)) return null;
    final parts = normalized.split('.');
    return int.parse(parts[0]) * 1000000 +
        int.parse((parts.length == 2 ? parts[1] : '').padRight(6, '0'));
  }

  @override
  void dispose() {
    for (final focus in focuses) {
      focus.dispose();
    }
    id.dispose();
    credits.dispose();
    fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Vorhandenen Guthabenbeleg erfassen'),
    children: [
      const Notice(
        'Hier wird nichts gekauft. Nur einen vorhandenen Beleg eintragen. Die Gebühr wird anteilig dem tatsächlich verbrauchten Guthaben zugeordnet.',
      ),
      Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: id,
              focusNode: focuses[0],
              enabled: !saving,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => focuses[1].requestFocus(),
              decoration: const InputDecoration(
                labelText: 'Eindeutige Belegkennung',
              ),
              validator: (v) =>
                  RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(v ?? '')
                  ? null
                  : '8–64 Buchstaben, Zahlen, - oder _ verwenden.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: credits,
              focusNode: focuses[1],
              enabled: !saving,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => focuses[2].requestFocus(),
              decoration: const InputDecoration(
                labelText: 'Erworbenes Guthaben in USD',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) =>
                  (amount(v ?? '') ?? 0) > 0 && amount(v!)! <= 1000000000
                  ? null
                  : 'Gültigen Guthabenbetrag bis 1000 USD eintragen.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: fee,
              focusNode: focuses[2],
              enabled: !saving,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                labelText: 'Tatsächliche Kaufgebühr in USD',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) =>
                  amount(v ?? '') != null && amount(v!)! <= 100000000
                  ? null
                  : 'Gebühr laut Beleg bis 100 USD eintragen.',
            ),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: Listenable.merge([credits, fee]),
              builder: (context, _) {
                final value = amount(credits.text), charge = amount(fee.text);
                if (value == null || charge == null) {
                  return const SizedBox.shrink();
                }
                return Text(
                  'Belegentwurf: ${(value / 1000000).toStringAsFixed(6)} USD Guthaben + ${(charge / 1000000).toStringAsFixed(6)} USD Kaufgebühr = ${((value + charge) / 1000000).toStringAsFixed(6)} USD Gesamtzahlung.',
                );
              },
            ),
            if (error != null)
              Semantics(liveRegion: true, child: Notice(error!, warning: true)),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (saving || !identical(widget.state.user, owner)) {
                        return;
                      }
                      final invalid = form.currentState!.validateGranularly();
                      if (invalid.isNotEmpty) {
                        final target = invalid.first;
                        final controller =
                            (target.widget as TextFormField).controller;
                        final index = [id, credits, fee].indexOf(controller!);
                        if (index >= 0) focuses[index].requestFocus();
                        Scrollable.ensureVisible(target.context);
                        return;
                      }
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await widget.state.api.post(
                          '/admin/ai-credit-receipts',
                          {
                            'receipt_id': id.text,
                            'credits_micros_usd': amount(credits.text),
                            'fee_micros_usd': amount(fee.text),
                          },
                        );
                        if (context.mounted &&
                            identical(widget.state.user, owner)) {
                          id.clear();
                          credits.clear();
                          fee.clear();
                          toast(
                            context,
                            'Beleg erfasst. Offene Kosten werden abgeglichen.',
                          );
                          widget.onSaved();
                        }
                      } catch (e) {
                        if (context.mounted &&
                            identical(widget.state.user, owner)) {
                          setState(
                            () => error = e is ApiError ? e.message : 'Der Beleg konnte nicht gespeichert werden. Die Eingaben bleiben erhalten.',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => saving = false);
                      }
                    },
              child: const Text('Vorhandenen Beleg speichern'),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Operational JSON belongs here, never in a child's learning flow.
class AiRoutingPanel extends StatefulWidget {
  final AppState state;
  const AiRoutingPanel(this.state, {super.key});
  @override
  State<AiRoutingPanel> createState() => _AiRoutingPanelState();
}

class _AiRoutingPanelState extends State<AiRoutingPanel> {
  final draft = TextEditingController();
  final editor = ExpansibleController();
  final editorFocus = FocusNode();
  Json? data;
  bool saving = false, initialized = false;
  String? error;
  late final Object? owner = widget.state.user;
  @override
  void dispose() {
    editor.dispose();
    editorFocus.dispose();
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoadView<Json>(
    load: () => widget.state.api.get('/admin/ai-routing'),
    builder: (value, reload) {
      data ??= value;
      if (!initialized) {
        initialized = true;
        draft.text = const JsonEncoder.withIndent('  ')
            .convert(data!['policy']);
      }
      final routes = Json.from(data!['policy']?['routes'] ?? {});
      return AdminWorkSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Geprüfter Modellmix',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Gespeicherte Routingregeln neu laden',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: saving
                      ? null
                      : () async {
                          if (!identical(widget.state.user, owner)) return;
                          final saved = const JsonEncoder.withIndent('  ')
                              .convert(data!['policy']);
                          if (draft.text != saved &&
                              !await confirmDialog(
                                context,
                                'Routingentwurf beim Neuladen verwerfen?',
                                'Bei Abbrechen bleibt dein Entwurf hier erhalten. Es werden keine Regeln gespeichert.',
                              )) {
                            return;
                          }
                          if (!mounted ||
                              !identical(widget.state.user, owner)) {
                            return;
                          }
                          data = null;
                          initialized = false;
                          reload();
                        },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              data!['policy']?['enabled'] == true
                  ? 'Routing eingeschaltet · Freigaben werden vor jedem Aufruf geprüft.'
                  : 'Routing noch nicht aktiviert.',
            ),
            for (final entry in routes.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ActionPanel(
                  padding: const EdgeInsets.all(14),
                  actionLabel: 'Route ${entry.key} prüfen',
                  onPressed: saving
                      ? null
                      : () => showAdminDetails(
                          context,
                          widget.state,
                          title: 'Gespeicherte Route ${entry.key}',
                          notice: 'Geladene Konfiguration; kein neuer Modellaufruf und kein Nachweis der Nutzbarkeit.',
                          rows: [
                            ('Auftragsart', _routeTitle(entry.key)),
                            (
                              'Modellkennung',
                              '${entry.value['model'] ?? 'nicht gemeldet'}',
                            ),
                            (
                              'Feste Upstreams',
                              (entry.value['upstreams'] as List? ?? []).join(
                                ', ',
                              ),
                            ),
                            (
                              'Denkstufe',
                              '${entry.value['reasoning_effort'] ?? data!['effective_reasoning_effort'] ?? 'nicht gemeldet'}',
                            ),
                            (
                              'Kinderfreigabe',
                              entry.value['under13_approved'] == true
                                  ? 'Gespeichert'
                                  : 'Offen',
                            ),
                            (
                              'Konfigurationsrevision',
                              '${data!['revision'] ?? 'nicht gemeldet'}',
                            ),
                          ],
                          continueLabel: 'Routingentwurf öffnen',
                          onContinue: () {
                            if (!mounted ||
                                !identical(widget.state.user, owner)) {
                              return;
                            }
                            editor.expand();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted ||
                                  !identical(widget.state.user, owner)) {
                                return;
                              }
                              editorFocus.requestFocus();
                              final target = editorFocus.context;
                              if (target != null) {
                                Scrollable.ensureVisible(target);
                              }
                            });
                          },
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_routeTitle(entry.key)} · ${entry.value['model'] ?? 'Modell nicht gemeldet'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Route ${entry.key} · ${(entry.value['upstreams'] as List? ?? []).join(', ')} · Denkstufe: ${entry.value['reasoning_effort'] ?? data!['effective_reasoning_effort'] ?? 'nicht gemeldet'} · ${entry.value['under13_approved'] == true ? 'Kinderroute freigegeben' : 'Kinderfreigabe offen'}',
                      ),
                    ],
                  ),
                ),
              ),
            const Notice(
              'Neue Regeln sperren die Verarbeitung, bis die technische Prüfung abgeschlossen ist. Familien- und Systemgrenzen gelten zusätzlich.',
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: draft,
              builder: (context, _, _) => Text(
                draft.text ==
                        const JsonEncoder.withIndent('  ')
                            .convert(data!['policy'])
                    ? 'Gespeicherte Routingregeln · Revision ${data!['revision'] ?? 'nicht gemeldet'}'
                    : 'Ungespeicherter Routingentwurf · bisher gespeicherte Regeln bleiben aktiv',
              ),
            ),
            ExpansionTile(
              controller: editor,
              title: const Text('Routingregeln bearbeiten'),
              children: [
                TextField(
                  controller: draft,
                  focusNode: editorFocus,
                  enabled: !saving,
                  maxLines: 20,
                  minLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Versionierte Routingkonfiguration (JSON)',
                  ),
                ),
                const SizedBox(height: 12),
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Notice(error!, warning: true),
                  ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (saving || !identical(widget.state.user, owner)) {
                            return;
                          }
                          dynamic parsed;
                          try {
                            parsed = jsonDecode(draft.text);
                          } on FormatException catch (failure) {
                            setState(
                              () => error =
                                  'Die Routingregeln sind kein gültiges JSON${failure.offset == null ? '' : ' bei Zeichen ${failure.offset! + 1}'}. Der Entwurf bleibt erhalten.',
                            );
                            return;
                          }
                          if (parsed is! Map) {
                            setState(
                              () => error = 'Die Routingregeln müssen ein JSON-Objekt sein.',
                            );
                            return;
                          }
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            final response = await widget.state.api.put(
                              '/admin/ai-routing',
                              {'revision': data!['revision'], 'policy': parsed},
                            );
                            if (mounted &&
                                context.mounted &&
                                identical(widget.state.user, owner)) {
                              setState(() {
                                data = response;
                                draft.text = const JsonEncoder.withIndent('  ')
                                    .convert(response['policy']);
                              });
                              toast(
                                context,
                                'Regeln gespeichert. Technische Prüfung erforderlich.',
                              );
                            }
                          } catch (e) {
                            if (mounted &&
                                context.mounted &&
                                identical(widget.state.user, owner)) {
                              setState(
                                () => error = e is ApiError ? e.message : 'Die Routingregeln konnten nicht gespeichert werden. Dein Entwurf bleibt erhalten.',
                              );
                            }
                          } finally {
                            if (mounted) setState(() => saving = false);
                          }
                        },
                  child: const Text(
                    'Regeln speichern und zur Prüfung vormerken',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

String _routeTitle(String tier) => switch (tier) {
  'luna' => 'Kompakte Aufgaben und Hilfen',
  'sol' => 'Umfangreicher oder unklarer Bedarf',
  'astra' => 'Starke Eskalationsroute',
  _ => 'Modellroute',
};
