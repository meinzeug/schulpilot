import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'ui.dart';

class AndroidDownload extends StatelessWidget {
  final Api api;
  const AndroidDownload(this.api, {super.key});

  @override
  Widget build(BuildContext context) => LoadView<Json>(
    revision: api,
    load: () => api.get('/app-release'),
    builder: (release, _) {
      if (release['available'] != true) return SizedBox.shrink();
      return ActionPanel(
        padding: const EdgeInsets.all(22),
        actionLabel: 'Android-App herunterladen',
        onPressed: () async {
          final uri = Uri.tryParse(release['download_url'] as String? ?? '');
          final origin = Uri.tryParse(api.base);
          if (uri == null ||
              origin == null ||
              uri.scheme != 'https' ||
              uri.host != origin.host ||
              uri.port != origin.port ||
              uri.userInfo.isNotEmpty ||
              uri.fragment.isNotEmpty ||
              uri.path != '/downloads/schulpilot-android.apk') {
            throw ApiError(
              'Die Downloadadresse ist nicht gültig. Bitte lade den aktuellen Stand neu.',
            );
          }
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            throw ApiError('Der Download konnte nicht geöffnet werden.');
          }
        },
        child: Row(
          children: [
            Icon(Icons.android_rounded, color: context.palette.teal, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                [
                  'SchuleSchlau für Android',
                  if (release['version'] is String)
                    'Version ${release['version']}',
                  if (release['size_bytes'] is num && release['size_bytes'] > 0)
                    '${NumberFormat('0.0', 'de').format(release['size_bytes'] / (1024 * 1024))} MB',
                  if (release['min_android'] is String)
                    'Ab Android ${release['min_android']}',
                ].join(' · '),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
          ],
        ),
      );
    },
  );
}
