import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

Future<void> showParentChildExport(
  BuildContext context,
  AppState state,
  Json child,
) async {
  if (!context.mounted || !state.isParent || state.familyId == null) return;
  final account = state.user, family = state.familyId;
  bool current() =>
      context.mounted &&
      identical(account, state.user) &&
      family == state.familyId &&
      state.isParent;
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _Export(state, child: Json.from(child), current: current),
  );
  void changed() {
    if (current()) return;
    Future<void>.microtask(() {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  state.addListener(changed);
  try {
    await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
  } finally {
    state.removeListener(changed);
  }
}

class _Export extends StatefulWidget {
  final AppState state;
  final Json child;
  final bool Function() current;
  const _Export(this.state, {required this.child, required this.current});
  @override
  State<_Export> createState() => _ExportState();
}

class _ExportState extends State<_Export> {
  bool busy = false, saved = false, includePhotos = true;
  String? error;
  Future<void> save() async {
    if (!mounted ||
        !widget.current() ||
        busy ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final bytes = await widget.state.api.bytes(
        Uri(
          path: '/children/${widget.child['id']}/export',
          queryParameters: {'include_photos': '$includePhotos'},
        ).toString(),
      );
      if (!mounted || !widget.current()) return;
      final result = await FileSaver.instance.saveAs(
        name: 'schulpilot-kinderexport',
        bytes: bytes,
        fileExtension: 'zip',
        mimeType: MimeType.zip,
      );
      if (mounted && widget.current()) setState(() => saved = result != null);
    } catch (e) {
      if (mounted && widget.current()) {
        setState(
          () => error = e is ApiError ? e.message : 'Die private Datei konnte nicht gespeichert werden. Die Daten in der App bleiben erhalten.',
        );
      }
    } finally {
      if (mounted && widget.current()) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: Text('Daten von ${widget.child['display_name']} exportieren'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.child['username'] is String)
              Text('Kinderzugang: ${widget.child['username']}'),
            const Text(
              'Die ZIP-Datei enthält ausschließlich diesen Kinderzugang: Materialtexte und Metadaten, Lernaufträge, Runden und Antworten, Hilfen, Nachrichten, Wörter, Schulnoten und gespeicherte Elternberichte.',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: includePhotos,
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      includePhotos = v == true;
                      saved = false;
                    }),
              title: const Text('Persönliche Bilddateien mitnehmen'),
              subtitle: const Text(
                'Abwählen spart Dateigröße und überträgt nur die gespeicherten Texte, Belege und Metadaten. Bilddateien sind dann nicht in der Kopie enthalten.',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Daten anderer Kinder, Elternpasswörter, Gerätezugänge und Familienbestellungen werden nicht übernommen. Bewahre die Datei sicher auf und prüfe sie vor einer Weitergabe.',
            ),
            if (error != null)
              Semantics(liveRegion: true, child: Notice(error!, warning: true)),
            if (saved)
              const Notice(
                'Der Kinderexport wurde gespeichert. Der Zugang und alle Lerndaten bleiben in der App erhalten.',
              ),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy
              ? null
              : () {
                  if (context.mounted &&
                      widget.current() &&
                      ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.pop(context);
                  }
                },
          child: const Text('Schließen'),
        ),
        FilledButton.icon(
          onPressed: busy ? null : save,
          icon: const Icon(Icons.download_outlined),
          label: Text(
            busy
                ? 'Export wird gespeichert …'
                : saved
                ? 'Erneut speichern'
                : 'Kinderexport ausdrücklich speichern',
          ),
        ),
      ],
    ),
  );
}
