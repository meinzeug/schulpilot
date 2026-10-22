import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ui.dart';
import 'api.dart';
import 'app_version.dart';

class PublicSupportContact extends StatefulWidget {
  final String email;
  const PublicSupportContact(this.email, {super.key});
  @override
  State<PublicSupportContact> createState() => _PublicSupportContactState();
}

class _PublicSupportContactState extends State<PublicSupportContact> {
  bool busy = false;
  String? error;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(widget.email) &&
          widget.email.length <= 254)
        TextButton.icon(
          onPressed: busy
              ? null
              : () async {
                  if (busy) return;
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    if (!await launchUrl(
                      Uri(scheme: 'mailto', path: widget.email),
                      mode: LaunchMode.externalApplication,
                    )) {
                      throw StateError('Unavailable mail handler');
                    }
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => error = 'Dein E-Mail-Programm konnte nicht geöffnet werden. Übernimm die angezeigte Supportadresse selbst; es wurde keine Nachricht gesendet.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          icon: const Icon(Icons.mail_outline),
          label: Text(
            busy ? 'E-Mail-Programm wird geöffnet …' : 'Support-E-Mail öffnen',
          ),
        ),
      if (error != null)
        Semantics(liveRegion: true, child: Notice(error!, warning: true)),
    ],
  );
}

/// All text remains public and local. Search and section navigation never send
/// the query or selected paragraph to the server.
class PrivacyReadingPanel extends StatefulWidget {
  final String text;
  final String? initialSection;
  final String publicOrigin;
  final Api? legalApi;
  final Future<void> Function(Uint8List)? save;
  const PrivacyReadingPanel({
    super.key,
    required this.text,
    this.initialSection,
    required this.publicOrigin,
    this.legalApi,
    this.save,
  });
  @override
  State<PrivacyReadingPanel> createState() => _PrivacyReadingPanelState();
}

class _PrivacyReadingPanelState extends State<PrivacyReadingPanel> {
  static const labels = <String, (String, String)>{
    'zugang': ('Eltern und Kinder haben', 'Eigene Zugänge und Familienrechte'),
    'testraum': ('Im öffentlichen Testraum', 'Künstlicher Testraum'),
    'ki': ('Echte Lerninhalte werden', 'Lerninhalte und KI'),
    'heftfragen': ('Fragen zum Heft', 'Heftfragen und Sprache'),
    'fotos': ('Fotos werden vor', 'Fotos und lokale Warteschlange'),
    'google': ('Die Google-Anmeldung', 'Freiwillige Google-Anmeldung'),
    'loeschen': ('Sitzungen sind widerrufbar', 'Widerruf, Export und Löschung'),
    'noten': ('Eltern können freiwillig Schulnoten', 'Private Schulnoten'),
    'lerntipps': ('Freiwillige Lerntipps', 'Externe Lerntipps'),
    'aufbewahrung': ('Aufbewahrung:', 'Aufbewahrungsfristen'),
    'push': (
      'Benachrichtigungen sind freiwillig',
      'Freiwillige Benachrichtigungen',
    ),
    'bestellungen': ('Bei einer Bestellung', 'Bestellungen und Zahlungsbelege'),
    'grenzen': ('Es gibt keine Werbung', 'Grenzen und Transparenz'),
  };
  final search = TextEditingController();
  final top = GlobalKey();
  final keys = <String, GlobalKey>{};
  final focuses = <String, FocusNode>{};
  String query = '', selected = '';
  String? copyResult;
  bool exporting = false;
  String? exportResult;

