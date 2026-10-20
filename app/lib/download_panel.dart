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
      if (release['available'] != true) return SizedBox.shrink();
      return Panel(
        padding: EdgeInsets.all(22),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 24,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 230,
              child: Row(
                children: [
                  Icon(
                    Icons.android_rounded,
                    color: context.palette.teal,
                    size: 28,
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Schulpilot für Android',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ActionButton(
              label: 'Android-App herunterladen',
              icon: Icons.download_rounded,
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
          ],
        ),
      );
    },
  );
}
