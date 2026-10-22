import 'dart:math';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Technical metadata only. No child/family context is requested or displayed.
class OperatorIncidentsScreen extends StatefulWidget {
  final AppState state;
  const OperatorIncidentsScreen(this.state, {super.key});
  @override
  State<OperatorIncidentsScreen> createState() =>
      _OperatorIncidentsScreenState();
}

class _OperatorIncidentsScreenState extends State<OperatorIncidentsScreen> {
  final search = TextEditingController();
  late final Json? owner;
  Json? listing, detail, catalog;
  String kind = '', code = '', query = '';
  String? selected, error, notice, requestKey, requestedSnapshot;
  int generation = 0, detailGeneration = 0, page = 1;
  bool loading = false, reading = false, acting = false;
  ModalRoute<bool>? confirmation;
  bool get current =>
      mounted && identical(owner, widget.state.user) && widget.state.isAdmin;
  bool get canAct =>
      current &&
      !acting &&
      !reading &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    widget.state.addListener(changed);
    load();
  }

  void changed() {
    if (mounted && !current) {
      generation++;
      detailGeneration++;
      final route = confirmation;
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
      setState(() {
        listing = detail = catalog = null;
        search.clear();
        requestKey = requestedSnapshot = null;
      });
    }
  }

  @override
  void dispose() {
    generation++;
    detailGeneration++;
    widget.state.removeListener(changed);
    search.dispose();
    super.dispose();
  }

  String safeError(Object value) => value is ApiError
      ? value.message
      : 'Die technische Übersicht ist gerade nicht erreichbar. Bitte erneut versuchen.';

  Future<void> load({int? targetPage}) async {
    if (!current || loading || acting) return;
    final token = ++generation;
    final wantedPage = targetPage ?? page;
    final wantedKind = kind, wantedCode = code, wantedQuery = query;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.state.api.get(
        Uri(
          path: '/admin/operator-incidents',
          queryParameters: {
            'kind': wantedKind,
            'code': wantedCode,
            'q': wantedQuery,
            'page': '$wantedPage',
          },
        ).toString(),
      );
      if (!current || token != generation) return;
      setState(() {
        listing = value;
        page = wantedPage;
      });
    } catch (e) {
      if (current && token == generation) setState(() => error = safeError(e));
    } finally {
      if (current && token == generation) setState(() => loading = false);
    }
  }

  Future<void> open(String id) async {
    if (!current || reading || acting) return;
    final token = ++detailGeneration;
    final same = selected == id;
    setState(() {
      selected = id;
      reading = true;
      error = null;
      if (!same) {
        detail = catalog = null;
        requestKey = requestedSnapshot = null;
        notice = null;
      }
    });
    try {
      final value = await widget.state.api.get('/admin/operator-incidents/$id');
      if (current && token == detailGeneration && selected == id) {
        setState(() => detail = value);
      }
    } catch (e) {
      if (current && token == detailGeneration) {
        setState(() => error = safeError(e));
      }
    } finally {
      if (current && token == detailGeneration) setState(() => reading = false);
    }
  }

  Future<bool> confirm(String title, String text, String action) async {
    if (!current || ModalRoute.of(context)?.isCurrent == false) return false;
    final source = ModalRoute.of(context);
    late final DialogRoute<bool> route;
    route = DialogRoute<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted && current && route.isCurrent) {
                Navigator.of(ctx).pop(false);
              }
            },
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              if (ctx.mounted && current && route.isCurrent) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: Text(action),
          ),
        ],
      ),
    );
    confirmation = route;
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    if (identical(confirmation, route)) confirmation = null;
    return current && source?.isCurrent != false && result == true;
  }

  Future<void> repair() async {
    if (!canAct || detail == null || selected == null) return;
    final shown = detail!, id = selected!;
    setState(() {
      acting = true;
      error = notice = null;
    });
    try {
      final capabilities = await widget.state.api.get(
        '/admin/operator-incidents/repair-capabilities',
      );
      if (!current || !identical(detail, shown) || selected != id) return;
      setState(() => catalog = capabilities);
      if (capabilities['available'] != true) return;
      final commit = shown['current_source']?['source_commit'];
      if (commit is! String) {
        setState(
          () => error = 'Der veröffentlichte Quellstand ist nicht bestätigt. Es wurde keine Reparatur beauftragt.',
        );
        return;
      }
      final allowed = await confirm(
        'Reparaturvorschlag anfordern?',
        'Der separate Codex-Worker prüft nur den bestätigten Quellstand und neutrale Fehlercodes mit ${capabilities['model']} / ${capabilities['reasoning_effort']}. Er erhält keine Kinderinhalte oder Serverzugänge. Der Auftrag kann Kontingent verbrauchen. Ein Patch wird anschließend geprüft und niemals automatisch übernommen.',
        'Patch vorschlagen lassen',
      );
      if (!allowed || !current || !identical(detail, shown) || selected != id) {
        return;
      }
      final binding = '${shown['snapshot_digest']}:$commit';
      if (requestKey == null || requestedSnapshot != binding) {
        requestKey =
            'repair-${List.generate(20, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
        requestedSnapshot = binding;
      }
      final value = await widget.state.api.post(
        '/admin/operator-incidents/$id/repairs',
        {
          'request_key': requestKey,
          'basis_snapshot_digest': shown['snapshot_digest'],
          'source_commit': commit,
        },
      );
      if (!current || !identical(detail, shown) || selected != id) return;
      setState(() {
        final previous = (shown['repairs'] as List? ?? []).where(
          (r) => r['id'] != value['id'],
        );
        detail = {
          ...shown,
          'repairs': [value, ...previous],
        };
        notice = 'Der Reparaturauftrag wurde gespeichert. Stand aktualisieren lädt nur den Status; es startet keinen weiteren Auftrag.';
      });
    } catch (e) {
      if (current && selected == id) setState(() => error = safeError(e));
    } finally {
      if (current) setState(() => acting = false);
    }
  }

  Future<void> download(Json repair) async {
    if (!canAct || repair['patch_available'] != true) return;
    final shown = detail;
    setState(() {
      acting = true;
      error = notice = null;
    });
    try {
      final bytes = await widget.state.api.bytes(
        '/admin/operator-incidents/repairs/${repair['id']}/patch',
      );
      if (!mounted ||
          !current ||
          !identical(detail, shown) ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final saved = await FileSaver.instance.saveAs(
        name: 'schulpilot-reparatur-${repair['id']}',
        bytes: bytes,
        fileExtension: 'patch',
        mimeType: MimeType.text,
      );
      if (current && identical(detail, shown) && saved != null) {
        setState(
          () => notice =
              'Patchdatei gespeichert. Es wurde kein Anwendungscode verändert.',
        );
      }
    } catch (e) {
      if (current) setState(() => error = safeError(e));
    } finally {
      if (current) setState(() => acting = false);
    }
  }

  Future<void> review(Json repair, String decision) async {
    if (!canAct || repair['patch_available'] != true) return;
    final shown = detail;
    setState(() => acting = true);
    try {
      if (!await confirm(
        'Patchprüfung vermerken?',
        decision == 'approved'
            ? 'Dies vermerkt nur deine fachliche Patchprüfung. Auch ein freigegebener Vorschlag wird nicht automatisch eingespielt.'
            : 'Der Vorschlag wird als abgelehnt vermerkt. Der Anwendungscode bleibt unverändert.',
        decision == 'approved' ? 'Als geprüft freigeben' : 'Vorschlag ablehnen',
      )) {
        return;
      }
      if (!current || !identical(detail, shown)) return;
      final value = await widget.state.api.post(
        '/admin/operator-incidents/repairs/${repair['id']}/review',
        {
          'revision': repair['revision'],
          'artifact_sha256': repair['artifact_sha256'],
          'decision': decision,
        },
      );
      if (!current || !identical(detail, shown)) return;
      setState(
        () => detail = {
          ...shown!,
          'repairs': [
            for (final r in shown['repairs'] as List)
              if (r['id'] == value['id']) value else r,
          ],
        },
      );
    } catch (e) {
      if (current) setState(() => error = safeError(e));
    } finally {
      if (current) setState(() => acting = false);
    }
  }

  String timestamp(dynamic value) =>
      value is num ? friendlyDate(value) : 'Nicht erfasst';
  String status(dynamic value) =>
      const {
        'queued': 'Wartet auf Prüfung',
        'running': 'Vorschlag entsteht',
        'completed': 'Vorschlag bereit',
        'failed': 'Vorschlag fehlgeschlagen',
        'cancelled': 'Auftrag beendet',
        'pending': 'Noch nicht geprüft',
        'approved': 'Als geprüft freigegeben',
        'rejected': 'Abgelehnt',
      }[value] ??
      'Stand unbekannt';

  Widget detailView() {
    final item = Json.from(detail!['incident'] as Map);
    final repairs = (detail!['repairs'] as List? ?? [])
        .whereType<Map>()
        .map(Json.from)
        .toList();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Technischer Fehler: ${item['code']}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SelectableText(
            'Auftragsart: ${item['kind']}\nCodefunktion: ${item['function']}\nAusnahmekategorie: ${item['exception_category']}\nHäufigkeit: ${item['occurrences']}\nErstmals: ${timestamp(item['first_seen'])}\nZuletzt: ${timestamp(item['last_seen'])}\nRelease: ${item['release']}\nTracekennung: ${item['trace_id'] ?? 'Historisch nicht erfasst'}',
          ),
          const SizedBox(height: 12),
          if (item['basis'] == 'job_history')
            const Notice(
              'Rückwirkende Metadaten aus fehlgeschlagenen Lernaufträgen. Deren genauer alter Quellstand und Ausnahme sind nicht gespeichert; die ursprüngliche Ursache ist damit nicht bewiesen.',
            ),
          Text(
            'Reparaturbasis: ${detail!['current_source']?['source_commit'] ?? 'Quellstand nicht bestätigt'}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionButton(
                label: 'Stand aktualisieren',
                icon: Icons.refresh,
                enabled: !acting && !reading,
                secondary: true,
                onPressed: () => open(selected!),
              ),
              ActionButton(
                label: 'Reparaturvorschlag anfordern',
                icon: Icons.build_outlined,
                enabled: !acting && !reading,
                onPressed: repair,
              ),
            ],
          ),
          if (catalog != null) ...[
            const SizedBox(height: 12),
            Notice('${catalog!['notice']}'),
          ],
          for (final r in repairs) ...[
            const Divider(height: 32),
            Text(
              status(r['status']),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text('${r['model']} · ${r['effort']} · ${timestamp(r['created'])}'),
            Text('Patchprüfung: ${status(r['review_status'])}'),
            SelectableText(
              'Patchbasis: ${r['source_commit'] ?? 'Nicht gemeldet'}',
            ),
            if (r['source_commit'] is String &&
                r['source_commit'] !=
                    detail!['current_source']?['source_commit'])
              const Notice(
                'Dieser Vorschlag gehört zu einer anderen Quellfassung als der aktuellen Veröffentlichung. Prüfe ihn anhand seiner gespeicherten Patchbasis; er wird nicht automatisch eingespielt.',
              ),
            if (r['error_code'] != null)
              Text('Technischer Auftragscode: ${r['error_code']}'),
            if (r['test_summary']?['executed'] == true &&
                r['test_summary']?['verification_kind'] == 'pytest')
              Text(
                'Isolierter Prüflauf: ${r['test_summary']['passed'] ?? '?'} bestanden, ${r['test_summary']['failed'] ?? '?'} fehlgeschlagen, ${r['test_summary']['skipped'] ?? '?'} ausgelassen.',
              )
            else
              const Text(
                'Kein unabhängig ausgeführter Testlauf nachgewiesen. Ein Modellbericht allein bestätigt keine bestandenen Tests.',
              ),
            if (r['test_summary']?['baseline']?['executed'] == true)
              Text(
                'Pytest vor der Änderung: ${r['test_summary']['baseline']['passed'] ?? '?'} bestanden, ${r['test_summary']['baseline']['failed'] ?? '?'} fehlgeschlagen.',
              ),
            if (r['test_summary']?['verification_kind'] == 'syntax_only')
              const Text(
                'Nur Syntaxprüfung: kein ausgeführter fachlicher Regressionstest nachgewiesen.',
              ),
            if (r['patch_available'] == true) ...[
              SelectableText('Patch-SHA256: ${r['artifact_sha256']}'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionButton(
                    label: 'Patchdatei herunterladen',
                    icon: Icons.download_outlined,
                    enabled: !acting,
                    secondary: true,
                    onPressed: () => download(r),
                  ),
                  ActionButton(
                    label: 'Als geprüft freigeben',
                    enabled: !acting,
                    secondary: true,
                    onPressed: () => review(r, 'approved'),
                  ),
                  TextButton(
                    onPressed: acting ? null : () => review(r, 'rejected'),
                    child: const Text('Vorschlag ablehnen'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return const SizedBox.shrink();
    if (selected != null) {
      return PageFrame(
        state: widget.state,
        title: 'Fehlerdetails',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton.icon(
              onPressed: acting
                  ? null
                  : () {
                      detailGeneration++;
                      setState(() {
                        selected = null;
                        detail = catalog = null;
                        reading = false;
                        error = notice = null;
                      });
                    },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Zur Fehlerübersicht'),
            ),
            if (reading) const LinearProgressIndicator(),
            if (error != null) ...[
              Semantics(liveRegion: true, child: Notice(error!, warning: true)),
              TextButton(
                onPressed: reading || acting ? null : () => open(selected!),
                child: const Text('Fehlerdetails erneut laden'),
              ),
            ],
            if (notice != null)
              Semantics(liveRegion: true, child: Notice(notice!)),
            if (detail != null) detailView(),
          ],
        ),
      );
    }
    final items = (listing?['items'] as List? ?? [])
        .whereType<Map>()
        .map(Json.from)
        .toList();
    final total = (listing?['pagination']?['total'] as num?)?.toInt() ?? 0;
    return PageFrame(
      state: widget.state,
      title: 'Technische Fehler',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Fehler prüfen und einen kontrollierten Reparaturvorschlag anfordern. Keine Kinderinhalte; kein automatisches Einspielen von Änderungen.',
          ),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    labelText: 'Technischen Code oder Funktion suchen',
                  ),
                  onSubmitted: loading || acting
                      ? null
                      : (_) {
                          query = search.text.trim();
                          load(targetPage: 1);
                        },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<String>(
                        initialValue: kind,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Auftragsart',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Alle Auftragsarten'),
                          ),
                          for (final value in listing?['kinds'] as List? ?? [])
                            DropdownMenuItem(
                              value: '$value',
                              child: Text('$value'),
                            ),
                        ],
                        onChanged: loading || acting
                            ? null
                            : (v) {
                                kind = v ?? '';
                                load(targetPage: 1);
                              },
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<String>(
                        initialValue: code,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Fehlercode',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Alle Fehlercodes'),
                          ),
                          for (final value in listing?['codes'] as List? ?? [])
                            DropdownMenuItem(
                              value: '$value',
                              child: Text('$value'),
                            ),
                        ],
                        onChanged: loading || acting
                            ? null
                            : (v) {
                                code = v ?? '';
                                load(targetPage: 1);
                              },
                      ),
                    ),
                    ActionButton(
                      label: 'Suchen',
                      enabled: !loading && !acting,
                      icon: Icons.search,
                      onPressed: () async {
                        query = search.text.trim();
                        await load(targetPage: 1);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (loading) const LinearProgressIndicator(),
                if (listing != null)
                  Text(
                    '$total technische Fehlergruppen · 30 Tage Aufbewahrung',
                  ),
                if (!loading && listing != null && items.isEmpty)
                  const Text(
                    'Für diese Auswahl liegen keine technischen Fehler vor.',
                  ),
                for (final item in items) ...[
                  const SizedBox(height: 12),
                  ActionPanel(
                    actionLabel: 'Fehlerdetails ansehen',
                    enabled: !loading && !reading && !acting,
                    onPressed: () => open(item['id']),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${item['code']} · ${item['kind']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${item['occurrences']} Vorkommnisse · zuletzt ${timestamp(item['last_seen'])}',
                        ),
                        Text('${item['function']}'),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: page > 1 && !loading && !acting
                          ? () => load(targetPage: page - 1)
                          : null,
                      child: const Text('Vorherige Fehlergruppen'),
                    ),
                    TextButton(
                      onPressed: page * 30 < total && !loading && !acting
                          ? () => load(targetPage: page + 1)
                          : null,
                      child: const Text('Weitere Fehlergruppen'),
                    ),
                    TextButton(
                      onPressed: !loading && !acting ? () => load() : null,
                      child: const Text('Übersicht neu laden'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Notice(error!, warning: true)),
            TextButton(
              onPressed: loading || reading || acting
                  ? null
                  : () => selected != null ? open(selected!) : load(),
              child: const Text('Erneut laden'),
            ),
          ],
          if (notice != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Notice(notice!)),
          ],
          if (reading) const LinearProgressIndicator(),
          if (detail != null) ...[const SizedBox(height: 20), detailView()],
        ],
      ),
    );
  }
}
