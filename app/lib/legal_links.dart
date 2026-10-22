import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public legal documents never receive an app token, order ID or child data.
Future<bool> openPublicLegalDocument(String path, String apiBase) async {
  if (!const ['/impressum', '/widerrufen'].contains(path)) return false;
  final origin = kIsWeb ? Uri.base : Uri.tryParse(apiBase);
  if (origin == null || origin.host.isEmpty ||
      (!kIsWeb && origin.scheme != 'https') ||
      (kIsWeb && !const ['http', 'https'].contains(origin.scheme))) {
    return false;
  }
  final uri = Uri(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
    path: path,
  );
  try {
    return await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
  } catch (_) {
    return false;
  }
}

class PublicLegalLinks extends StatelessWidget {
  final String apiBase;
  const PublicLegalLinks(this.apiBase, {super.key});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    children: [
      for (final item in const [
        ('/impressum', 'Impressum'),
        ('/widerrufen', 'Vertrag widerrufen'),
      ])
        TextButton(
          onPressed: () async {
            final opened = await openPublicLegalDocument(item.$1, apiBase);
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Die Seite konnte nicht geöffnet werden. Bitte im Webbrowser erneut versuchen.')),
              );
            }
          },
          child: Text(item.$2),
        ),
    ],
  );
}