  Future<void> exportPrivacy() async {
    if (!mounted || exporting || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    setState(() {
      exporting = true;
      exportResult = null;
    });
    try {
      final legal = await (widget.legalApi ?? Api()).get('/legal');
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      final contact = legal['complete'] == true
          ? 'Verantwortlicher Betreiber: ${legal['operator']}\n${legal['address']}\nSupport: ${legal['support_email']}'
          : 'Betreiber- und Kontaktangaben sind in der öffentlichen Antwort noch nicht vollständig.';
      final text =
          'SCHULPILOT – Datenschutz & Transparenz\nTextstand der App: $appVersion\nÖffentliche Quelle: ${Uri.tryParse(widget.publicOrigin)?.origin ?? 'nicht verfügbar'}/privacy\n\n$contact\n\n${widget.text}\n';
      final bytes = Uint8List.fromList(utf8.encode(text));
      final save = widget.save;
      if (save != null) {
        await save(bytes);
      } else {
        await FileSaver.instance.saveFile(
          name: 'schulpilot-datenschutz',
          bytes: bytes,
          fileExtension: 'txt',
          mimeType: MimeType.text,
        );
      }
      if (mounted) {
        setState(
          () => exportResult = 'Die vollständigen angezeigten Datenschutztexte und geladenen öffentlichen Kontaktangaben wurden an den Speicherdialog übergeben. Prüfe die lokale Datei selbst.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => exportResult = 'Die Datenschutztexte konnten gerade nicht gespeichert werden. Hier weiterlesen oder später bewusst erneut versuchen.',
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  late List<(String, String, String)> parts;
  void prepare() {
    parts = widget.text
        .split(RegExp(r'\n\s*\n'))
        .where((s) => s.trim().isNotEmpty)
        .indexed
        .map((e) {
          final matched = labels.entries
              .where((row) => e.$2.startsWith(row.value.$1))
              .firstOrNull;
          final id = matched?.key ?? 'abschnitt-${e.$1 + 1}';
          keys.putIfAbsent(id, () => GlobalKey());
          focuses.putIfAbsent(id, () => FocusNode());
          return (id, matched?.value.$2 ?? 'Abschnitt ${e.$1 + 1}', e.$2);
        })
        .toList();
  }

  @override
  void initState() {
    super.initState();
    prepare();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.initialSection != null) {
        open(widget.initialSection!);
      }
    });
  }

  @override
  void didUpdateWidget(covariant PrivacyReadingPanel old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) prepare();
    if (old.initialSection != widget.initialSection &&
        widget.initialSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) open(widget.initialSection!);
      });
    }
  }

  void open(String id) {
    if (!parts.any((p) => p.$1 == id)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      selected = id;
      query = '';
      search.clear();
      copyResult = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = keys[id]?.currentContext;
      if (mounted && target != null) {
        focuses[id]?.requestFocus();
        Scrollable.ensureVisible(target, alignment: .05);
      }
    });
  }

  @override
  void dispose() {
    search.dispose();
    for (final f in focuses.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = parts
        .where((p) => '${p.$2} ${p.$3}'.toLowerCase().contains(query))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(key: top),
        OutlinedButton.icon(
          onPressed: exporting ? null : exportPrivacy,
          icon: const Icon(Icons.download_outlined),
          label: Text(
            exporting
                ? 'Datenschutztexte werden übergeben …'
                : 'Datenschutztexte mit Kontaktangaben speichern',
          ),
        ),
        if (exportResult != null)
          Semantics(liveRegion: true, child: Notice(exportResult!)),
        TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onChanged: (value) => setState(() {
            query = value.trim().toLowerCase();
            copyResult = null;
          }),
          decoration: InputDecoration(
            labelText: 'Datenschutz auf dieser Seite durchsuchen',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Datenschutzsuche leeren',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() {
                        query = '';
                        search.clear();
                      });
                    },
                  ),
          ),
        ),
        ExpansionTile(
          title: const Text('Datenschutz: direkt zum Abschnitt'),
          children: [
            for (final part in parts)
              ListTile(
                title: Text(part.$2),
                trailing: const Icon(Icons.arrow_downward),
                onTap: () => open(part.$1),
              ),
          ],
        ),
        if (query.isNotEmpty)
          Semantics(
            liveRegion: true,
            child: Text(
              '${shown.length} von ${parts.length} Abschnitten enthalten deine Suche. Nur öffentliche Texte auf diesem Gerät werden durchsucht.',
            ),
          ),
        if (shown.isEmpty)
          const Notice(
            'Kein Datenschutzabschnitt passt zur Suche. Suche leeren, um alle Informationen wieder zu lesen.',
          ),
        if (widget.initialSection != null &&
            !parts.any((p) => p.$1 == widget.initialSection))
          const Notice(
            'Dieser Datenschutzabschnitt wurde nicht gefunden. Alle vorhandenen Abschnitte bleiben hier zugänglich.',
          ),
        if (copyResult != null)
          Semantics(liveRegion: true, child: Notice(copyResult!)),
        for (final part in shown)
          Padding(
            key: keys[part.$1],
            padding: const EdgeInsets.only(top: 24),
            child: Focus(
              focusNode: focuses[part.$1],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      part.$2,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(part.$3),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.link),
                        label: Text('Link: ${part.$2}'),
                        onPressed: () async {
                          final base = Uri.tryParse(widget.publicOrigin);
                          if (base == null ||
                              base.scheme != 'https' ||
                              base.host.isEmpty) {
                            return;
                          }
                          try {
                            await Clipboard.setData(
                              ClipboardData(
                                text: Uri(
                                  scheme: base.scheme,
                                  host: base.host,
                                  port: base.hasPort ? base.port : null,
                                  path: '/privacy',
                                  queryParameters: {'section': part.$1},
                                ).toString(),
                              ),
                            );
                            if (mounted) {
                              setState(
                                () => copyResult =
                                    'Öffentlicher Link zu „${part.$2}“ kopiert. Er enthält keine Kontodaten.',
                              );
                            }
                          } catch (_) {
                            if (mounted) {
                              setState(
                                () => copyResult = 'Der öffentliche Link konnte nicht kopiert werden. Du kannst den Abschnitt hier weiterlesen.',
                              );
                            }
                          }
                        },
                      ),
                      TextButton(
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          final target = top.currentContext;
                          if (target != null) {
                            Scrollable.ensureVisible(target, alignment: .05);
                          }
                        },
                        child: const Text('Zur Abschnittsauswahl'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
