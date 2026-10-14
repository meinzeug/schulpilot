import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'material_screen.dart';
import 'ui.dart';

class SchoolDayScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  const SchoolDayScreen(this.state, {super.key, required this.childId});

  @override
  State<SchoolDayScreen> createState() => _SchoolDayScreenState();
}

class _SchoolDayScreenState extends State<SchoolDayScreen> {
  Json? day;
  String? error, reviewId;
  String progress = '';
  bool loading = true, working = false, fetching = false;
  Timer? poll;
  AppState get state => widget.state;
  List<Json> get pages => (day?['pages'] as List? ?? []).cast<Json>();
  bool get locked => working || day?['active_job'] != null;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (fetching) return;
    fetching = true;
    poll?.cancel();
    try {
      final result = await state.api.get(
        '/children/${widget.childId}/school-day/today',
      );
      Json? next = result['day'] as Json?;
      if (next == null && state.isChild) {
        next = await state.api.post(
          '/children/${widget.childId}/school-day/today',
        );
      }
      if (!mounted) return;
      setState(() {
        day = next;
        loading = false;
        final pending = pages.where(
          (p) => p['status'] == 'review' && p['confirmed'] != true,
        );
        if (reviewId == null ||
            !pages.any((p) => p['id'] == reviewId && p['confirmed'] != true)) {
          reviewId = pending.isEmpty ? null : pending.first['id'] as String;
        }
      });
      if (next?['active_job'] != null && !working) {
        poll = Timer(const Duration(seconds: 2), () => unawaited(load()));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    } finally {
      fetching = false;
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (locked) return;
    setState(() {
      working = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          working = false;
          progress = '';
        });
        await load();
      }
    }
  }

  Future<void> capture(ImageSource source, {bool recovered = false}) async {
    final status = await state.api.get('/status');
    if (status['real_data_enabled'] != true) {
      throw ApiError(
        'Echte Heftfotos sind bis zur dokumentierten Datenschutzfreigabe gesperrt. Im synthetischen Testraum kannst du den Ablauf mit zwei künstlichen Seiten testen.',
      );
    }
    if (!mounted) return;
    final nativeAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (nativeAndroid && !recovered) {
      await state.storage.write(key: 'camera_child', value: widget.childId);
    }
    if (!mounted) return;
    final bytes = recovered && state.recoveredPhoto != null
        ? await cropMaterialPhoto(context, state.recoveredPhoto!)
        : await pickMaterialPhoto(context, source);
    if (nativeAndroid) await state.storage.delete(key: 'camera_child');
    if (bytes == null) return;
    await state.api.upload(widget.childId, bytes, schoolDayId: day!['id']);
    if (recovered) state.recoveredPhoto = null;
  }

  Future<void> recognize() async {
    final pending = pages.where((p) => p['status'] == 'uploaded').toList();
    for (var i = 0; i < pending.length; i++) {
      if (!mounted) return;
      setState(
        () => progress = 'Seite ${i + 1} von ${pending.length} wird erkannt …',
      );
      await state.api.job('/materials/${pending[i]['id']}/extract');
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = day?['stage'] ?? 'collecting';
    final step = stage == 'collecting'
        ? 0
        : stage == 'ready'
        ? 2
        : 1;
    final parent = !state.isChild;
    final confirmed = day?['confirmed_count'] ?? 0;
    final preview = day?['plan'] as Json?;
    final allConfirmed = pages.isNotEmpty && confirmed == pages.length;
    final selected = pages.where((p) => p['id'] == reviewId).firstOrNull;
    return PageFrame(
      state: state,
      title: 'Nach der Schule.',
      subtitle: 'Deine Heftseiten von heute werden zu einem kleinen Lernpaket. Du kannst den Assistenten jederzeit verlassen und später fortsetzen.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => unawaited(load()),
          icon: const Icon(Icons.refresh),
          label: const Text('Aktualisieren'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in [
                (0, '1 · Seiten sammeln'),
                (1, '2 · Stoff prüfen'),
                (2, '3 · Lernen & festigen'),
              ])
                Tag(item.$2, color: step == item.$1 ? mint : Colors.white),
            ],
          ),
          const SizedBox(height: 24),
          if (loading) const Center(child: CircularProgressIndicator()),
          if (error != null) Notice(error!, warning: true),
          if (!loading && day == null)
            const Notice(
              'Für heute wurde noch kein Tagesassistent begonnen. Dein Kind kann ihn in seinem eigenen Lernraum starten.',
            ),
          if (day != null) ...[
            Text(
              '${day!['date']} · ${pages.length} von ${day!['max_pages']} möglichen Seiten · $confirmed geprüft',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            if (day!['synthetic'] == true)
              const Notice(
                'KI-Test mit zwei künstlichen Heftseiten ohne Kinderdaten. Erkennung und Paket-Erstellung verwenden tatsächlich das konfigurierte kostenlose OpenRouter-Modell. Keine eigenen Fotos oder Texte eingeben.',
                icon: Icons.science_outlined,
              ),
            if (locked)
              Panel(
                color: mint,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        progress.isEmpty
                            ? 'Dein Auftrag wird verarbeitet. Bereits erkannte Seiten bleiben gespeichert. Du kannst später wiederkommen.'
                            : progress,
                      ),
                    ),
                  ],
                ),
              ),
            if (!locked && day!['last_error'] != null && error == null)
              Notice(
                '${day!['last_error']} Bereits erkannte Seiten bleiben gespeichert. Ein erneuter Versuch wird als neuer KI-Aufruf gezählt.',
                warning: true,
              ),
            if (stage == 'collecting') ...[
              heading(
                'Alles von heute einsammeln',
                subtitle: 'Öffne nacheinander deine Hefter. Eine Seite pro Foto, gut beleuchtet und möglichst gerade. Schneide Namen vor dem Hochladen ab.',
              ),
              if (!parent &&
                  !locked &&
                  pages.length < (day!['max_pages'] as int))
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (day!['synthetic'] == true && pages.isEmpty)
                      ActionButton(
                        label: 'Zwei künstliche Heftseiten hinzufügen',
                        icon: Icons.science_outlined,
                        onPressed: () => run(() async {
                          await state.api.post(
                            '/school-days/${day!['id']}/synthetic-pages',
                          );
                        }),
                      )
                    else if (day!['synthetic'] != true) ...[
                      ActionButton(
                        label: pages.isEmpty
                            ? 'Erste Seite fotografieren'
                            : 'Nächste Seite fotografieren',
                        icon: Icons.add_a_photo_outlined,
                        onPressed: () => run(() => capture(ImageSource.camera)),
                      ),
                      ActionButton(
                        label: 'Foto aus Galerie hinzufügen',
                        icon: Icons.photo_library_outlined,
                        secondary: true,
                        onPressed: () =>
                            run(() => capture(ImageSource.gallery)),
                      ),
                      if (state.recoveredPhoto != null)
                        ActionButton(
                          label: 'Wiedergefundenes Foto prüfen',
                          icon: Icons.restore,
                          secondary: true,
                          onPressed: () => run(
                            () => capture(ImageSource.camera, recovered: true),
                          ),
                        ),
                    ],
                  ],
                ),
              const SizedBox(height: 20),
            ],
            if (stage != 'ready') ...[
              for (final page in pages)
                Padding(
                  key: ValueKey(page['id']),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (page['synthetic'] != true ||
                            page['fixture_id'] != null)
                          SizedBox(
                            width: 48,
                            height: 64,
                            child: LoadView<Uint8List>(
                              load: () => state.api.bytes(
                                '/materials/${page['id']}/image',
                              ),
                              builder: (bytes, _) =>
                                  Image.memory(bytes, fit: BoxFit.contain),
                            ),
                          )
                        else
                          const Icon(Icons.description_outlined, color: teal),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Seite ${page['page_number']} · ${page['subject'].toString().isEmpty ? 'Fach wird erkannt' : page['subject']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                page['confirmed'] == true
                                    ? 'Geprüft · ${page['topic']}'
                                    : page['status'] == 'review'
                                    ? 'Erkannt · Bitte prüfen'
                                    : 'Foto gespeichert',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (stage == 'collecting' &&
                            !locked &&
                            !parent &&
                            page['confirmed'] != true &&
                            day!['synthetic'] != true)
                          IconButton(
                            tooltip: 'Diese Seite entfernen',
                            onPressed: () => run(() async {
                              await state.api.delete(
                                '/school-days/${day!['id']}/pages/${page['id']}',
                              );
                            }),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        if (stage == 'review' && page['status'] != 'uploaded')
                          TextButton(
                            onPressed: () =>
                                setState(() => reviewId = page['id']),
                            child: const Text('Ansehen'),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 18),
            ],
            if (stage == 'collecting' && pages.isNotEmpty && !locked && !parent)
              ActionButton(
                label: 'Alle Seiten sind da · Weiter',
                icon: Icons.arrow_forward,
                onPressed: () => run(() async {
                  await state.api.put('/school-days/${day!['id']}/stage', {
                    'stage': 'review',
                  });
                }),
              ),
            if (stage == 'review') ...[
              if (!parent &&
                  !locked &&
                  pages.any((p) => p['status'] == 'uploaded'))
                ActionButton(
                  label: 'Heftseiten mit KI erkennen',
                  icon: Icons.document_scanner_outlined,
                  onPressed: () => run(recognize),
                ),
              if (selected != null && !locked) ...[
                const SizedBox(height: 22),
                heading(
                  'Seite ${selected['page_number']} prüfen',
                  subtitle: 'Stimmt der erkannte Stoff? Kläre unleserliche Stellen gemeinsam mit deinen Eltern. Bestätige nur, was du wirklich prüfen konntest.',
                ),
                MaterialReview(
                  state,
                  selected,
                  key: ValueKey('${selected['id']}-${selected['status']}'),
                  showUnitAction: false,
                  onRefresh: () => unawaited(load()),
                ),
              ],
              if (!locked && !parent) ...[
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: () => run(() async {
                    await state.api.put('/school-days/${day!['id']}/stage', {
                      'stage': 'collecting',
                    });
                  }),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Noch eine Seite hinzufügen'),
                ),
              ],
              if (allConfirmed) ...[
                const SizedBox(height: 24),
                heading(
                  'Dein Paket für heute',
                  subtitle: 'Zusammengehörige Seiten werden gemeinsam verarbeitet. Erst verstehen, dann mit kurzen Aufgaben festigen. Ausdrücklich notierte Hausaufgaben bleiben eigene Aufträge.',
                ),
                for (final group in preview?['groups'] as List? ?? [])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      group['selected'] == true
                          ? Icons.auto_stories_outlined
                          : Icons.schedule,
                      color: teal,
                    ),
                    title: Text(group['subject']),
                    subtitle: Text(
                      '${(group['topics'] as List).join(' · ')}\n${group['selected'] == true ? 'Heute · ca. ${group['estimated_minutes']} Minuten' : 'Gespeichert für später'}',
                    ),
                  ),
                for (final note in preview?['notices'] as List? ?? [])
                  Notice(note),
                if (!locked &&
                    !parent &&
                    (preview?['estimated_minutes'] ?? 0) > 0)
                  ActionButton(
                    label: 'Lernpaket für heute erstellen',
                    icon: Icons.auto_awesome_outlined,
                    onPressed: () => run(() async {
                      setState(
                        () => progress = 'Aus deinen geprüften Seiten entsteht dein Lernpaket …',
                      );
                      await state.api.job('/school-days/${day!['id']}/package');
                    }),
                  ),
              ],
            ],
            if (stage == 'ready') ...[
              heading(
                'Dein Lernpaket ist bereit',
                subtitle: 'Die Übungen wurden aus deinen bestätigten Seiten erstellt. Richtige Antworten und spätere Wiederholungen werden getrennt gespeichert.',
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Heftseiten dieses Tages (${pages.length})'),
                children: [
                  for (final page in pages)
                    ListTile(
                      title: Text(
                        'Seite ${page['page_number']} · ${page['subject']}',
                      ),
                      subtitle: Text(page['topic']),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          openRoute(context, '/material/${page['id']}'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              for (final unit in day!['units'] as List)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Panel(
                    color: mint,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tag(
                          unit['status'] == 'completed'
                              ? 'Abgeschlossen · später wiederholen'
                              : unit['status'] == 'not_started'
                              ? 'Noch nicht begonnen'
                              : 'Begonnen · weiterlernen',
                        ),
                        const SizedBox(height: 12),
                        heading(
                          '${unit['subject']} · ${unit['topic']}',
                          subtitle:
                              '${(unit['source_material_ids'] as List).length} Heftseite(n) · ${unit['questions'].length} Aufgaben · ca. ${unit['estimated_minutes']} Minuten',
                        ),
                        if (!locked)
                          ActionButton(
                            label: parent || unit['status'] == 'completed'
                                ? 'Einheit ansehen'
                                : unit['status'] == 'not_started'
                                ? 'Jetzt lernen & festigen'
                                : 'Weiterlernen',
                            icon: Icons.play_arrow_rounded,
                            onPressed: () async {
                              if (!parent && unit['status'] != 'completed') {
                                await state.api.post(
                                  '/units/${unit['id']}/start',
                                );
                              }
                              if (context.mounted) {
                                openRoute(context, '/unit/${unit['id']}');
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              for (final group in preview?['groups'] as List? ?? [])
                if (!(day!['units'] as List).any(
                  (u) =>
                      u['subject'].toString().toLowerCase() ==
                      group['subject'].toString().toLowerCase(),
                ))
                  Notice(
                    '${group['subject']}: ${(group['topics'] as List).join(', ')} bleibt für später gespeichert. Heute wird daraus kein zusätzlicher Pflichtauftrag.',
                  ),
              if (!parent)
                const Notice(
                  'Deine Eltern sehen die Heftseiten, Aufgaben, Antworten und verwendeten Hinweise. Nach einer Pause oder späteren Wiederholung kannst du hier wieder einsteigen.',
                ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => openRoute(context, '/app'),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Zur Tagesübersicht'),
            ),
          ],
        ],
      ),
    );
  }
}
