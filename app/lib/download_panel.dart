import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'ui.dart';

class AndroidDownload extends StatelessWidget {
  final Api api;
  const AndroidDownload(this.api, {super.key});

  @override
  Widget build(BuildContext context) => LoadView<Json>(
    load: () => api.get('/app-release'),
    builder: (release, _) {
      if (release['available'] != true) return const SizedBox.shrink();
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading('SCHULPILOT für Android'),
            Text(
              'Version ${release['version']} · ${((release['size_bytes'] as num) / 1048576).toStringAsFixed(1)} MB · Android ${release['min_android']}+',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 12),
            const Text(
              'Installierbare Testversion mit derselben HTTPS-API und denselben Zugängen wie im Web.',
            ),
            const SizedBox(height: 16),
            ActionButton(
              label: 'Android-APK herunterladen',
              icon: Icons.android_rounded,
              onPressed: () async {
                final uri = Uri.parse(release['download_url'] as String);
                if (!await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                )) {
                  throw ApiError('Der Download konnte nicht geöffnet werden.');
                }
              },
            ),
            const SizedBox(height: 12),
            SelectableText(
              'SHA-256: ${release['sha256']}',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          ],
        ),
      );
    },
  );
}
