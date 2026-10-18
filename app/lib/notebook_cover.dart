import 'package:flutter/material.dart';

const notebookCoverKeys = {
  'biologie',
  'mathematik',
  'englisch',
  'deutsch',
  'physik',
  'chemie',
  'geschichte',
  'geographie',
  'franzoesisch',
  'latein',
  'spanisch',
  'musik',
  'sachunterricht',
  'deutsch-als-zweitsprache',
  'lern-und-arbeitstechniken',
  'kreativitaet-und-bewegung',
  'sport',
  'kunst',
  'ethik',
  'religion',
  'informatik',
  'technik',
  'wirtschaft',
  'gemeinschaftskunde',
};

/// The server's public cover key is never interpolated as an arbitrary path.
String notebookCoverPath(String? key) =>
    'assets/folders/${notebookCoverKeys.contains(key) ? key : 'mein-heft'}.webp';

class NotebookCover extends StatelessWidget {
  final String? coverKey;
  const NotebookCover(this.coverKey, {super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      notebookCoverPath(coverKey),
      fit: BoxFit.contain,
      cacheWidth: 512,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.folder_outlined, size: 64)),
    ),
  );
}
