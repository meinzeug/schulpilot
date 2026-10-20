import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'admin_workspace_ui.dart';
import 'ui.dart';

class AiCostPanel extends StatelessWidget {
  final AppState state;
  const AiCostPanel(this.state, {super.key});
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
            '${data['peak_calls_per_minute'] ?? 0} Aufrufe / Minute in der Spitze · ${data['escalations'] ?? 0} schwierige Fälle',
          ),
          const SizedBox(height: 14),
          if ((data['models'] as Map? ?? {}).isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: SurfaceInset(
                child: Text('Noch kein zuordenbarer Modellverbrauch erfasst.'),
              ),
            ),
          if (data['budget_policy'] is Map) ...[
            Text(
              'Pro Kind und Monat: Ziel ${(data['budget_policy']['target_eur_micros'] / 1000000).toStringAsFixed(2)} € · Warnung ${(data['budget_policy']['warning_eur_micros'] / 1000000).toStringAsFixed(2)} € · Grenze ${(data['budget_policy']['hard_eur_micros'] / 1000000).toStringAsFixed(2)} €',
            ),
            for (final row in data['child_budgets'] as List? ?? [])
              ListTile(
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
                  '${_budgetState(row['state'])} · ${(row['held_eur_micros'] / 1000000).toStringAsFixed(2)} € einschließlich Reservierungen · ${row['unsettled_calls']} Abrechnungen offen',
                ),
              ),
            const SizedBox(height: 14),
          ],
          for (final entry in Json.from(data['models'] ?? {}).entries) ...[
            SurfaceInset(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    entry.key,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${entry.value['calls']} Aufrufe · ${(entry.value['billed_micros_usd'] / 1000000).toStringAsFixed(5)} USD erfasst',
                  ),
                  Text(
                    '${entry.value['unknown_calls']} Kosten offen · ${entry.value['unusable_calls']} unbrauchbare Ergebnisse',
                  ),
                  Text(
                    'Latenz P50: ${entry.value['p50_ms'] ?? 'offen'} ms · P95: ${entry.value['p95_ms'] ?? 'offen'} ms',
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
                        'Ø ${(data['cost_per_completed_session_micros_usd'] / 1000000).toStringAsFixed(5)} USD zugeordnete Auftragskosten je Runde.',
                      ),
                    if (data['cost_per_independently_practiced_goal_micros_usd']
                        is num) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${data['independently_practiced_goals']} Lernziele mit selbstständiger Anwendung · Ø ${(data['cost_per_independently_practiced_goal_micros_usd'] / 1000000).toStringAsFixed(5)} USD zugeordnete Kosten.',
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
              'Künstliche Anbieterprüfungen: ${data['operator_probes']['calls'] ?? 0} Aufrufe · ${((data['operator_probes']['billed_micros_usd'] as num? ?? 0) / 1000000).toStringAsFixed(5)} USD erfasst · ${data['operator_probes']['unknown_calls'] ?? 0} Kosten offen.',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
          ],
          ExpansionTile(
            title: const Text('Kostenstellen'),
            children: [
              for (final row in data['cost_centres'] as List? ?? [])
                ListTile(
                  title: Text('Konto ${row[0]}'),
                  subtitle: Text(
                    '${row[1]['calls']} Aufrufe · keine privaten Lerninhalte',
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
  bool saving = false;
  int? amount(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d{1,4}(\.\d{1,6})?$').hasMatch(normalized)) return null;
    final parts = normalized.split('.');
    return int.parse(parts[0]) * 1000000 +
        int.parse((parts.length == 2 ? parts[1] : '').padRight(6, '0'));
  }

  @override
  void dispose() {
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
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      setState(() => saving = true);
                      try {
                        await widget.state.api.post(
                          '/admin/ai-credit-receipts',
                          {
                            'receipt_id': id.text,
                            'credits_micros_usd': amount(credits.text),
                            'fee_micros_usd': amount(fee.text),
                          },
                        );
                        if (context.mounted) {
                          toast(
                            context,
                            'Beleg erfasst. Offene Kosten werden abgeglichen.',
                          );
                          widget.onSaved();
                        }
                      } catch (e) {
                        if (context.mounted) showError(context, e);
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
  Json? data;
  bool saving = false;
  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoadView<Json>(
    load: () => widget.state.api.get('/admin/ai-routing'),
    builder: (value, reload) {
      data ??= value;
      if (draft.text.isEmpty) {
        draft.text = const JsonEncoder.withIndent('  ')
            .convert(data!['policy']);
      }
      final routes = Json.from(data!['policy']?['routes'] ?? {});
      return AdminWorkSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Geprüfter Modellmix',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              data!['policy']?['enabled'] == true
                  ? 'Routing eingeschaltet · Freigaben werden vor jedem Aufruf geprüft.'
                  : 'Routing noch nicht aktiviert.',
            ),
            for (final entry in routes.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.route_outlined,
                  color: context.palette.teal,
                ),
                title: Text(entry.value['model'] ?? entry.key),
                subtitle: Text(
                  '${(entry.value['upstreams'] as List? ?? []).join(', ')} · medium · ${entry.value['under13_approved'] == true ? 'Kinderroute freigegeben' : 'Kinderfreigabe offen'}',
                ),
              ),
            const Notice(
              'Neue Regeln sperren die Verarbeitung, bis die technische Prüfung abgeschlossen ist. Familien- und Systemgrenzen gelten zusätzlich.',
            ),
            ExpansionTile(
              title: const Text('Routingregeln bearbeiten'),
              children: [
                TextField(
                  controller: draft,
                  maxLines: 20,
                  minLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Versionierte Routingkonfiguration (JSON)',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() => saving = true);
                          try {
                            final response = await widget.state.api.put(
                              '/admin/ai-routing',
                              {
                                'revision': data!['revision'],
                                'policy': jsonDecode(draft.text),
                              },
                            );
                            if (mounted && context.mounted) {
                              setState(() => data = response);
                              toast(
                                context,
                                'Regeln gespeichert. Technische Prüfung erforderlich.',
                              );
                            }
                          } catch (e) {
                            if (mounted && context.mounted) {
                              showError(context, e);
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
