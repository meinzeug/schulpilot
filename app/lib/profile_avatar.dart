import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';

/// Decorative, own-account avatar. Private bytes never become an image URL or
/// persisted cache; the enclosing account control owns its accessible label.
class ProfileAvatar extends StatefulWidget {
  final AppState state;
  final double size;
  const ProfileAvatar(this.state, {super.key, this.size = 36});
  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Object? binding;
  MemoryImage? image;
  int generation = 0;
  Object get currentBinding => (
    widget.state,
    ObjectKey(widget.state.user),
    widget.state.familyId,
    widget.state.api.token,
    widget.state.profileAvatarRevision,
    widget.state.hasProfileAvatar,
  );

  @override
  void initState() {
    super.initState();
    widget.state.addListener(changed);
    reload();
  }

  void discard() {
    generation++;
    final old = image;
    image = null;
    if (old != null) unawaited(old.evict());
  }

  void changed() {
    if (!mounted || binding == currentBinding) return;
    setState(reload);
  }

  void reload() {
    discard();
    binding = currentBinding;
    if (widget.state.hasProfileAvatar) unawaited(load());
  }

  Future<void> load() async {
    final stamp = generation, scope = binding;
    try {
      final bytes = await widget.state.loadProfileAvatar();
      if (!mounted ||
          stamp != generation ||
          binding != scope ||
          currentBinding != scope) {
        return;
      }
      setState(() => image = MemoryImage(bytes));
    } catch (_) {
      // A failed private image never hides the account control or exposes bytes.
    }
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.removeListener(changed);
      widget.state.addListener(changed);
    }
    if (binding != currentBinding) reload();
  }

  @override
  void dispose() {
    widget.state.removeListener(changed);
    discard();
    super.dispose();
  }

  Widget fallback() {
    final name = (widget.state.user?['display_name'] as String?)?.trim();
    final initial = name == null || name.isEmpty
        ? 'K'
        : name.characters.first.toUpperCase();
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/brand/schulpilot-avatar-header.png',
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF202C34),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: EdgeInsets.all(widget.size * .12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                initial,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.size * .43,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      key: const ValueKey('profile-avatar'),
      dimension: widget.size,
      child: ClipOval(
        child: image == null
            ? fallback()
            : Image(
                image: image!,
                fit: BoxFit.cover,
                gaplessPlayback: false,
                errorBuilder: (_, _, _) => fallback(),
              ),
      ),
    ),
  );
}
