import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// A deliberate normal reserved job. Viewing this card only reads saved state.
class VisualPreparationCard extends StatefulWidget {
  final AppState state;
  final Json unit;
  final bool Function() isCurrent;
  final Future<void> Function() refresh;
  const VisualPreparationCard({
    super.key,
    required this.state,
    required this.unit,
    required this.isCurrent,
    required this.refresh,
  });
  @override
  State<VisualPreparationCard> createState() => _VisualPreparationCardState();
}

class _VisualPreparationCardState extends State<VisualPreparationCard> {
  bool busy = false, dispatched = false;
  Object? error;
  String? requestKey;
  late final Json? owner = widget.state.user;
  late final String? ownerToken = widget.state.api.token,
      ownerFamily = widget.state.familyId;
  bool get current =>
      mounted &&
      widget.isCurrent() &&
      identical(widget.state.user, owner) &&
      widget.state.api.token == ownerToken &&
      widget.state.familyId == ownerFamily &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
  @override
  void didUpdateWidget(covariant VisualPreparationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unit['visual_preparation'] is Map &&
        ![
          'queued',
          'running',
        ].contains(widget.unit['visual_preparation']['status'])) {
      dispatched = false;
    }
    if (widget.unit['visual_preparation'] is Map &&
        widget.unit['visual_preparation']['status'] == 'failed' &&
        (oldWidget.unit['visual_preparation'] is! Map ||
            oldWidget.unit['visual_preparation']['status'] != 'failed')) {
      requestKey = null;
    }
  }

  Future<void> prepare() async {
    if (busy || !current || ModalRoute.of(context)?.isCurrent == false) return;
    final owner = widget.state.user,
        token = widget.state.api.token,
        family = widget.state.familyId;
    final snapshot = widget.unit;
    bool requestCurrent() =>
        current &&
        identical(widget.unit, snapshot) &&
        identical(widget.state.user, owner) &&
        widget.state.api.token == token &&
        widget.state.familyId == family;
    setState(() => busy = true);
    requestKey ??=
        'visual-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    try {
      final job = await widget.state.api.post(
        '/units/${snapshot['id']}/visual-explanation',
        null,
        {'Idempotency-Key': requestKey!},
      );
      if (requestCurrent()) {
        setState(
          () => dispatched = ['queued', 'running'].contains(job['status']),
        );
      }
      if (requestCurrent()) await widget.refresh();
    } catch (e) {
      if (requestCurrent()) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final renderedUnit = widget.unit;
    final status = widget.unit['explanation_visual_status'];
    if (status == null || status == 'ready') return const SizedBox.shrink();
    final job = widget.unit['visual_preparation'];
    final pending =
        dispatched ||
        job is Map && ['queued', 'running'].contains(job['status']);
    final failed = job is Map && job['status'] == 'failed';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pending
                ? 'Grafische Erklärung wird vorbereitet …'
                : status == 'legacy_text'
                ? 'Gespeicherte Texterklärung · Grafikschritte fehlen noch.'
                : 'Die grafische Erklärung ist noch nicht vollständig quellengebunden verfügbar.',
            key: const ValueKey('visual-readiness'),
            style: TextStyle(color: context.palette.muted, fontSize: 14),
          ),
          if (!pending &&
              widget.unit['synthetic'] != true &&
              widget.unit['can_prepare_visual'] != false)
            TextButton.icon(
              onPressed: busy || !current
                  ? null
                  : () {
                      if (identical(widget.unit, renderedUnit)) prepare();
                    },
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                busy
                    ? 'Wird angefragt …'
                    : failed
                    ? 'Grafische Erklärung erneut anfragen'
                    : 'Grafische Erklärung vorbereiten',
              ),
            ),
          if (pending)
            const Text(
              'Deine gespeicherten Aufgaben und Antworten bleiben erhalten.',
            ),
          if (error != null) Notice(error.toString(), warning: true),
        ],
      ),
    );
  }
}
