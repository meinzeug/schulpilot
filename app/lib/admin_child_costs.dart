import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Operator controls only. Reading or editing a draft never starts learning.
class AdminChildCosts extends StatefulWidget {
  final AppState state;
  final bool enabled;
  const AdminChildCosts(this.state, {super.key, this.enabled = true});
  @override
  State<AdminChildCosts> createState() => _AdminChildCostsState();
}

class _AdminChildCostsState extends State<AdminChildCosts>
    with WidgetsBindingObserver {
  final search = TextEditingController();
  final daily = TextEditingController();
  final monthly = TextEditingController();
  late Json? owner = widget.state.user;
  late String? token = widget.state.api.token;
  Json? selected, saved, latest;
  final items = <Json>[];
  String? cursor;
  String query = '', timezone = 'Europe/Berlin';
  String? error, notice, pendingKey, pendingBody;
  bool showSearch = false, loading = false, saving = false;
  bool configured = false, unlimitedDay = false, unlimitedMonth = false;
  bool foreground = true, dirty = false, needsRead = true;
  int epoch = 0, revision = 0;
  bool get current =>
      mounted &&
      widget.enabled &&
      foreground &&
      widget.state.isAdmin &&
      identical(widget.state.user, owner) &&
      widget.state.api.token == token &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(identity);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (current) load();
    });
  }

  @override
  void didUpdateWidget(covariant AdminChildCosts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      epoch++;
      loading = false;
    }
    if (widget.enabled && needsRead && !loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current) load();
      });
    }
  }

  void identity() {
    if (identical(widget.state.user, owner) &&
        widget.state.api.token == token) {
      return;
    }
    epoch++;
    items.clear();
    selected = saved = latest = null;
    search.clear();
    daily.clear();
    monthly.clear();
    pendingKey = pendingBody = null;
    error = notice = null;
    dirty = false;
    loading = saving = false;
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    if (!foreground) {
      epoch++;
      loading = saving = false;
      needsRead = true;
    }
    if (foreground && current && !saving) load();
  }

  @override
  void dispose() {
    epoch++;
    widget.state.removeListener(identity);
    WidgetsBinding.instance.removeObserver(this);
    search.dispose();
    daily.dispose();
    monthly.dispose();
    super.dispose();
  }

  static String money(Object? micros) =>
      micros is int ? '${amount(micros)} €' : 'offen';
  static String amount(Object? value) {
    if (value is! int) return '';
    final fraction = (value.abs() % 1000000)
        .toString()
        .padLeft(6, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '${value < 0 ? '-' : ''}${value.abs() ~/ 1000000}${fraction.isEmpty ? '' : ',$fraction'}';
  }

  static int? parseAmount(String input) {
    final value = input.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d{1,6}(?:\.\d{1,6})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    return int.parse(parts[0]) * 1000000 +
        int.parse((parts.length == 2 ? parts[1] : '').padRight(6, '0'));
  }

  String failure(Object e) => e is ApiError
      ? e.message
      : 'Der Stand konnte nicht geladen werden. Bitte erneut versuchen.';

  Future<void> load({bool more = false}) async {
    if (!current || loading) return;
    final request = ++epoch;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (selected != null) {
        final value = await widget.state.api.get(
          '/admin/children/${selected!['child_id']}/cost-controls',
        );
        if (!current || request != epoch) return;
        if (dirty) {
          latest = value;
        } else {
          bind(value);
        }
      } else {
        final path = Uri(
          path: '/admin/child-cost-controls',
          queryParameters: {
            'limit': '30',
            if (query.isNotEmpty) 'query': query,
            if (more && cursor != null) 'cursor': cursor!,
          },
        ).toString();
        final value = await widget.state.api.get(path);
        if (!current || request != epoch) return;
        if (!more) items.clear();
        for (final row in (value['items'] as List? ?? [])) {
          if (row is Map &&
              !items.any((item) => item['child_id'] == row['child_id'])) {
            items.add(Json.from(row));
          }
        }
        cursor = value['next_cursor'] as String?;
      }
      needsRead = false;
    } catch (e) {
      if (current && request == epoch) error = failure(e);
    } finally {
      if (mounted && request == epoch) setState(() => loading = false);
    }
  }

  void bind(Json value) {
    saved = value;
    latest = null;
    revision = value['revision'] as int? ?? 0;
    configured = value['enabled'] == true;
    timezone = value['timezone'] as String? ?? 'Europe/Berlin';
    unlimitedDay = value['daily_limit_eur_micros'] == null;
    unlimitedMonth = value['monthly_limit_eur_micros'] == null;
    daily.text = amount(value['daily_limit_eur_micros']);
    monthly.text = amount(value['monthly_limit_eur_micros']);
    dirty = false;
    pendingKey = pendingBody = null;
  }

  void changed() {
    if (current && !saving) {
      setState(() {
        dirty = true;
        notice = error = null;
      });
    }
  }

  Future<void> save() async {
    if (!current || saving || saved == null) return;
    final day = unlimitedDay ? null : parseAmount(daily.text);
    final month = unlimitedMonth ? null : parseAmount(monthly.text);
    if (configured &&
        ((!unlimitedDay && day == null) ||
            (!unlimitedMonth && month == null))) {
      setState(
        () => error = 'Gib einen Betrag ab 0 ein oder wähle „Unbegrenzt“.',
      );
      return;
    }
    final body = <String, dynamic>{
      'revision': revision,
      'enabled': configured,
      'timezone': timezone,
      'daily_limit_eur_micros': day,
      'monthly_limit_eur_micros': month,
    };
    final signature = jsonEncode(body);
    if (pendingBody != signature) {
      pendingBody = signature;
      pendingKey =
          'costs_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
    }
    final request = epoch;
    setState(() {
      saving = true;
      error = notice = null;
    });
    try {
      final value = Json.from(
        await widget.state.api.call(
          'PUT',
          '/admin/children/${selected!['child_id']}/cost-controls',
          body,
          {'Idempotency-Key': pendingKey!},
        ),
      );
      if (!current || request != epoch) return;
      setState(() {
        bind(value);
        notice = 'Gespeichert. Diese Grenzen gelten jetzt für neue KI-Aufrufe.';
      });
    } catch (e) {
      if (current && request == epoch) setState(() => error = failure(e));
    } finally {
      if (mounted && request == epoch) setState(() => saving = false);
    }
  }

  Widget period(Json? value, String title) {
    if (value == null) return const SizedBox.shrink();
    final limit = value['limit_eur_micros'];
    final held = value['held_eur_micros'];
    final fee = value['fee_reserved_eur_micros'];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${money(value['accounted_eur_micros'])} / ${saved?['enabled'] != true
                ? 'Bisherige Grenzen'
                : limit == null
                ? 'Unbegrenzt'
                : money(limit)}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Gemeldeter Anbieterpreis: ${money(value['known_provider_eur_micros'])}',
          ),
          if (held is num && held > 0)
            Text('Preis noch offen · reserviert: ${money(held)}'),
          if (value['fee_known_eur_micros'] is num &&
              value['fee_known_eur_micros'] > 0)
            Text('Belegte Gebühren: ${money(value['fee_known_eur_micros'])}'),
          if (fee is num && fee > 0)
            Text('Gebühren vorsorglich reserviert: ${money(fee)}'),
          if ((value['receipt_pending_calls'] as num? ?? 0) > 0)
            Text(
              '${value['receipt_pending_calls']} OpenRouter-Beleg(e) noch nicht abgeglichen.',
            ),
          if ((value['fee_adjustment_calls'] as num? ?? 0) > 0)
            const Text('Eine Gebührenkorrektur ist noch zu prüfen.'),
          if ((value['unknown_calls'] as num? ?? 0) > 0)
            Text(
              'Für ${value['unknown_calls']} Aufruf(e) liegt kein tatsächlicher Preis vor.',
            ),
        ],
      ),
    );
  }

  Widget limitField(
    String name,
    TextEditingController controller,
    bool unlimited,
    ValueChanged<bool> onUnlimited,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text('$name unbegrenzt'),
        value: unlimited,
        onChanged: !configured || saving
            ? null
            : (v) {
                onUnlimited(v);
                changed();
              },
      ),
      if (!unlimited)
        TextField(
          controller: controller,
          enabled: configured && !saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '$name in Euro',
            suffixText: '€',
          ),
          onChanged: (_) => changed(),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final buildEpoch = epoch, buildRevision = revision;
    final buildChild = selected?['child_id'];
    if (!widget.state.isAdmin ||
        !identical(widget.state.user, owner) ||
        widget.state.api.token != token) {
      return const SizedBox.shrink();
    }
    if (selected == null) {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Kosten pro Kind',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Kinderzugang suchen',
                  onPressed: () => setState(() => showSearch = !showSearch),
                  icon: const Icon(Icons.search_rounded),
                ),
                IconButton(
                  tooltip: 'Kostenlimits aktualisieren',
                  onPressed: loading ? null : load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const Text(
              'Tages- und Monatsgrenzen festlegen. „Unbegrenzt“ gilt nach dem Speichern.',
            ),
            if (showSearch)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    labelText: 'Kinderzugang suchen',
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) {
                    FocusScope.of(context).unfocus();
                    query = value.trim();
                    load();
                  },
                ),
              ),
            if (error != null) Notice(error!, warning: true),
            if (loading) const LinearProgressIndicator(),
            for (final row in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  row['username']?.toString() ??
                      row['account_label']?.toString() ??
                      'Kinderzugang',
                ),
                subtitle: Text(
                  row['mode'] == 'configured'
                      ? 'Eigene Tages- und Monatsgrenzen'
                      : 'Bisherige Kontingente',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  epoch++;
                  setState(() {
                    selected = row;
                    saved = null;
                    error = notice = null;
                    dirty = false;
                    loading = false;
                  });
                  load();
                },
              ),
            if (!loading && items.isEmpty && error == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Keine passenden Kinderzugänge.'),
              ),
            if (cursor != null)
              TextButton(
                onPressed: loading ? null : () => load(more: true),
                child: const Text('Weitere Kinderzugänge'),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: saving
              ? null
              : () {
                  epoch++;
                  setState(() {
                    selected = saved = latest = null;
                    error = notice = null;
                    dirty = false;
                    loading = false;
                  });
                  load();
                },
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Anderen Kinderzugang wählen'),
        ),
        Text(
          selected!['username']?.toString() ??
              selected!['account_label']?.toString() ??
              'Kinderzugang',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        if (loading) const LinearProgressIndicator(),
        if (saved != null) ...[
          if (saved!['system_stop'] == true ||
              (saved!['system_stop'] is Map &&
                  saved!['system_stop']['emergency_stop'] == true))
            Notice(
              'Ein gesonderter Systemstopp kann neue KI-Aufrufe anhalten. Die Kindereinstellung wird dadurch nicht geändert.',
              warning: true,
            ),
          if (saved!['system_stop'] is Map)
            Text(
              'Globales Betriebskostenlimit: ${amount(saved!['system_stop']['global_limit_micros_usd'])} USD. Anbieterfreigaben und dieser gesonderte Sicherheitsdeckel gelten weiterhin.',
            ),
          if (saved!['enabled'] != true)
            Text(
              'Bisherige Kontingente sind aktiv. Die unten angezeigten Beträge enthalten die bekannten Anbieterpreise und offene Reservierungen; die eigenen Tages- und Monatsgrenzen greifen erst nach dem Speichern.',
            ),
          if (saved!['legacy_effective'] is Map) ...[
            Text(
              'Bisherige Familiengrenze: ${amount(saved!['legacy_effective']['family']['limit_usd_micros'])} USD pro Monat · noch ${amount(saved!['legacy_effective']['family']['remaining_usd_micros'])} USD verfügbar.',
            ),
            Text(
              'Aufrufkontingent: ${saved!['legacy_effective']['family']['calls_used']} von ${saved!['legacy_effective']['family']['calls_limit']}.',
            ),
            if (saved!['legacy_effective']['route_child']['applies'] == true)
              Text(
                'Bisherige Kinderkostengrenze: ${money(saved!['legacy_effective']['route_child']['limit_eur_micros'])} pro Monat · einschließlich Reservierungen ${money(saved!['legacy_effective']['route_child']['encumbered_eur_micros'])}.',
              ),
          ],
          period(
            saved!['day'] is Map ? Json.from(saved!['day']) : null,
            'Heute',
          ),
          period(
            saved!['month'] is Map ? Json.from(saved!['month']) : null,
            'Diesen Monat',
          ),
          AdminCostCalls(
            widget.state,
            childId: selected!['child_id'].toString(),
            enabled: widget.enabled,
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Wirksame Grenzen',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Eigene Grenzen anwenden'),
                  subtitle: const Text(
                    'Diese Einstellungen ersetzen die bisherigen Aufruf- und Familienkostengrenzen für dieses Kind.',
                  ),
                  value: configured,
                  onChanged: saving
                      ? null
                      : (v) {
                          configured = v;
                          changed();
                        },
                ),
                if (!configured)
                  const Text(
                    'Aktuell gelten die bisherigen Kontingente. Aktiviere eigene Grenzen und speichere, um sie zu ersetzen.',
                  ),
                limitField(
                  'Tageslimit',
                  daily,
                  unlimitedDay,
                  (v) => unlimitedDay = v,
                ),
                limitField(
                  'Monatslimit',
                  monthly,
                  unlimitedMonth,
                  (v) => unlimitedMonth = v,
                ),
                const SizedBox(height: 12),
                Text(
                  'Abrechnung in Euro · Zeitzone $timezone. 0 € sperrt neue KI-Aufrufe. Gespeicherte Inhalte bleiben nutzbar.',
                ),
                const SizedBox(height: 12),
                if (error != null) Notice(error!, warning: true),
                if (notice != null) Notice(notice!),
                ActionButton(
                  label: saving ? 'Wird gespeichert …' : 'Grenzen speichern',
                  icon: Icons.check_rounded,
                  onPressed: () async {
                    if (current &&
                        epoch == buildEpoch &&
                        revision == buildRevision &&
                        selected?['child_id'] == buildChild) {
                      await save();
                    }
                  },
                  enabled: !saving,
                ),
                TextButton(
                  onPressed: saving || loading ? null : load,
                  child: const Text('Gespeicherten Stand prüfen'),
                ),
                if (latest != null) ...[
                  Notice(
                    'Der Serverstand wurde neu geladen. Deine Eingaben bleiben erhalten. Gespeichert sind: Tag ${latest!['daily_limit_eur_micros'] == null ? 'Unbegrenzt' : money(latest!['daily_limit_eur_micros'])}, Monat ${latest!['monthly_limit_eur_micros'] == null ? 'Unbegrenzt' : money(latest!['monthly_limit_eur_micros'])}.',
                    warning: true,
                  ),
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => setState(() {
                            revision = latest!['revision'] as int;
                            saved = latest;
                            latest = null;
                            pendingBody = pendingKey = null;
                          }),
                    child: const Text(
                      'Diese Serverfassung für meine Eingaben verwenden',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Explicit metadata inspection. No model call and no child content is loaded.
class AdminCostCalls extends StatefulWidget {
  final AppState state;
  final String childId;
  final bool enabled;
  const AdminCostCalls(
    this.state, {
    super.key,
    required this.childId,
    required this.enabled,
  });
  @override
  State<AdminCostCalls> createState() => _AdminCostCallsState();
}

class _AdminCostCallsState extends State<AdminCostCalls>
    with WidgetsBindingObserver {
  late final Json? owner = widget.state.user;
  late final String? token = widget.state.api.token;
  final rows = <Json>[];
  final refreshKeys = <String, String>{};
  String? cursor, error, notice;
  bool expanded = false, loading = false, foreground = true;
  int epoch = 0;
  bool get current =>
      mounted &&
      widget.enabled &&
      foreground &&
      widget.state.isAdmin &&
      identical(widget.state.user, owner) &&
      widget.state.api.token == token &&
      ModalRoute.of(context)?.isCurrent != false;
  @override
  void initState() {
    super.initState();
    widget.state.addListener(identity);
    WidgetsBinding.instance.addObserver(this);
  }

  void identity() {
    if (!identical(widget.state.user, owner) ||
        widget.state.api.token != token) {
      epoch++;
      rows.clear();
      cursor = null;
      error = notice = null;
      if (mounted) setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant AdminCostCalls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId || !widget.enabled) {
      epoch++;
      rows.clear();
      cursor = null;
      refreshKeys.clear();
      loading = expanded = false;
      error = notice = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      epoch++;
      loading = false;
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(identity);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String amount(dynamic v, [String currency = '€']) {
    if (v is! int) return 'Preis offen';
    final fraction = (v.abs() % 1000000).toString().padLeft(6, '0');
    return '${v < 0 ? '-' : ''}${v.abs() ~/ 1000000},$fraction $currency';
  }

  Future<void> load({bool more = false}) async {
    if (!current || loading || !expanded) return;
    final request = ++epoch;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.state.api.get(
        Uri(
          path: '/admin/children/${widget.childId}/cost-calls',
          queryParameters: {
            'limit': '30',
            if (more && cursor != null) 'cursor': cursor!,
          },
        ).toString(),
      );
      if (!current || request != epoch || !expanded) return;
      setState(() {
        if (!more) rows.clear();
        for (final raw in (value['items'] as List? ?? [])) {
          if (raw is Map && !rows.any((v) => v['id'] == raw['id'])) {
            rows.add(Json.from(raw));
          }
        }
        cursor = value['next_cursor'] as String?;
      });
    } catch (e) {
      if (current && request == epoch) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'Kostenbelege konnten nicht geladen werden.',
        );
      }
    } finally {
      if (mounted && request == epoch) setState(() => loading = false);
    }
  }

  Future<void> refresh(Json row) async {
    if (!current ||
        loading ||
        !expanded ||
        !rows.any((candidate) => identical(candidate, row))) {
      return;
    }
    final request = epoch;
    final id = row['id'].toString();
    final key = refreshKeys.putIfAbsent(
      id,
      () =>
          'receipt_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}',
    );
    setState(() {
      loading = true;
      error = notice = null;
    });
    try {
      await widget.state.api.post('/admin/usage/$id/refresh-cost', {}, {
        'Idempotency-Key': key,
      });
      if (!current || request != epoch || !expanded) return;
      setState(
        () => notice = 'Belegabgleich vorgemerkt. Mit „Belege aktualisieren“ den Stand laden. Es wird keine neue KI-Antwort erzeugt.',
      );
    } catch (e) {
      if (current && request == epoch) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'Belegabgleich konnte nicht vorgemerkt werden.',
        );
      }
    } finally {
      if (mounted && request == epoch) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buildEpoch = epoch;
    final buildChild = widget.childId;
    if (!identical(widget.state.user, owner) ||
        widget.state.api.token != token ||
        !widget.state.isAdmin) {
      return const SizedBox.shrink();
    }
    return ExpansionTile(
      title: const Text('Preisbelege der Aufrufe'),
      subtitle: const Text('OpenRouter-Preise, Abgleich und offene Beträge'),
      onExpansionChanged: (v) {
        expanded = v;
        if (!v) {
          epoch++;
          loading = false;
        } else if (rows.isEmpty) {
          load();
        }
      },
      children: [
        if (error != null) Notice(error!, warning: true),
        if (notice != null) Notice(notice!),
        if (loading) const LinearProgressIndicator(),
        TextButton.icon(
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Belege aktualisieren'),
        ),
        for (final row in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${row['provider']} · ${row['model']}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['receipt_state'] == 'verified_generation'
                      ? 'Mit OpenRouter-Generierungsbeleg abgeglichen'
                      : row['receipt_state'] == 'reported'
                      ? 'Anbieterpreis gemeldet · Belegabgleich offen'
                      : 'Tatsächlicher Preis unbekannt',
                ),
                Text('Anbieter: ${amount(row['provider_usd_micros'], 'USD')}'),
                if (row['created'] is int)
                  Text(
                    DateTime.fromMillisecondsSinceEpoch(row['created'] * 1000)
                        .toLocal()
                        .toString(),
                  ),
                if (row['held_eur_micros'] is int && row['held_eur_micros'] > 0)
                  Text(
                    'Offener Betrag reserviert: ${amount(row['held_eur_micros'])}',
                  ),
                if (row['fee_state'] == 'estimated')
                  Text(
                    'Gebührenreserve: ${amount(row['fee_reserved_eur_micros'])}',
                  ),
                if (row['fee_state'] == 'adjustment_pending')
                  const Text('Gebührenkorrektur zu prüfen'),
                if (row['fee_state'] == 'actual')
                  Text(
                    'Belegte Gebühren: ${amount(row['fee_known_eur_micros'])}',
                  ),
                if (row['provider'] == 'openrouter' &&
                    row['receipt_state'] != 'verified_generation' &&
                    row['status'] != 'reserved')
                  TextButton(
                    onPressed: loading
                        ? null
                        : () {
                            if (current &&
                                epoch == buildEpoch &&
                                widget.childId == buildChild &&
                                rows.any((v) => identical(v, row))) {
                              refresh(row);
                            }
                          },
                    child: const Text('Generierungsbeleg abgleichen'),
                  ),
              ],
            ),
          ),
        if (cursor != null)
          TextButton(
            onPressed: loading ? null : () => load(more: true),
            child: const Text('Weitere Aufrufbelege'),
          ),
        if (!loading && rows.isEmpty && error == null)
          const Text('Keine Aufrufbelege vorhanden.'),
      ],
    );
  }
}
